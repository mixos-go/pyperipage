"""
barcode_detect.py (Android implementation)

GANTI ARSITEKTUR (Juli 2026): sama seperti transport_usb.py/transport_ble.py
-- `pyzbar` butuh library native `libzbar` yang TIDAK bisa dipasang di
Android lewat Chaquopy (kelas masalah yang sama persis dengan
pymupdf/pyusb/bleak sebelumnya: butuh native code yang tidak tersedia di
lingkungan Chaquopy). Implementasi di sini delegasi ke ZXing (Java, pure
JVM, TIDAK butuh native code apa pun) lewat NativeBarcodeDetector.kt.

Fungsi & signature SENGAJA sama persis dengan versi desktop
(library/peripage_a9/barcode_detect.py) supaya python_service.py bisa
panggil `from peripage_a9.barcode_detect import has_barcode` tanpa peduli
platform di baliknya -- kontrak yang identik, implementasi yang berbeda.
"""
import io
from typing import Optional
from PIL import Image

from com.pyperipage import NativeBarcodeDetector


def has_barcode(pil_image: Image.Image) -> bool:
    """True kalau gambar mengandung minimal 1 barcode/QR yang terdeteksi
    ZXing (CODE_128, CODE_39, EAN_13, QR_CODE, PDF_417, DATA_MATRIX, dll)."""
    buffer = io.BytesIO()
    pil_image.convert("RGB").save(buffer, format="PNG")
    png_bytes = buffer.getvalue()
    try:
        return bool(NativeBarcodeDetector.hasBarcode(bytearray(png_bytes)))
    except Exception:
        # Kegagalan native call (mis. bitmap decode gagal) di-treat sebagai
        # "tidak ada barcode" -- konsisten dengan perilaku versi desktop.
        return False


def barcode_availability_error() -> Optional[str]:
    """Android selalu punya ZXing bundled (pure Java, Gradle dependency) --
    tidak pernah unavailable seperti pyzbar/libzbar di desktop."""
    return None
