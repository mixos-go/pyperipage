"""
peripage_logic.py

SHIM KOMPATIBILITAS -- supaya peripage_gui.py (dan app.py di folder library/)
TIDAK PERLU DIUBAH SAMA SEKALI setelah refactor ini.

Logic asli sudah dipindah ke:
- peripage_protocol.py  -> kalkulasi kertas, smart-crop, urutan byte protokol
- transport_usb.py      -> klaim endpoint USB, kernel detach/reattach

File ini cuma menyatukan keduanya, meniru persis perilaku publik yang dulu
ada di peripage_logic.py versi lama: signature fungsi, nama, dan urutan
eksekusi execute_printing() sama persis, cuma sekarang didelegasikan.
"""
from peripage_protocol import (
    DOTS_PER_MM,
    SUPPORTED_PAPER_WIDTHS_MM,
    DEFAULT_PAPER_WIDTH_MM,
    CONFIG_DIR,
    CONFIG_PATH,
    CALIBRATED_BYTES_PER_ROW,
    get_paper_dimensions,
    load_paper_width_mm,
    save_paper_width_mm,
    smart_crop_and_resize,
    send_print_job,
)
from transport_usb import UsbTransport, TransportError


def force_detach_kernel():
    """Dipertahankan untuk backward-compat -- peripage_gui.py memanggil ini
    langsung di satu tempat (lihat baris ~125, dipakai saat tombol
    'cek koneksi printer' ditekan)."""
    return UsbTransport()._force_detach_kernel()


def execute_printing(pages_to_print, cropped_images_dict, paper_width_mm=DEFAULT_PAPER_WIDTH_MM):
    """Signature & perilaku sama persis seperti execute_printing() versi lama:
    cari printer di USB, klaim endpoint, kirim seluruh halaman, lepas endpoint
    di akhir (baik sukses maupun gagal). Sekarang cuma didelegasikan ke
    UsbTransport + send_print_job()."""
    with UsbTransport() as transport:
        send_print_job(transport, pages_to_print, cropped_images_dict, paper_width_mm)
