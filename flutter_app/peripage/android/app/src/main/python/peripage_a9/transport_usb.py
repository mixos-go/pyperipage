"""
transport_usb.py

Transport USB untuk PeriPage A9 di Android.

GANTI ARSITEKTUR (Juli 2026): sebelumnya pakai `pyusb` (usb.core.find()),
yang TIDAK BISA jalan di Android:
1. pyusb butuh backend `libusb` -- di Android tanpa root umumnya berujung
   `usb.core.NoBackendError: No backend available`.
2. Bahkan kalau ada backend, app Android non-root TIDAK BISA enumerasi
   device USB mentah lewat filesystem seperti Linux/Windows -- akses fisik
   WAJIB lewat `android.hardware.usb.UsbManager` (izin resmi dari user).

Sekarang class ini jadi jembatan TIPIS ke `NativeUsbTransport` (Kotlin),
yang beneran implementasi UsbManager + bulk transfer native. Interface
`.connect()` / `.write(bytes)` / `.close()` SENGAJA dipertahankan identik
supaya `driver.py` dan `protocol.py` TIDAK PERLU diubah sama sekali --
keduanya cuma tahu "transport" yang punya 3 method itu, tidak peduli
implementasi di baliknya pyusb atau Kotlin native.
"""
from com.pyperipage import NativeUsbTransport


class TransportError(Exception):
    """Kegagalan pada layer transport (gagal ditemukan, gagal klaim endpoint, dst)."""
    pass


class UsbTransport:
    VENDOR_ID = 0x09c5
    PRODUCT_ID = 0x0200

    def __init__(self):
        self._native = NativeUsbTransport.INSTANCE

    def connect(self):
        """Cari device USB (prioritas VENDOR_ID/PRODUCT_ID, fallback ke device
        USB manapun yang attached & punya endpoint bulk OUT -- lihat komentar
        `connect()` di NativeUsbTransport.kt untuk detail perilaku universal
        ini), minta izin user lewat dialog sistem Android, lalu klaim endpoint.
        Return `self` supaya bisa dipakai sebagai context manager (`with`)."""
        ok = self._native.connect(self.VENDOR_ID, self.PRODUCT_ID)
        if not ok:
            raise TransportError(
                "Printer USB tidak ditemukan, izin USB ditolak, atau gagal klaim endpoint. "
                "Pastikan printer terhubung lewat kabel USB-OTG dan izin USB di-Allow."
            )
        return self

    def write(self, data: bytes):
        ok = self._native.write(bytearray(data))
        if not ok:
            raise TransportError("Gagal mengirim data ke printer USB (koneksi terputus?).")

    def close(self):
        self._native.close()

    @property
    def is_connected(self) -> bool:
        """Cek status koneksi USB sebenarnya (fix Juli 2026) -- lihat
        komentar serupa di BleTransportSync.is_connected."""
        try:
            return bool(self._native.isConnected())
        except Exception:
            return False

    def __enter__(self):
        return self.connect()

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False
