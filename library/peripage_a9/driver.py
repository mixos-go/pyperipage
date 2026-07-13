"""
peripage_a9/driver.py

API PUBLIK class PeriPageA9USB dan PeriPageA9BLE.
Logic protokol dan transport dipisah ke modul terpisah.
Support USB (desktop) dan BLE (mobile) dengan interface yang sama.
"""
import traceback

from . import protocol
from .transport_usb import UsbTransport
from .transport_ble import BleTransportDefault as BleTransport


class PeriPageA9USB:
    """
    Library Driver Native USB Profesional untuk Printer Thermal PeriPage A9.
    Mendukung Full 4-Way Smart Crop adaptif, mengunci lebar cetak persis
    sesuai lebar kertas fisik yang dipilih lewat set_paper_width().
    """

    def __init__(self, vid=0x09c5, pid=0x0200, paper_width_mm=None):
        self.vid = vid
        self.pid = pid
        self.dev = None
        self.ep_out = None
        self._transport = None
        # Kalau tidak diisi eksplisit, otomatis pakai setting tersimpan terakhir
        self.paper_width_mm = paper_width_mm if paper_width_mm else protocol.load_paper_width_mm()

    def set_paper_width(self, paper_width_mm, persist=True):
        """Ganti lebar kertas aktif (58 atau 77mm). Kalau persist=True, otomatis
        disimpan supaya jadi default di sesi berikutnya juga."""
        if paper_width_mm not in protocol.SUPPORTED_PAPER_WIDTHS_MM:
            raise ValueError(
                f"Lebar kertas {paper_width_mm}mm tidak didukung. "
                f"Pilihan: {protocol.SUPPORTED_PAPER_WIDTHS_MM}"
            )
        self.paper_width_mm = paper_width_mm
        if persist:
            protocol.save_paper_width_mm(paper_width_mm, warning_tag="LIBRARY")

    def smart_crop_and_resize(self, pil_img, use_smart_crop: bool = True):
        """
        Algoritma Sinkronisasi Cetak & Preview:
        Memotong ruang kosong 4-arah, mengunci lebar konten murni halaman
        pada lebar kertas fisik aktif (self.paper_width_mm), dan menyerahkannya
        ke fungsi cetak.

        use_smart_crop=False (mode "Manual Crop" di UI): skip auto-trim
        whitespace, cuma resize gambar asli ke lebar kertas.
        """
        if use_smart_crop:
            return protocol.smart_crop_and_resize(pil_img, self.paper_width_mm, error_tag="LIBRARY")
        return protocol.resize_to_paper_width(pil_img, self.paper_width_mm, error_tag="LIBRARY")

    def connect(self):
        """Mencari fisik hardware, melepas driver kernel, dan mengklaim interface USB.
        Return True/False (tidak raise) -- sama seperti perilaku versi lama."""
        self._transport = UsbTransport()
        self._transport.VENDOR_ID = self.vid
        self._transport.PRODUCT_ID = self.pid
        try:
            self._transport.connect()
            self.dev = self._transport.dev
            self.ep_out = self._transport.ep_out
            return True
        except Exception as e:
            print(f"\n[LIBRARY ERROR] Gagal menginisialisasi port USB: {e}")
            traceback.print_exc()
            self._transport = None
            return False

    def print_pages(self, pages_to_print, cropped_images_dict, force_protocol=None):
        """Mengirim data biner sesuai lebar kertas fisik aktif (self.paper_width_mm).
        force_protocol: override manual "raw"/"compressed"/None=auto -- lihat
        protocol.send_print_job() untuk detail. USB tidak punya device_name
        (bukan BLE advertised name), jadi auto-detect selalu fallback RAW
        kecuali di-force manual."""
        if self._transport is None:
            raise Exception("Printer belum terhubung. Panggil fungsi .connect() terlebih dahulu.")

        try:
            protocol.send_print_job(
                self._transport, pages_to_print, cropped_images_dict, self.paper_width_mm,
                progress_tag="LIBRARY", done_tag="LIBRARY", force_protocol=force_protocol,
            )
            print("[LIBRARY] Seluruh dokumen sukses dibakar ke kertas thermal!")
        except Exception as e:
            print("\n[LIBRARY ERROR] Kegagalan transmisi data USB:")
            traceback.print_exc()
            raise e
        # PENTING (fix Juli 2026): TIDAK auto-close transport di sini lagi.
        # Sebelumnya ada `finally: self._transport.close()` yang menutup
        # koneksi setiap SELESAI 1 print job apa pun hasilnya -- niatnya
        # "cegah resource busy", tapi efeknya app harus reconnect ulang
        # setiap mau print lagi walau user sudah connect di Settings dan
        # printer masih fisik menyala & dalam jangkauan. Sekarang koneksi
        # tetap terbuka sampai user eksplisit pilih "Putuskan" di Settings
        # (lihat disconnect_printer() di python_service.py / server.py).


class PeriPageA9BLE:
    """
    Library Driver BLE (Bluetooth Low Energy) untuk Printer Thermal PeriPage A9.
    Interface sama dengan PeriPageA9USB untuk kemudahan penggunaan.
    Cocok untuk mobile (Android/iOS) dan desktop dengan Bluetooth.
    """

    def __init__(self, device_address=None, device_name=None, paper_width_mm=None):
        """
        Args:
            device_address: MAC address atau UUID device BLE (opsional).
                           Jika None, akan auto-discovery berdasarkan nama.
            device_name: nama BLE device (dari hasil scan) -- dipakai buat
                         auto-deteksi protokol RAW vs COMPRESSED (lihat
                         protocol.uses_compressed_protocol()). Opsional,
                         None = selalu fallback RAW kecuali di-force manual.
            paper_width_mm: Lebar kertas (58 atau 77mm). Default dari setting tersimpan.
        """
        self.device_address = device_address
        self.device_name = device_name
        self._transport = None
        self.paper_width_mm = paper_width_mm if paper_width_mm else protocol.load_paper_width_mm()

    def set_paper_width(self, paper_width_mm, persist=True):
        """Ganti lebar kertas aktif (58 atau 77mm)."""
        if paper_width_mm not in protocol.SUPPORTED_PAPER_WIDTHS_MM:
            raise ValueError(
                f"Lebar kertas {paper_width_mm}mm tidak didukung. "
                f"Pilihan: {protocol.SUPPORTED_PAPER_WIDTHS_MM}"
            )
        self.paper_width_mm = paper_width_mm
        if persist:
            protocol.save_paper_width_mm(paper_width_mm, warning_tag="LIBRARY-BLE")

    def smart_crop_and_resize(self, pil_img, use_smart_crop: bool = True):
        """Smart/manual crop dan resize gambar sesuai lebar kertas aktif."""
        if use_smart_crop:
            return protocol.smart_crop_and_resize(pil_img, self.paper_width_mm, error_tag="LIBRARY-BLE")
        return protocol.resize_to_paper_width(pil_img, self.paper_width_mm, error_tag="LIBRARY-BLE")

    def connect(self):
        """Koneksi ke printer via BLE. Return True/False."""
        self._transport = BleTransport(self.device_address)
        try:
            self._transport.connect()
            print("[LIBRARY-BLE] Koneksi BLE berhasil.")
            return True
        except Exception as e:
            print(f"\n[LIBRARY-BLE ERROR] Gagal koneksi BLE: {e}")
            traceback.print_exc()
            self._transport = None
            return False

    def print_pages(self, pages_to_print, cropped_images_dict, force_protocol=None):
        """Kirim data print ke printer via BLE. force_protocol: override
        manual "raw"/"compressed"/None=auto-detect dari self.device_name --
        lihat protocol.send_print_job() untuk detail."""
        if self._transport is None:
            raise Exception("Printer belum terhubung. Panggil fungsi .connect() terlebih dahulu.")

        try:
            protocol.send_print_job(
                self._transport, pages_to_print, cropped_images_dict, self.paper_width_mm,
                progress_tag="LIBRARY-BLE", done_tag="LIBRARY-BLE",
                device_name=self.device_name, force_protocol=force_protocol,
            )
            print("[LIBRARY-BLE] Dokumen sukses dicetak via BLE!")
        except Exception as e:
            print("\n[LIBRARY-BLE ERROR] Kegagalan transmisi data BLE:")
            traceback.print_exc()
            raise e
        # PENTING (fix Juli 2026): TIDAK auto-close transport lagi -- lihat
        # komentar panjang di PeriPageA9USB.print_pages() di atas, alasannya
        # sama persis. Auto-close di sini yang bikin BLE "koneksi terputus"
        # tiap mau print job ke-2 dst walau device masih fisik terhubung.
