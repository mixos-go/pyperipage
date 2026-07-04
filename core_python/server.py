"""
server.py

FastAPI server untuk jembatan komunikasi antara Python core (logic, protocol, transport)
dan Flutter UI. Server ini berjalan lokal dan menyediakan REST API untuk:
- Print PDF, gambar, label
- Preview smart crop
- Manajemen printer (USB/BLE)
- Setting kertas dan kalibrasi
"""
import os
import sys
import io
import base64
import traceback
import tempfile
from typing import List, Optional, Dict, Any
from pathlib import Path

from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel
import uvicorn
from PIL import Image

# Import core logic
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'core_python'))
from peripage_a9 import (
    PeriPageA9USB,
    PeriPageA9BLE,
    SUPPORTED_PAPER_WIDTHS_MM,
    DEFAULT_PAPER_WIDTH_MM,
    load_paper_width_mm,
    save_paper_width_mm,
    smart_crop_and_resize,
)

try:
    from pdf2image import convert_from_path
    PDF_SUPPORT = True
except ImportError:
    PDF_SUPPORT = False
    print("[SERVER WARNING] pdf2image tidak terinstall. Support PDF dinonaktifkan.")

# Inisialisasi FastAPI app
app = FastAPI(
    title="PeriPage A9 Print Server",
    description="API server untuk printer thermal PeriPage A9 dengan support USB dan BLE",
    version="2.0.0"
)

# CORS middleware untuk Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Untuk development. Production perlu dibatasi.
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global state
printer_usb = None
printer_ble = None
current_transport = "usb"  # "usb" atau "ble"


# =====================================================================
# MODELS
# =====================================================================

class PrinterStatus(BaseModel):
    connected: bool
    transport_type: str
    paper_width_mm: int
    message: str


class PrintRequest(BaseModel):
    pages: List[int]  # Index halaman yang akan dicetak (0-based)
    paper_width_mm: Optional[int] = None
    transport: Optional[str] = "usb"  # "usb" atau "ble"


class PaperWidthRequest(BaseModel):
    width_mm: int


class BleConnectRequest(BaseModel):
    device_address: Optional[str] = None


# =====================================================================
# HELPER FUNCTIONS
# =====================================================================

def image_to_base64(img: Image.Image, format: str = "PNG") -> str:
    """Convert PIL Image ke base64 string."""
    buffered = io.BytesIO()
    img.save(buffered, format=format)
    return base64.b64encode(buffered.getvalue()).decode("utf-8")


def base64_to_image(base64_str: str) -> Image.Image:
    """Convert base64 string ke PIL Image."""
    img_data = base64.b64decode(base64_str)
    return Image.open(io.BytesIO(img_data))


def get_printer():
    """Dapatkan instance printer aktif berdasarkan transport saat ini."""
    global printer_usb, printer_ble, current_transport
    
    if current_transport == "usb":
        if printer_usb is None:
            printer_usb = PeriPageA9USB()
        return printer_usb
    else:
        if printer_ble is None:
            printer_ble = PeriPageA9BLE()
        return printer_ble


# =====================================================================
# API ENDPOINTS
# =====================================================================

@app.get("/")
async def root():
    """Health check endpoint."""
    return {
        "status": "ok",
        "service": "PeriPage A9 Print Server",
        "version": "2.0.0",
        "pdf_support": PDF_SUPPORT
    }


@app.get("/api/status", response_model=PrinterStatus)
async def get_status():
    """Cek status koneksi printer."""
    printer = get_printer()
    
    # Coba detect koneksi (untuk USB)
    connected = False
    message = "Belum terhubung"
    
    if current_transport == "usb":
        # Untuk USB, coba detect device
        try:
            import usb.core
            dev = usb.core.find(idVendor=0x09c5, idProduct=0x0200)
            connected = dev is not None
            message = "Terdeteksi via USB" if connected else "Printer USB tidak ditemukan"
        except Exception as e:
            message = f"Error cek USB: {str(e)}"
    else:
        # Untuk BLE, cek apakah sudah pernah connect
        connected = printer._transport is not None and printer._transport._connected
        message = "Terhubung via BLE" if connected else "Belum terhubung via BLE"
    
    return PrinterStatus(
        connected=connected,
        transport_type=current_transport,
        paper_width_mm=load_paper_width_mm(),
        message=message
    )


@app.post("/api/connect/usb")
async def connect_usb():
    """Koneksi ke printer via USB."""
    global current_transport, printer_usb
    current_transport = "usb"
    printer_usb = PeriPageA9USB()
    
    success = printer_usb.connect()
    
    if success:
        return {"status": "success", "message": "Terhubung ke printer via USB"}
    else:
        raise HTTPException(status_code=400, detail="Gagal koneksi ke printer USB")


@app.post("/api/connect/ble")
async def connect_ble(request: Optional[BleConnectRequest] = None):
    """Koneksi ke printer via BLE."""
    global current_transport, printer_ble
    
    device_address = request.device_address if request else None
    current_transport = "ble"
    printer_ble = PeriPageA9BLE(device_address=device_address)
    
    success = printer_ble.connect()
    
    if success:
        return {"status": "success", "message": "Terhubung ke printer via BLE"}
    else:
        raise HTTPException(status_code=400, detail="Gagal koneksi ke printer BLE")


@app.post("/api/disconnect")
async def disconnect():
    """Putus koneksi printer aktif (USB atau BLE) & lepas resource transport.
    Dipakai SettingsScreen (Flutter) -- mirroring disconnect_printer() di
    python_service.py (jalur Android), supaya perilakunya konsisten lintas
    platform."""
    global printer_usb, printer_ble

    active = printer_usb if current_transport == "usb" else printer_ble
    if active is not None and getattr(active, "_transport", None) is not None:
        try:
            active._transport.close()
        except Exception:
            pass

    printer_usb = None
    printer_ble = None
    return {"status": "success", "message": "Printer terputus."}


@app.get("/api/ble/discover")
async def discover_ble_devices(timeout: float = 5.0):
    """Scan dan temukan device BLE di sekitar."""
    try:
        # Buat instance temporary untuk discovery
        ble_transport_module = __import__(
            'peripage_a9.transport_ble', 
            fromlist=['BleTransport']
        ).BleTransport()
        
        devices = await ble_transport_module.discover_devices(timeout=timeout)
        return {"devices": devices}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Gagal scan BLE: {str(e)}")


@app.post("/api/paper-width")
async def set_paper_width(request: PaperWidthRequest):
    """Set lebar kertas (58 atau 77mm)."""
    if request.width_mm not in SUPPORTED_PAPER_WIDTHS_MM:
        raise HTTPException(
            status_code=400, 
            detail=f"Lebar kertas tidak didukung. Pilihan: {SUPPORTED_PAPER_WIDTHS_MM}"
        )
    
    save_paper_width_mm(request.width_mm)
    return {
        "status": "success",
        "paper_width_mm": request.width_mm
    }


@app.get("/api/paper-width")
async def get_paper_width():
    """Dapatkan setting lebar kertas saat ini."""
    return {
        "paper_width_mm": load_paper_width_mm(),
        "supported_widths": SUPPORTED_PAPER_WIDTHS_MM
    }


@app.post("/api/preview/image")
async def preview_image(
    image: UploadFile = File(...),
    paper_width_mm: Optional[int] = None
):
    """
    Upload gambar dan dapatkan preview hasil smart crop.
    Return: gambar yang sudah di-crop dan di-resize sesuai lebar kertas.
    """
    try:
        # Baca gambar
        contents = await image.read()
        img = Image.open(io.BytesIO(contents))
        
        # Gunakan setting kertas saat ini jika tidak specified
        if paper_width_mm is None:
            paper_width_mm = load_paper_width_mm()
        
        # Smart crop dan resize
        cropped_img = smart_crop_and_resize(img, paper_width_mm)
        
        # Return sebagai PNG
        return Response(
            content=image_to_base64(cropped_img),
            media_type="image/png"
        )
        
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Gagal process preview: {str(e)}")


@app.post("/api/print/image")
async def print_image(
    image: UploadFile = File(...),
    paper_width_mm: Optional[int] = Form(None)
):
    """Print gambar langsung."""
    try:
        contents = await image.read()
        img = Image.open(io.BytesIO(contents))
        
        if paper_width_mm is None:
            paper_width_mm = load_paper_width_mm()
        
        printer = get_printer()
        
        # Set paper width
        printer.set_paper_width(paper_width_mm, persist=False)
        
        # Smart crop
        cropped_img = printer.smart_crop_and_resize(img)
        
        # Connect jika belum
        if not printer._transport:
            if not printer.connect():
                raise HTTPException(status_code=400, detail="Gagal koneksi ke printer")
        
        # Print
        printer.print_pages([0], {0: cropped_img})
        
        return {"status": "success", "message": "Gambar sukses dicetak"}
        
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Gagal print: {str(e)}")


@app.post("/api/print/pdf")
async def print_pdf(
    pdf_file: UploadFile = File(...),
    pages: str = Form(...),  # Comma-separated page indices, e.g., "0,1,2"
    paper_width_mm: Optional[int] = Form(None)
):
    """
    Print PDF. 
    pages: string comma-separated index halaman (0-based), e.g., "0,1,2" untuk halaman 1,2,3
    """
    if not PDF_SUPPORT:
        raise HTTPException(status_code=503, detail="PDF support tidak tersedia")
    
    try:
        # Parse pages
        page_indices = [int(p.strip()) for p in pages.split(",")]
        
        # Save PDF temporarily
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
            contents = await pdf_file.read()
            tmp.write(contents)
            tmp_path = tmp.name
        
        try:
            # Convert PDF to images
            raw_pages = convert_from_path(tmp_path, dpi=300)
            
            if paper_width_mm is None:
                paper_width_mm = load_paper_width_mm()
            
            printer = get_printer()
            printer.set_paper_width(paper_width_mm, persist=False)
            
            # Connect jika belum
            if not printer._transport:
                if not printer.connect():
                    raise HTTPException(status_code=400, detail="Gagal koneksi ke printer")
            
            # Smart crop semua halaman yang dipilih
            cropped_images = {}
            for idx in page_indices:
                if 0 <= idx < len(raw_pages):
                    cropped_images[idx] = printer.smart_crop_and_resize(raw_pages[idx])
            
            # Print
            printer.print_pages(page_indices, cropped_images)
            
            return {"status": "success", "message": f"Sukses cetak {len(page_indices)} halaman"}
            
        finally:
            # Cleanup temp file
            os.unlink(tmp_path)
            
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Gagal print PDF: {str(e)}")


@app.post("/api/print/batch")
async def print_batch(
    files: List[UploadFile] = File(...),
    paper_width_mm: Optional[int] = Form(None)
):
    """
    Print multiple files (gambar atau PDF) sekaligus.
    Mendukung mix antara gambar dan PDF.
    """
    try:
        if paper_width_mm is None:
            paper_width_mm = load_paper_width_mm()
        
        printer = get_printer()
        printer.set_paper_width(paper_width_mm, persist=False)
        
        # Connect jika belum
        if not printer._transport:
            if not printer.connect():
                raise HTTPException(status_code=400, detail="Gagal koneksi ke printer")
        
        all_images = []
        
        for file in files:
            contents = await file.read()
            
            if file.filename.lower().endswith('.pdf'):
                if not PDF_SUPPORT:
                    continue
                
                with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
                    tmp.write(contents)
                    tmp_path = tmp.name
                
                try:
                    raw_pages = convert_from_path(tmp_path, dpi=300)
                    for page in raw_pages:
                        all_images.append(printer.smart_crop_and_resize(page))
                finally:
                    os.unlink(tmp_path)
            else:
                # Gambar
                img = Image.open(io.BytesIO(contents))
                all_images.append(printer.smart_crop_and_resize(img))
        
        if not all_images:
            raise HTTPException(status_code=400, detail="Tidak ada halaman valid untuk dicetak")
        
        # Print semua
        pages_dict = {i: img for i, img in enumerate(all_images)}
        printer.print_pages(list(range(len(all_images))), pages_dict)
        
        return {"status": "success", "message": f"Sukses cetak {len(all_images)} halaman"}
        
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Gagal print batch: {str(e)}")


@app.get("/api/config")
async def get_config():
    """Dapatkan konfigurasi aplikasi."""
    return {
        "supported_paper_widths": SUPPORTED_PAPER_WIDTHS_MM,
        "default_paper_width": DEFAULT_PAPER_WIDTH_MM,
        "current_paper_width": load_paper_width_mm(),
        "pdf_support": PDF_SUPPORT,
        "transport_types": ["usb", "ble"]
    }


# =====================================================================
# MAIN
# =====================================================================

if __name__ == "__main__":
    print("=" * 60)
    print("PeriPage A9 Print Server")
    print("=" * 60)
    print(f"PDF Support: {'Yes' if PDF_SUPPORT else 'No'}")
    print(f"Supported paper widths: {SUPPORTED_PAPER_WIDTHS_MM}mm")
    print("=" * 60)
    print("Starting server at http://localhost:8000")
    print("API docs available at http://localhost:8000/docs")
    print("=" * 60)
    
    uvicorn.run(app, host="0.0.0.0", port=8000)
