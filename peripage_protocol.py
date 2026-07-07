"""
peripage_protocol.py

Logic MURNI protokol printer PeriPage A9: kalkulasi dimensi kertas, algoritma
smart-crop, dan urutan byte yang dikirim ke printer.

File ini SENGAJA tidak tahu apakah datanya nanti dikirim lewat USB atau
Bluetooth -- itu tanggung jawab modul transport_usb.py / transport_bluetooth.py.
Prinsipnya: satu sumber kebenaran untuk "apa yang dikirim", banyak transport
untuk "lewat mana dikirim".

CATATAN MIGRASI: seluruh isi fungsi di file ini adalah pindahan 1:1 dari
peripage_logic.py versi lama (sebelum dipisah dari transport USB). Tidak ada
nilai byte, urutan command, atau timing (time.sleep) yang diubah. Yang berubah
HANYA cara pengiriman byte-nya: dari `ep_out.write(...)` langsung jadi
`transport.write(...)` yang bisa diisi USB maupun Bluetooth.
"""
import os
import json
import time
import traceback
from PIL import Image, ImageChops

# =====================================================================
# KONFIGURASI LEBAR KERTAS FISIK
# PeriPage A9 mendukung 2 lebar roll kertas resmi: 58mm dan 77mm.
# Resolusi 203dpi ~ 8 dot/mm, jadi lebar piksel = lebar_mm * 8.
# Nilai default kalau belum ada setting tersimpan sama sekali.
DOTS_PER_MM = 8
SUPPORTED_PAPER_WIDTHS_MM = [58, 77]
DEFAULT_PAPER_WIDTH_MM = 77

CONFIG_DIR = os.path.expanduser("~/.pyperipage")
CONFIG_PATH = os.path.join(CONFIG_DIR, "settings.json")
# =====================================================================


# =====================================================================
# KONFIGURASI CROP MANUAL
# DPI ini dipakai HANYA untuk konversi mm<->px pada fitur crop manual
# (garis offset atas/bawah di crop editor), SAMA DENGAN dpi render PDF
# di peripage_gui.py (convert_from_path(..., dpi=300)). Kalau nanti dpi
# render PDF diubah, nilai ini WAJIB ikut diubah supaya mistar mm di
# crop editor tetap akurat. Untuk gambar hasil impor langsung (JPG/PNG)
# yang tidak selalu 300dpi, ini dipakai sebagai asumsi pendekatan.
CROP_REFERENCE_DPI = 300
# =====================================================================


# =====================================================================
# OVERRIDE KALIBRASI MANUAL
# Kalau hasil tes tools/calibrate_paper_width.py menunjukkan lebar cetak
# asli unit kamu BEDA dari asumsi 8 dot/mm, isi di sini nilai byte yang
# terbukti aman dari kalibrasi (mengalahkan hitungan mm otomatis).
# Format: {lebar_mm_yang_dipilih_di_GUI: lebar_byte_hasil_kalibrasi}
# Hasil kalibrasi fisik (03 Jul 2026): pola ruler terpotong antara byte
# 70-75 pada mode kertas 77mm -> dipakai 70 byte (560px) sebagai batas aman.
CALIBRATED_BYTES_PER_ROW = {77: 70}
# =====================================================================


def get_paper_dimensions(paper_width_mm):
    """Konversi lebar kertas (mm) -> (lebar_piksel, lebar_byte). Kalau ada
    hasil kalibrasi manual untuk lebar ini di CALIBRATED_BYTES_PER_ROW,
    itu yang dipakai (lebih akurat daripada asumsi generik 8 dot/mm).
    Kalau belum, dibulatkan ke kelipatan 8 dari asumsi 8 dot/mm."""
    if paper_width_mm in CALIBRATED_BYTES_PER_ROW:
        bytes_per_row = CALIBRATED_BYTES_PER_ROW[paper_width_mm]
        return bytes_per_row * 8, bytes_per_row
    px = int(round(paper_width_mm * DOTS_PER_MM / 8.0)) * 8
    return px, px // 8


def load_paper_width_mm():
    """Baca setting lebar kertas terakhir yang disimpan pengguna. Kalau belum
    pernah diset, kembalikan default."""
    try:
        with open(CONFIG_PATH, "r") as f:
            data = json.load(f)
        width = int(data.get("paper_width_mm", DEFAULT_PAPER_WIDTH_MM))
        if width in SUPPORTED_PAPER_WIDTHS_MM:
            return width
    except Exception:
        pass
    return DEFAULT_PAPER_WIDTH_MM


def save_paper_width_mm(paper_width_mm, warning_tag="LOGIC"):
    """Simpan pilihan lebar kertas pengguna supaya otomatis dipakai lagi di sesi berikutnya."""
    try:
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(CONFIG_PATH, "w") as f:
            json.dump({"paper_width_mm": paper_width_mm}, f)
    except Exception:
        print(f"\n[{warning_tag} WARNING] Gagal menyimpan setting lebar kertas ke disk:")
        traceback.print_exc()


def smart_crop_and_resize(pil_img, paper_width_mm=DEFAULT_PAPER_WIDTH_MM, error_tag="LOGIC"):
    """
    Algoritma Sinkronisasi Cetak (What You See Is What You Print):
    Memotong ruang kosong 4-arah, mengunci lebar konten murni halaman pada
    lebar kertas fisik yang sedang dipakai (paper_width_mm), dan menyerahkannya
    ke fungsi cetak.

    `error_tag` cuma memengaruhi label log kalau terjadi error (mis. "LOGIC"
    dipakai peripage_logic.py, "LIBRARY" dipakai package peripage_a9) --
    TIDAK memengaruhi hasil crop/resize-nya sama sekali.
    """
    try:
        img = pil_img.convert("RGB")
        orig_w, orig_h = img.size

        # 1. Full 4-Way Smart Crop Konten Aktif
        bg = Image.new(img.mode, img.size, (255, 255, 255))
        diff = ImageChops.difference(img, bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()

        if bbox:
            left, upper, right, lower = bbox
            left = max(0, left)
            upper = max(0, upper - 10)
            right = min(orig_w, right + 10)
            lower = min(orig_h, lower + 10)
            cropped_content = img.crop((left, upper, right, lower))
        else:
            cropped_content = img

        crop_w, crop_h = cropped_content.size

        # Kunci lebar isi gambar tepat sesuai lebar kertas fisik yang aktif
        target_width, _ = get_paper_dimensions(paper_width_mm)
        width_percent = (target_width / float(crop_w))
        target_height = int((float(crop_h) * float(width_percent)))

        final_img = cropped_content.resize((target_width, target_height), Image.Resampling.LANCZOS)
        return final_img

    except Exception as e:
        print(f"\n[{error_tag} ERROR] Gagal pada fungsi smart_crop_and_resize:")
        traceback.print_exc()
        raise e


def mm_to_px(mm, dpi=CROP_REFERENCE_DPI):
    """Konversi milimeter -> piksel pada dpi referensi crop manual."""
    return int(round(mm * dpi / 25.4))


def px_to_mm(px, dpi=CROP_REFERENCE_DPI):
    """Konversi piksel -> milimeter pada dpi referensi crop manual."""
    return px * 25.4 / dpi


def auto_detect_full_bbox(pil_img):
    """Deteksi bbox 4-arah konten aktif PERSIS sama seperti bagian awal
    smart_crop_and_resize (termasuk padding +-10px), tapi hanya mengembalikan
    koordinatnya (tidak langsung crop). Dipakai crop editor manual untuk
    menaruh posisi awal garis atas/bawah di titik yang masuk akal (bukan
    mulai dari 0), sebelum pengguna geser manual."""
    img = pil_img.convert("RGB")
    orig_w, orig_h = img.size
    bg = Image.new(img.mode, img.size, (255, 255, 255))
    diff = ImageChops.difference(img, bg)
    diff = ImageChops.add(diff, diff, 2.0, -100)
    bbox = diff.getbbox()
    if bbox:
        left, upper, right, lower = bbox
        left = max(0, left)
        upper = max(0, upper - 10)
        right = min(orig_w, right + 10)
        lower = min(orig_h, lower + 10)
        return left, upper, right, lower
    return 0, 0, orig_w, orig_h


def auto_detect_horizontal_bbox(pil_img):
    """Deteksi batas kiri/kanan konten aktif (buang spasi kosong kiri-kanan)
    dengan algoritma yang sama seperti smart_crop_and_resize, tapi HANYA
    sumbu horizontal -- dipakai crop manual supaya lebar konten tetap presisi
    otomatis sementara batas atas/bawah diatur manual oleh pengguna."""
    img = pil_img.convert("RGB")
    orig_w, orig_h = img.size
    bg = Image.new(img.mode, img.size, (255, 255, 255))
    diff = ImageChops.difference(img, bg)
    diff = ImageChops.add(diff, diff, 2.0, -100)
    bbox = diff.getbbox()
    if bbox:
        left, _, right, _ = bbox
        left = max(0, left)
        right = min(orig_w, right + 10)
        return left, right
    return 0, orig_w


def manual_crop_and_resize(pil_img, top_offset_px, bottom_offset_px,
                            paper_width_mm=DEFAULT_PAPER_WIDTH_MM, error_tag="LOGIC"):
    """
    Crop Manual dengan Pola Offset Tetap (Fixed Offset Pattern):
    Membuang persis `top_offset_px` piksel dari atas dan `bottom_offset_px`
    piksel dari bawah pada gambar MENTAH (raw, belum di-crop). Sisa bagian
    tengah TIDAK ikut diatur -- otomatis mengikuti panjang asli halaman
    tersebut, jadi cocok dipakai sebagai satu "pola" (pattern) yang di-apply
    rata ke semua halaman meskipun panjang tiap halaman berbeda-beda.

    Lebar kiri/kanan tetap dipotong otomatis (whitespace detection) dan
    dikunci ke lebar kertas fisik, sama seperti smart_crop_and_resize --
    hanya sumbu vertikal (atas/bawah) yang manual.
    """
    try:
        img = pil_img.convert("RGB")
        orig_w, orig_h = img.size

        left, right = auto_detect_horizontal_bbox(img)

        # Offset atas/bawah manual, di-clamp supaya tidak saling menabrak
        # dan tidak melebihi ukuran gambar (jaga-jaga halaman pendek).
        upper = max(0, min(int(top_offset_px), orig_h - 1))
        lower = max(upper + 1, orig_h - max(0, int(bottom_offset_px)))
        lower = min(lower, orig_h)

        cropped_content = img.crop((left, upper, right, lower))
        crop_w, crop_h = cropped_content.size

        target_width, _ = get_paper_dimensions(paper_width_mm)
        width_percent = (target_width / float(crop_w))
        target_height = int((float(crop_h) * float(width_percent)))

        final_img = cropped_content.resize((target_width, target_height), Image.Resampling.LANCZOS)
        return final_img

    except Exception as e:
        print(f"\n[{error_tag} ERROR] Gagal pada fungsi manual_crop_and_resize:")
        traceback.print_exc()
        raise e


def send_print_job(transport, pages_to_print, cropped_images_dict, paper_width_mm=DEFAULT_PAPER_WIDTH_MM,
                    progress_tag="SISTEM", done_tag="LOGIC"):
    """
    Membangun & mengirim urutan byte protokol PeriPage A9 lewat `transport`.

    `transport` harus punya method `.write(data: bytes)` -- bisa diisi
    UsbTransport atau (nanti) BluetoothTransport, keduanya harus sudah dalam
    keadaan `connect()`-ed sebelum fungsi ini dipanggil.

    Isi fungsi ini adalah pindahan 1:1 dari execute_printing() versi lama:
    HANYA `ep_out.write(...)` yang diganti `transport.write(...)`. Urutan
    command, nilai byte, dan seluruh `time.sleep(...)` (jeda yang dibutuhkan
    hardware printer, bukan spesifik USB) tetap persis sama.

    `progress_tag` / `done_tag` cuma memengaruhi label di console log (mis.
    peripage_logic.py pakai "SISTEM"/"LOGIC", package peripage_a9 pakai
    "LIBRARY"/"LIBRARY") -- tidak memengaruhi byte yang dikirim ke printer.
    """
    paper_width_px, bytes_per_row = get_paper_dimensions(paper_width_mm)

    # JABAT TANGAN UTAMA PERIPAGE A9
    init_bytes = [0x10, 0xff, 0xfe, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    transport.write(bytes(init_bytes))
    time.sleep(0.2)

    for idx in pages_to_print:
        print(f"[{progress_tag}] Mengirim data biner Halaman {idx+1}... (kertas {paper_width_mm}mm)")
        final_img = cropped_images_dict[idx]

        bw_img = final_img.convert("1")
        width, height = bw_img.size

        # PACKET HEADER HALAMAN
        page_header = bytearray([
            0x1d, 0x76, 0x30, 0x00,
            bytes_per_row & 0xff, (bytes_per_row >> 8) & 0xff,
            height & 0xff, (height >> 8) & 0xff
        ])
        transport.write(bytes(page_header))
        time.sleep(0.1)

        # =====================================================================
        # KIRIM KONTEN APA ADANYA (sesuai lebar kertas fisik aktif, WYSIWYG dengan preview smartcrop)
        # =====================================================================
        for y in range(height):
            row_bytes = bytearray()

            for x in range(0, paper_width_px, 8):
                byte_val = 0
                for bit in range(8):
                    if x + bit < width:
                        pixel = bw_img.getpixel((x + bit, y))
                        if pixel == 0:  # 0 = Hitam
                            byte_val |= (1 << (7 - bit))
                row_bytes.append(byte_val)

            # Kirim baris persis sesuai lebar kertas fisik aktif
            transport.write(bytes(row_bytes))
            time.sleep(0.005)

        # Perintah gulung kertas maju di akhir halaman (ESC J 64)
        transport.write(bytes([0x1b, 0x4a, 0x40]))
        time.sleep(0.5)

    transport.write(bytes([0x1b, 0x40]))
    print(f"[{done_tag}] Proses cetak dokumen selesai total!")
