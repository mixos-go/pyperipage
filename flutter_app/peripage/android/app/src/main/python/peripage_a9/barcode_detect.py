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
import traceback
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
        # FIX (Juli 2026): Kotlin `object` (singleton) HARUS diakses lewat
        # `.INSTANCE` dari Chaquopy -- diekspos sebagai kelas Java biasa,
        # method-nya bukan static. Sebelumnya kode ini panggil
        # `NativeBarcodeDetector.hasBarcode(...)` LANGSUNG (tanpa .INSTANCE),
        # beda dari pola yang benar di transport_usb.py/transport_ble.py --
        # itu melempar AttributeError SETIAP panggilan, yang lalu ketelan
        # diam-diam oleh except di bawah, bikin has_barcode() SELALU return
        # False (0 dari 7 halaman terdeteksi, walau ada barcode jelas).
        return bool(NativeBarcodeDetector.INSTANCE.hasBarcode(bytearray(png_bytes)))
    except Exception:
        # Kegagalan native call (mis. bitmap decode gagal) di-treat sebagai
        # "tidak ada barcode" -- TAPI di-print dulu ke log/traceback supaya
        # kegagalan SUNGGUHAN (seperti bug .INSTANCE di atas) tidak lagi
        # tertelan diam-diam tanpa jejak sama sekali.
        traceback.print_exc()
        return False


def barcode_availability_error() -> Optional[str]:
    """Android selalu punya ZXing bundled (pure Java, Gradle dependency) --
    tidak pernah unavailable seperti pyzbar/libzbar di desktop."""
    return None
