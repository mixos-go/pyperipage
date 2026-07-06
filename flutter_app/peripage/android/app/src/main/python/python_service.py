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
- print_pdf_pages (sebelumnya print_pdf) sekarang menerima gambar hasil
  render halaman PDF dari Dart (package `pdfx`), BUKAN merender PDF sendiri
  pakai PyMuPDF (fitz tidak bisa dipasang di Chaquopy Android) atau base64
  pass-through kosong seperti versi-versi sebelumnya.
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
_device_address = None  # MAC address BLE, atau None untuk USB
_device_name = None  # Nama device BLE hasil scan, atau None


def _err(e: Exception) -> dict:
    tb = traceback.format_exc()
    print(tb)
    # PENTING: sertakan traceback lengkap di response, BUKAN cuma print ke
    # logcat (yang percuma tanpa adb). Ini yang bikin "Lihat Detail" &
    # Log Aplikasi di UI sebelumnya SELALU kosong untuk error jenis ini
    # (beda dari error native Kotlin/PlatformException yang sudah benar
    # menyertakan stack trace).
    return {"status": "error", "message": str(e), "details": tb}


def connect_usb() -> dict:
    """Connect ke printer via USB. Menyesuaikan bentuk return ApiService.connectUsb()."""
    global _driver, _transport_type, _device_address, _device_name
    try:
        _transport_type = "usb"
        _driver = PeriPageA9USB()
        ok = _driver.connect()
        if not ok:
            _driver = None
            return {"status": "error", "message": "Printer USB tidak ditemukan / gagal klaim endpoint."}
        _device_address = None  # USB tidak punya konsep address kayak BLE MAC
        _device_name = "PeriPage A9 (USB)"
        return {"status": "ok", "connected": True, "transport_type": "usb"}
    except Exception as e:
        return _err(e)


def connect_ble(device_address: str = None, device_name: str = None) -> dict:
    """Connect ke printer via BLE. device_address boleh None (auto-discovery by name)."""
    global _driver, _transport_type, _device_address, _device_name
    try:
        _transport_type = "ble"
        _driver = PeriPageA9BLE(device_address=device_address)
        ok = _driver.connect()
        if not ok:
            _driver = None
            return {"status": "error", "message": "Printer BLE tidak ditemukan / gagal connect."}
        _device_address = device_address
        _device_name = device_name or "Printer BLE"
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
        "device_address": _device_address if connected else None,
        "device_name": _device_name if connected else None,
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


def preview_image(image_path: str, paper_width_mm: int = None, smart_crop: bool = True) -> dict:
    """Dipakai ApiService.previewImage() -- return base64 PNG hasil crop,
    TANPA mengirim apapun ke printer (murni preview). `smart_crop=False`
    kalau user pilih toggle "Manual Crop" di Print Screen."""
    try:
        width = paper_width_mm or (_driver.paper_width_mm if _driver else protocol.load_paper_width_mm())
        img = Image.open(image_path)
        if smart_crop:
            cropped = protocol.smart_crop_and_resize(img, width)
        else:
            cropped = protocol.resize_to_paper_width(img, width)
        return {"status": "ok", "image_base64": _image_to_base64_png(cropped)}
    except Exception as e:
        return _err(e)


def print_image(image_path: str, paper_width_mm: int = None, smart_crop: bool = True) -> dict:
    """Dipakai ApiService.printImage(File)."""
    global _driver
    if _driver is None:
        return {"status": "error", "message": "Printer belum terhubung."}
    try:
        if paper_width_mm:
            _driver.set_paper_width(paper_width_mm)
        img = Image.open(image_path)
        cropped = _driver.smart_crop_and_resize(img, use_smart_crop=smart_crop)
        _driver.print_pages([0], {0: cropped})
        return {"status": "ok"}
    except Exception as e:
        return _err(e)


def print_pdf_pages(image_paths: list, pages: list, paper_width_mm: int = None, smart_crop: bool = True) -> dict:
    """
    Dipakai ApiService.printPdf(File, List<int> pages) di Android/iOS.

    GANTI ARSITEKTUR (Juli 2026): sebelumnya fungsi ini bernama print_pdf()
    dan menerima path PDF mentah, lalu merender halamannya jadi gambar di
    sini pakai PyMuPDF (fitz). Itu TIDAK BISA jalan karena fitz tidak punya
    wheel untuk Android di Chaquopy, dan tidak bisa dikompilasi dari source
    di Android (butuh toolchain native C/C++ buat build MuPDF).

    Sekarang rasterisasi PDF->gambar dipindah ke sisi Dart (package `pdfx`,
    berbasis PDFium) SEBELUM data dikirim ke sini -- jadi fungsi ini cuma
    terima path gambar hasil render (satu file per halaman), persis seperti
    print_batch(), tapi indeks halamannya (`pages`) tetap dijaga sinkron
    dengan urutan asli di dokumen PDF (bukan cuma 0..N sekuensial).

    image_paths dan pages HARUS punya panjang yang sama & berpasangan index
    ke index -- image_paths[i] adalah hasil render dari pages[i].
    """
    global _driver
    if _driver is None:
        return {"status": "error", "message": "Printer belum terhubung."}
    if len(image_paths) != len(pages):
        return {"status": "error", "message": "image_paths dan pages harus punya panjang sama."}
    try:
        if paper_width_mm:
            _driver.set_paper_width(paper_width_mm)

        cropped_images = {}
        for page_idx, img_path in zip(pages, image_paths):
            img = Image.open(img_path)
            cropped_images[page_idx] = _driver.smart_crop_and_resize(img, use_smart_crop=smart_crop)

        _driver.print_pages(pages, cropped_images)
        return {"status": "ok"}
    except Exception as e:
        return _err(e)


def print_batch(file_paths: list, paper_width_mm: int = None, smart_crop: bool = True) -> dict:
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
            cropped_images[idx] = _driver.smart_crop_and_resize(img, use_smart_crop=smart_crop)

        _driver.print_pages(list(range(len(file_paths))), cropped_images)
        return {"status": "ok"}
    except Exception as e:
        return _err(e)


def disconnect_printer() -> dict:
    global _driver, _device_address, _device_name
    if _driver and getattr(_driver, "_transport", None):
        try:
            _driver._transport.close()
        except Exception:
            pass
    _driver = None
    _device_address = None
    _device_name = None
    return {"status": "ok"}
