"""
peripage_a9/driver.py

API PUBLIK class PeriPageA9USB TIDAK BERUBAH dari versi lama -- signature
method, nilai balik, dan label log ([LIBRARY], [LIBRARY ERROR], dst) sama
persis. Yang berubah cuma internalnya: byte protokol & transport USB sekarang
didelegasikan ke peripage_protocol.py / transport_usb.py yang SAMA dipakai
oleh aplikasi GUI di root project -- supaya kedua produk (package pip ini dan
app GUI) tidak lagi punya dua salinan logic protokol yang bisa diam-diam beda.
"""
import traceback

from . import protocol
from .transport_usb import UsbTransport


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

    def smart_crop_and_resize(self, pil_img):
        """
        Algoritma Sinkronisasi Cetak & Preview:
        Memotong ruang kosong 4-arah, mengunci lebar konten murni halaman
        pada lebar kertas fisik aktif (self.paper_width_mm), dan menyerahkannya
        ke fungsi cetak.
        """
        return protocol.smart_crop_and_resize(pil_img, self.paper_width_mm, error_tag="LIBRARY")

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

    def print_pages(self, pages_to_print, cropped_images_dict):
        """Mengirim data biner sesuai lebar kertas fisik aktif (self.paper_width_mm)"""
        if self._transport is None:
            raise Exception("Printer belum terhubung. Panggil fungsi .connect() terlebih dahulu.")

        try:
            protocol.send_print_job(
                self._transport, pages_to_print, cropped_images_dict, self.paper_width_mm,
                progress_tag="LIBRARY", done_tag="LIBRARY",
            )
            print("[LIBRARY] Seluruh dokumen sukses dibakar ke kertas thermal!")
        except Exception as e:
            print("\n[LIBRARY ERROR] Kegagalan transmisi data USB:")
            traceback.print_exc()
            raise e
        finally:
            # SISTEM AUTO-RESET PORT UNTUK MENCEGAH MACET / RESOURCE BUSY
            self._transport.close()
