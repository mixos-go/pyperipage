"""
transport_ble.py

Transport Bluetooth Low Energy (BLE) untuk PeriPage A9 di Android.

GANTI ARSITEKTUR (Juli 2026): sebelumnya pakai `bleak`, yang TIDAK BISA jalan
di Android lewat Chaquopy. Backend Android bleak (`bleak.backends.p4android`)
hardcoded butuh `python-for-android` -- dia `import jnius`,
`from android.broadcast import BroadcastReceiver`,
`from android.permissions import ...`, yang SEMUANYA cuma ada di ekosistem
python-for-android (Kivy/Buildozer), sama sekali tidak ada di Chaquopy. Tim
BeeWare mengalami masalah persis sama saat mereka juga pakai Chaquopy
(lihat github.com/beeware/beeware/issues/181) -- ini bukan salah konfigurasi,
memang bleak tidak kompatibel dengan Chaquopy.

Sekarang class di file ini jadi jembatan TIPIS ke `NativeBleTransport`
(Kotlin), yang beneran implementasi `BluetoothLeScanner`/`BluetoothGatt`
native Android. Interface `.discover_devices()` / `.connect()` /
`.write(bytes)` / `.close()` SENGAJA dipertahankan identik supaya
`driver.py` TIDAK PERLU diubah sama sekali.

UNIVERSAL DEVICE SUPPORT: tidak lagi hardcode ke 1 service/characteristic
UUID PeriPage. NativeBleTransport men-scan SEMUA characteristic writable di
device manapun yang connect (prioritas ke UUID printer BLE yang umum lintas
merk, fallback ke characteristic writable apa pun) -- jadi printer BLE merk
lain (bukan cuma PeriPage) juga bisa dipakai selama protokol datanya
kompatibel (raw byte tunnel), tanpa perlu tahu UUID persisnya di awal.

Karena NativeBleTransport Kotlin sudah sepenuhnya synchronous/blocking
(pakai CountDownLatch internal buat nunggu callback BLE), wrapper asyncio
yang dulu dipakai buat `bleak` (yang async) SUDAH TIDAK DIPERLUKAN LAGI --
class di sini langsung synchronous dari awal, jadi lebih simpel.
"""
from typing import Optional
import json

from com.pyperipage import NativeBleTransport


class TransportError(Exception):
    """Kegagalan pada layer transport BLE (device tidak ditemukan, gagal connect, dll)."""
    pass


class BleTransportSync:
    """
    Transport handler synchronous untuk printer BLE (PeriPage A9 maupun merk
    lain yang kompatibel). Nama class dipertahankan `BleTransportSync` (bukan
    `BleTransport`) untuk kompatibilitas mundur dengan python_service.py yang
    sudah memanggil `from peripage_a9.transport_ble import BleTransportSync`.
    """

    def __init__(self, device_address: Optional[str] = None):
        """
        Args:
            device_address: MAC address device BLE (opsional). Kalau None,
                           connect() akan gagal -- caller (driver.py /
                           python_service.py) diharapkan sudah memanggil
                           discover_devices() dulu buat dapetin address-nya,
                           lalu user pilih salah satu lewat UI (lihat
                           BLE device picker di home_screen.dart).
        """
        self.device_address = device_address
        self._native = NativeBleTransport.INSTANCE
        self._connected = False

    def discover_devices(self, timeout: float = 5.0) -> list:
        """
        Scan device BLE di sekitar. UNIVERSAL: mengembalikan SEMUA device BLE
        bernama yang ditemukan (tidak difilter cuma nama "PeriPage"/"A9"),
        supaya printer BLE merk lain juga muncul & bisa dipilih user.

        Returns:
            List of dict: {'name': str, 'address': str, 'rssi': int}
        """
        timeout_ms = int(timeout * 1000)
        try:
            # NativeBleTransport.discoverDevices() sekarang return STRING JSON
            # (bukan List<Map> Kotlin mentah) -- fix Juli 2026, lihat komentar
            # panjang di NativeBleTransport.kt. Iterasi objek Java/Kotlin lewat
            # Chaquopy reflection rawan rusak kalau R8 me-rename class internal
            # (muncul sebagai "'l' object is not iterable" -- 'l' itu literally
            # nama class hasil obfuscation). json.loads() di sini SAMA SEKALI
            # tidak menyentuh objek Java apa pun, jadi kebal dari masalah itu.
            json_str = self._native.discoverDevices(timeout_ms)
            devices = json.loads(str(json_str))
        except Exception as e:
            raise TransportError(f"Gagal scanning BLE: {e}")

        # json.loads() sudah menghasilkan list of dict Python murni --
        # tidak perlu konversi tambahan (beda dari versi lama yang masih
        # perlu dict(d) buat objek Kotlin Map mentah).
        return devices

    def connect(self, timeout: float = 10.0) -> 'BleTransportSync':
        """
        Koneksi ke device BLE. Kalau `device_address` tidak diisi saat init,
        auto-discovery lewat nama TIDAK dilakukan di sini lagi (beda dari
        versi bleak lama) -- device_address WAJIB sudah diketahui sebelum
        connect() dipanggil, karena scanning untuk cari-by-name di Android
        butuh permission runtime yang sebaiknya sudah selesai di tahap
        discover_devices() (lihat BLE device picker di UI).

        Returns:
            Self untuk method chaining / context manager.

        Raises:
            TransportError: Jika device_address kosong atau gagal connect.
        """
        if self._connected:
            return self

        if not self.device_address:
            raise TransportError(
                "Address device BLE belum diketahui. Panggil discover_devices() "
                "dulu untuk memilih printer, baru connect() dengan address-nya."
            )

        timeout_ms = int(timeout * 1000)
        try:
            ok = self._native.connect(self.device_address, timeout_ms)
        except Exception as e:
            raise TransportError(f"Gagal koneksi BLE: {e}")

        if not ok:
            raise TransportError(
                f"Gagal terhubung ke device BLE {self.device_address}. "
                "Pastikan printer masih menyala & dalam jangkauan."
            )

        self._connected = True
        return self

    def write(self, data: bytes) -> None:
        """Kirim data byte ke printer via BLE, otomatis di-chunk sesuai MTU
        (lihat NativeBleTransport.write())."""
        if not self._connected:
            raise TransportError("Printer belum terhubung. Panggil .connect() terlebih dahulu.")

        ok = self._native.write(bytearray(data))
        if not ok:
            raise TransportError("Gagal kirim data BLE (koneksi terputus?).")

    def close(self) -> None:
        """Tutup koneksi BLE dan lepas resource."""
        try:
            self._native.close()
        finally:
            self._connected = False

    def __enter__(self) -> 'BleTransportSync':
        return self.connect()

    def __exit__(self, exc_type, exc_val, exc_tb) -> bool:
        self.close()
        return False


# Alias untuk backward compatibility -- driver.py mengimpor nama ini.
BleTransportDefault = BleTransportSync

# WAJIB ADA (fix Juli 2026): __init__.py (file yang SAMA/di-sync dari
# library/peripage_a9/__init__.py di ketiga platform) melakukan:
#   from .transport_ble import BleTransport, TransportError as BleTransportError
# Nama `BleTransport` ini HARUS ada persis di sini walau implementasi
# Android cuma punya `BleTransportSync` -- kalau tidak, import __init__.py
# gagal total dengan "ImportError: cannot import name 'BleTransport'",
# yang berarti SELURUH package peripage_a9 gagal dimuat (bukan cuma BLE).
BleTransport = BleTransportSync
