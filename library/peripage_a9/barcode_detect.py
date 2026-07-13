"""
barcode_detect.py (Desktop implementation -- Windows/Linux/macOS)

Deteksi ada/tidaknya barcode (1D: CODE128/CODE39/EAN, atau 2D: QR/PDF417/
DataMatrix) di sebuah gambar -- dipakai fitur "Auto-deselect halaman tanpa
barcode" di Print Screen, supaya user tidak perlu manual uncheck halaman
non-label (misal halaman ringkasan/invoice) saat print resi pengiriman
massal dari 1 file PDF.

CATATAN ARSITEKTUR PENTING: file ini SENGAJA TIDAK di-sync ke Android
(lihat scripts/sync_peripage_a9.py, EXCLUDE list) -- sama seperti
transport_usb.py/transport_ble.py. Alasannya identik dengan kasus
pymupdf/pyusb/bleak sebelumnya: `pyzbar` butuh library native `libzbar`
(dynamic-loaded lewat ctypes saat runtime) yang TIDAK bisa dipasang di
Android lewat Chaquopy. Implementasi Android ada di file terpisah dengan
nama & signature fungsi SAMA PERSIS (`has_barcode`), tapi di baliknya
delegasi ke ZXing (Java, pure JVM, native Android) lewat
NativeBarcodeDetector.kt -- pola yang sama dengan transport USB/BLE.
"""
from typing import Optional
from PIL import Image

try:
    from pyzbar.pyzbar import decode as _zbar_decode
    _PYZBAR_AVAILABLE = True
    _PYZBAR_IMPORT_ERROR = None
except (ImportError, OSError) as e:
    # OSError muncul kalau libzbar.so/dylib tidak ketemu di sistem (bukan
    # cuma package Python pyzbar-nya yang belum ke-install) -- ini beda
    # penyebab, makanya keduanya ditangkap terpisah dari ImportError biasa.
    _PYZBAR_AVAILABLE = False
    _PYZBAR_IMPORT_ERROR = str(e)


def has_barcode(pil_image: Image.Image) -> bool:
    """
    True kalau gambar mengandung minimal 1 barcode/QR code yang terdeteksi
    (format apa pun yang didukung zbar: CODE128, CODE39, EAN13, QR, PDF417,
    dll -- mencakup hampir semua format yang dipakai label pengiriman
    Shopee/TikTok/JNE/SPX/dll).

    Raises:
        RuntimeError: kalau pyzbar/libzbar tidak tersedia di sistem ini.
    """
    if not _PYZBAR_AVAILABLE:
        raise RuntimeError(
            f"pyzbar/libzbar tidak tersedia di sistem ini ({_PYZBAR_IMPORT_ERROR}). "
            "Linux: sudo apt install libzbar0. macOS: brew install zbar. "
            "Windows: seharusnya sudah bundled di wheel pyzbar -- coba "
            "'pip install --force-reinstall pyzbar'."
        )
    try:
        results = _zbar_decode(pil_image.convert("RGB"))
        return len(results) > 0
    except Exception:
        # Kegagalan decode (gambar korup, dll) di-treat sebagai "tidak ada
        # barcode" -- bukan error fatal, biar proses batch tetap lanjut ke
        # halaman lain daripada gagal total.
        return False


def barcode_availability_error() -> Optional[str]:
    """None kalau pyzbar siap dipakai, atau pesan error kalau tidak --
    dipakai server.py buat kasih tahu user dengan jelas kalau fitur ini
    tidak bisa dipakai di sistem mereka (mis. libzbar belum terinstall)."""
    if _PYZBAR_AVAILABLE:
        return None
    return f"pyzbar/libzbar tidak tersedia: {_PYZBAR_IMPORT_ERROR}"
