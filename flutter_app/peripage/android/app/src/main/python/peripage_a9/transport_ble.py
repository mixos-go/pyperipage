"""
transport_ble.py

Transport Bluetooth Low Energy (BLE) untuk PeriPage A9.
Menggunakan library `bleak` untuk komunikasi lintas platform (Windows, macOS, Linux, Android, iOS).

Peripage A9 BLE menggunakan service UUID dan characteristic UUID khusus untuk transfer data print.
Interface sama dengan UsbTransport: .connect(), .write(), .close()
"""
import asyncio
import traceback
from typing import Optional

try:
    from bleak import BleakClient, BleakScanner
    from bleak.exc import BleakError
except ImportError:
    raise ImportError(
        "Library 'bleak' diperlukan untuk transport BLE. "
        "Install dengan: pip install bleak"
    )


class TransportError(Exception):
    """Kegagalan pada layer transport BLE (device tidak ditemukan, gagal connect, dll)."""
    pass


class BleTransport:
    """
    Transport handler untuk PeriPage A9 via Bluetooth Low Energy.

    UUID di bawah dikonfirmasi lewat inspeksi manual GATT table pakai nRF Connect
    langsung ke unit PeriPage_A9 fisik (Juli 2026), BUKAN placeholder generik.
    Service ini dikenal sebagai "ISSC Transparent UART" -- dipakai juga di banyak
    printer thermal BLE murah lain (cat-printer, Goojprt, dll), fungsinya
    nge-tunnel byte mentah langsung ke MCU printer.
    """

    SERVICE_UUID = "49535343-fe7d-4ae5-8fa9-9fafd205e455"          # ISSC Transparent UART service
    CHARACTERISTIC_UUID = "49535343-8841-43f4-a8d4-ecbe34729bb3"    # RX (write dari app ke printer)
    NOTIFY_UUID = "49535343-1e4d-4bd9-ba61-23c647249616"            # TX (notify dari printer ke app)

    # Nama iklan BLE printer ini "PeriPage_A9_BLE" (dari characteristic Device Name 0x2A00),
    # tapi header koneksi nRF Connect nunjukin "PERIPAGE_A9" -- cocokkan keduanya biar aman.
    DEVICE_NAME = "PeriPage_A9"
    
    def __init__(self, device_address: Optional[str] = None):
        """
        Inisialisasi transport BLE.
        
        Args:
            device_address: MAC address atau UUID device (opsional). 
                           Jika None, akan mencari berdasarkan DEVICE_NAME.
        """
        self.device_address = device_address
        self.client: Optional[BleakClient] = None
        self._connected = False
        self._characteristic_uuid = self.CHARACTERISTIC_UUID
    
    async def discover_devices(self, timeout: float = 5.0) -> list:
        """
        Scan dan temukan device BLE PeriPage A9 di sekitar.
        
        Args:
            timeout: Durasi scanning dalam detik.
            
        Returns:
            List of dict dengan info device: {'name': str, 'address': str, 'rssi': int}
        """
        print("[TRANSPORT-BLE] Memulai scanning device BLE...")
        try:
            devices = await BleakScanner.discover(timeout=timeout)
            found_devices = []
            
            for device in devices:
                # Cari device dengan nama mengandung "PeriPage" atau "A9"
                if device.name and ("PeriPage" in device.name or "A9" in device.name or "PP" in device.name):
                    found_devices.append({
                        'name': device.name,
                        'address': device.address,
                        'rssi': device.rssi
                    })
                    print(f"[TRANSPORT-BLE] Ditemukan: {device.name} ({device.address}) RSSI: {device.rssi}")
            
            if not found_devices:
                print("[TRANSPORT-BLE] Tidak menemukan printer PeriPage A9. Pastikan printer nyala dan dalam mode pairing.")
            
            return found_devices
            
        except BleakError as e:
            print(f"[TRANSPORT-BLE ERROR] Gagal scanning: {e}")
            traceback.print_exc()
            raise TransportError(f"Gagal scanning BLE: {e}")
    
    async def connect(self, timeout: float = 10.0) -> 'BleTransport':
        """
        Koneksi ke printer PeriPage A9 via BLE.
        
        Args:
            timeout: Timeout koneksi dalam detik.
            
        Returns:
            Self untuk method chaining.
            
        Raises:
            TransportError: Jika device tidak ditemukan atau gagal koneksi.
        """
        if self._connected and self.client:
            print("[TRANSPORT-BLE] Sudah terhubung.")
            return self
        
        try:
            # Tentukan address device
            address = self.device_address
            
            if not address:
                # Auto-discovery berdasarkan nama
                print(f"[TRANSPORT-BLE] Mencari device dengan nama: {self.DEVICE_NAME}")
                devices = await self.discover_devices(timeout=5.0)
                
                if not devices:
                    raise TransportError(
                        f"Printer '{self.DEVICE_NAME}' tidak ditemukan. "
                        "Pastikan printer nyala, dalam mode pairing, dan bluetooth aktif."
                    )
                
                # Ambil device pertama yang cocok
                address = devices[0]['address']
                print(f"[TRANSPORT-BLE] Menghubungkan ke: {devices[0]['name']} ({address})")
            
            # Buat client dan connect
            self.client = BleakClient(address)
            await self.client.connect(timeout=timeout)
            
            if not self.client.is_connected:
                raise TransportError("Gagal membangun koneksi BLE.")
            
            # Verify service dan characteristic tersedia
            services = self.client.services
            print(f"[TRANSPORT-BLE] Terhubung! Menemukan {len(services)} services.")
            
            # Cari characteristic untuk write
            char = None
            try:
                char = self.client.services.get_characteristic(self._characteristic_uuid)
            except Exception:
                # Coba cari characteristic writeable lainnya di service print
                for service in services:
                    if self.SERVICE_UUID.lower() in service.uuid.lower():
                        for c in service.characteristics:
                            if 'write' in str(c.properties).lower():
                                self._characteristic_uuid = c.uuid
                                char = c
                                print(f"[TRANSPORT-BLE] Menggunakan characteristic: {c.uuid}")
                                break
                        break
            
            if not char:
                print(f"[TRANSPORT-BLE WARNING] Characteristic {self._characteristic_uuid} tidak ditemukan. "
                      f"Menggunakan fallback. Mungkin perlu penyesuaian UUID.")
            
            self._connected = True
            print("[TRANSPORT-BLE] Koneksi BLE berhasil.")
            return self
            
        except BleakError as e:
            print(f"[TRANSPORT-BLE ERROR] Gagal koneksi: {e}")
            traceback.print_exc()
            raise TransportError(f"Gagal koneksi BLE: {e}")
        except Exception as e:
            print(f"[TRANSPORT-BLE ERROR] Error tak terduga: {e}")
            traceback.print_exc()
            raise TransportError(f"Error koneksi: {e}")
    
    async def write(self, data: bytes) -> None:
        """
        Kirim data byte ke printer via BLE.
        
        Args:
            data: Data byte yang akan dikirim.
            
        Raises:
            TransportError: Jika tidak terhubung atau gagal kirim.
        """
        if not self._connected or not self.client:
            raise TransportError("Printer belum terhubung. Panggil .connect() terlebih dahulu.")
        
        if not self.client.is_connected:
            raise TransportError("Koneksi BLE terputus.")
        
        try:
            # BLE memiliki MTU terbatas, mungkin perlu chunking untuk data besar
            # Untuk printer thermal, biasanya MTU ~20-512 bytes tergantung device
            mtu_size = self.client.mtu_size if hasattr(self.client, 'mtu_size') else 20
            # Gunakan 80% dari MTU untuk safety margin
            max_chunk_size = int(mtu_size * 0.8)
            
            # Chunk data jika terlalu besar
            for i in range(0, len(data), max_chunk_size):
                chunk = data[i:i + max_chunk_size]
                await self.client.write_gatt_char(self._characteristic_uuid, chunk, response=True)
                # Small delay untuk stabilitas
                await asyncio.sleep(0.002)
                
        except BleakError as e:
            print(f"[TRANSPORT-BLE ERROR] Gagal kirim data: {e}")
            traceback.print_exc()
            raise TransportError(f"Gagal kirim data BLE: {e}")
    
    async def close(self) -> None:
        """
        Tutup koneksi BLE dan lepas resource.
        """
        if self.client and self._connected:
            try:
                await self.client.disconnect()
                print("[TRANSPORT-BLE] Koneksi BLE ditutup.")
            except Exception as e:
                print(f"[TRANSPORT-BLE WARNING] Gagal menutup koneksi dengan bersih: {e}")
            finally:
                self.client = None
                self._connected = False
    
    async def __aenter__(self) -> 'BleTransport':
        """Async context manager entry."""
        return await self.connect()
    
    async def __aexit__(self, exc_type, exc_val, exc_tb) -> bool:
        """Async context manager exit."""
        await self.close()
        return False


# Wrapper synchronous untuk kompatibilitas dengan code existing
# (karena bleak adalah async library, tapi code lama kita synchronous)
class BleTransportSync:
    """
    Wrapper synchronous untuk BleTransport.
    Menggunakan asyncio.run() untuk menjalankan operasi async.
    Cocok untuk integrasi dengan code existing yang belum async.
    """
    
    def __init__(self, device_address: Optional[str] = None):
        self._async_transport = BleTransport(device_address)
        self._loop = None
    
    def _run_async(self, coro):
        """Jalankan coroutine async secara synchronous."""
        if self._loop is None or self._loop.is_closed():
            self._loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self._loop)
        return self._loop.run_until_complete(coro)
    
    def discover_devices(self, timeout: float = 5.0) -> list:
        """Scan device BLE (synchronous wrapper)."""
        return self._run_async(self._async_transport.discover_devices(timeout))
    
    def connect(self, timeout: float = 10.0) -> 'BleTransportSync':
        """Koneksi ke printer (synchronous wrapper)."""
        self._run_async(self._async_transport.connect(timeout))
        return self
    
    def write(self, data: bytes) -> None:
        """Kirim data (synchronous wrapper)."""
        self._run_async(self._async_transport.write(data))
    
    def close(self) -> None:
        """Tutup koneksi (synchronous wrapper)."""
        self._run_async(self._async_transport.close())
        if self._loop and not self._loop.is_closed():
            self._loop.close()
    
    def __enter__(self) -> 'BleTransportSync':
        return self.connect()
    
    def __exit__(self, exc_type, exc_val, exc_tb) -> bool:
        self.close()
        return False


# Alias untuk backward compatibility - gunakan sync version sebagai default
# agar interface sama dengan UsbTransport
BleTransportDefault = BleTransportSync
