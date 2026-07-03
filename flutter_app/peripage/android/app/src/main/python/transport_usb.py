"""
transport_usb.py

Transport USB raw untuk PeriPage A9. Ini pindahan 1:1 dari force_detach_kernel()
dan bagian USB-specific di execute_printing() versi lama (peripage_logic.py) --
klaim interface, cari endpoint bulk OUT, kernel driver detach/reattach.

Tidak ada perubahan pada logic detach kernel atau cara klaim endpoint. Yang
berubah cuma dikemas jadi class dengan interface `.connect()` / `.write()` /
`.close()` yang seragam dengan transport_bluetooth.py (nanti), supaya
peripage_protocol.send_print_job() bisa dipakai lewat transport manapun.
"""
import time
import usb.core
import usb.util


class TransportError(Exception):
    """Kegagalan pada layer transport (gagal ditemukan, gagal klaim endpoint, dst)."""
    pass


class UsbTransport:
    VENDOR_ID = 0x09c5
    PRODUCT_ID = 0x0200

    def __init__(self):
        self.dev = None
        self.ep_out = None

    def _force_detach_kernel(self):
        dev = usb.core.find(idVendor=self.VENDOR_ID, idProduct=self.PRODUCT_ID)
        if dev is not None:
            try:
                if dev.is_kernel_driver_active(0):
                    dev.detach_kernel_driver(0)
                    print("[TRANSPORT-USB] Driver kernel usblp berhasil dilepas.")
                    time.sleep(0.3)
            except Exception:
                pass
        return dev

    def connect(self):
        """Cari device di bus USB, lepas kunci kernel usblp, klaim endpoint OUT.
        Return `self` supaya bisa dipakai sebagai context manager (`with`)."""
        self.dev = self._force_detach_kernel()
        if self.dev is None:
            raise TransportError("Printer tidak ditemukan secara fisik di port USB.")

        self.dev.set_configuration()
        cfg = self.dev.get_active_configuration()
        intf = cfg[(0, 0)]

        self.ep_out = usb.util.find_descriptor(
            intf,
            custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_OUT
        )

        if self.ep_out is None:
            raise TransportError("Gagal memetakan pipa data (Endpoint OUT) USB Printer.")

        return self

    def write(self, data: bytes):
        self.ep_out.write(data)

    def close(self):
        try:
            usb.util.release_interface(self.dev, 0)
            self.dev.attach_kernel_driver(0)
            print("[TRANSPORT-USB] Resource port USB berhasil dilepas secara aman.")
        except Exception:
            pass

    def __enter__(self):
        return self.connect()

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False
