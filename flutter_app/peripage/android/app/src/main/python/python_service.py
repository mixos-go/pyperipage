"""
Python Service Entry Point for Chaquopy Android Integration
Bridges Flutter Dart code (ApiService) dengan Python printing logic asli.

PENTING: fungsi di file ini dipanggil LANGSUNG oleh MainActivity.kt lewat
Chaquopy (bukan lewat HTTP/server). Nama & parameter fungsi di sini harus
sinkron dengan method channel handler di MainActivity.kt.

Perbaikan dari versi sebelumnya:
- Sebelumnya file ini mengimpor `PeriPageDriver` yang TIDAK PERNAH ADA di
  peripage_a9/driver.py (cuma ada `PeriPageA9USB` dan `PeriPageA9BLE`) --
  ini bikin ImportError setiap kali Chaquopy coba load modul ini.
- Fungsi print_text/feed_paper/cut_paper dihapus karena protokol PeriPage A9
  kita HANYA mendukung cetak gambar (smart_crop_and_resize + print_pages),
  tidak ada mode teks langsung atau perintah potong kertas terpisah di
  protocol.py manapun (USB maupun BLE).
- print_pdf sekarang benar-benar merender halaman PDF jadi gambar pakai
  PyMuPDF (fitz), BUKAN base64 pass-through kosong seperti sebelumnya.
"""
import base64
import io
import traceback

from PIL import Image

from peripage_a9.driver import PeriPageA9USB, PeriPageA9BLE
from peripage_a9 import protocol

# Instance driver aktif (USB atau BLE), None kalau belum connect
_driver = None
_transport_type = "usb"


def _err(e: Exception) -> dict:
    traceback.print_exc()
    return {"status": "error", "message": str(e)}


def connect_usb() -> dict:
    """Connect ke printer via USB. Menyesuaikan bentuk return ApiService.connectUsb()."""
    global _driver, _transport_type
    try:
        _transport_type = "usb"
        _driver = PeriPageA9USB()
        ok = _driver.connect()
        if not ok:
            _driver = None
            return {"status": "error", "message": "Printer USB tidak ditemukan / gagal klaim endpoint."}
        return {"status": "ok", "connected": True, "transport_type": "usb"}
    except Exception as e:
        return _err(e)


def connect_ble(device_address: str = None) -> dict:
    """Connect ke printer via BLE. device_address boleh None (auto-discovery by name)."""
    global _driver, _transport_type
    try:
        _transport_type = "ble"
        _driver = PeriPageA9BLE(device_address=device_address)
        ok = _driver.connect()
        if not ok:
            _driver = None
            return {"status": "error", "message": "Printer BLE tidak ditemukan / gagal connect."}
        return {"status": "ok", "connected": True, "transport_type": "ble"}
    except Exception as e:
        return _err(e)


def discover_ble_devices(timeout: float = 5.0) -> dict:
    """Scan device BLE di sekitar. Dipakai ApiService.discoverBleDevices()."""
    try:
        from peripage_a9.transport_ble import BleTransportSync
        found = BleTransportSync().discover_devices(timeout=timeout)
        return {"devices": found}
    except Exception as e:
        return _err(e)


def get_printer_status() -> dict:
    """Dipakai ApiService.getPrinterStatus() -> PrinterStatus.fromJson()."""
    connected = _driver is not None and getattr(_driver, "_transport", None) is not None
    return {
        "connected": connected,
        "transport_type": _transport_type,
        "paper_width_mm": _driver.paper_width_mm if _driver else protocol.load_paper_width_mm(),
        "message": "Terhubung" if connected else "Belum terhubung",
    }


def get_config() -> dict:
    """Dipakai ApiService.getConfig() -> PrinterConfig.fromJson()."""
    width = _driver.paper_width_mm if _driver else protocol.load_paper_width_mm()
    return {
        "supported_paper_widths": protocol.SUPPORTED_PAPER_WIDTHS_MM,
        "default_paper_width": protocol.DEFAULT_PAPER_WIDTH_MM,
        "current_paper_width": width,
        "pdf_support": True,
        "transport_types": ["usb", "ble"],
    }


def set_paper_width(width_mm: int) -> dict:
    """Dipakai ApiService.setPaperWidth()."""
    try:
        if _driver:
            _driver.set_paper_width(width_mm)
        else:
            protocol.save_paper_width_mm(width_mm)
        return {"status": "ok"}
    except Exception as e:
        return _err(e)


def _image_to_base64_png(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("ascii")


def preview_image(image_path: str, paper_width_mm: int = None) -> dict:
    """Dipakai ApiService.previewImage() -- return base64 PNG hasil smart-crop,
    TANPA mengirim apapun ke printer (murni preview)."""
    try:
        width = paper_width_mm or (_driver.paper_width_mm if _driver else protocol.load_paper_width_mm())
        img = Image.open(image_path)
        cropped = protocol.smart_crop_and_resize(img, width)
        return {"status": "ok", "image_base64": _image_to_base64_png(cropped)}
    except Exception as e:
        return _err(e)


def print_image(image_path: str, paper_width_mm: int = None) -> dict:
    """Dipakai ApiService.printImage(File)."""
    global _driver
    if _driver is None:
        return {"status": "error", "message": "Printer belum terhubung."}
    try:
        if paper_width_mm:
            _driver.set_paper_width(paper_width_mm)
        img = Image.open(image_path)
        cropped = _driver.smart_crop_and_resize(img)
        _driver.print_pages([0], {0: cropped})
        return {"status": "ok"}
    except Exception as e:
        return _err(e)


def print_pdf(pdf_path: str, pages: list, paper_width_mm: int = None) -> dict:
    """
    Dipakai ApiService.printPdf(File, List<int> pages).

    CATATAN PENTING: app desktop asli pakai pdf2image (butuh binary poppler),
    yang TIDAK TERSEDIA di Android. Di sini dipakai PyMuPDF (fitz) untuk
    rasterisasi halaman PDF jadi gambar -- pure Python wheel, tidak butuh
    binary sistem eksternal.

    BELUM DIVALIDASI di device Android fisik apakah wheel `pymupdf` untuk
    arch arm64-v8a/x86_64 berhasil ditarik Chaquopy saat build -- ini perlu
    dites langsung sebelum dianggap beres. Kalau gagal, alternatif fallback:
    render PDF->gambar di sisi Dart pakai package `pdfx` / `printing`
    sebelum kirim path gambar ke sini (bukan path PDF).
    """
    global _driver
    if _driver is None:
        return {"status": "error", "message": "Printer belum terhubung."}
    try:
        import fitz  # PyMuPDF
    except ImportError as e:
        return _err(Exception(
            "PyMuPDF (fitz) tidak tersedia di runtime Android ini. "
            f"Detail: {e}"
        ))

    try:
        if paper_width_mm:
            _driver.set_paper_width(paper_width_mm)

        doc = fitz.open(pdf_path)
        cropped_images = {}
        zoom = 3.0  # ~216 DPI, cukup buat thermal print resolution
        mat = fitz.Matrix(zoom, zoom)

        for idx in pages:
            page = doc.load_page(idx)
            pix = page.get_pixmap(matrix=mat)
            img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
            cropped_images[idx] = _driver.smart_crop_and_resize(img)

        doc.close()
        _driver.print_pages(pages, cropped_images)
        return {"status": "ok"}
    except Exception as e:
        return _err(e)


def print_batch(file_paths: list, paper_width_mm: int = None) -> dict:
    """Dipakai ApiService.printBatch(List<File>) -- cetak beberapa file gambar berurutan."""
    global _driver
    if _driver is None:
        return {"status": "error", "message": "Printer belum terhubung."}
    try:
        if paper_width_mm:
            _driver.set_paper_width(paper_width_mm)

        cropped_images = {}
        for idx, path in enumerate(file_paths):
            img = Image.open(path)
            cropped_images[idx] = _driver.smart_crop_and_resize(img)

        _driver.print_pages(list(range(len(file_paths))), cropped_images)
        return {"status": "ok"}
    except Exception as e:
        return _err(e)


def disconnect_printer() -> dict:
    global _driver
    if _driver and getattr(_driver, "_transport", None):
        try:
            _driver._transport.close()
        except Exception:
            pass
    _driver = None
    return {"status": "ok"}
