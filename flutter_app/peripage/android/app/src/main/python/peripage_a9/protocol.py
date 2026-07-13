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
import zlib
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
# OVERRIDE KALIBRASI MANUAL
# Kalau hasil tes tools/calibrate_paper_width.py menunjukkan lebar cetak
# asli unit kamu BEDA dari asumsi 8 dot/mm, isi di sini nilai byte yang
# terbukti aman dari kalibrasi (mengalahkan hitungan mm otomatis).
# Format: {lebar_mm_yang_dipilih_di_GUI: lebar_byte_hasil_kalibrasi}
# Hasil kalibrasi fisik (03 Jul 2026): pola ruler terpotong antara byte
# 70-75 pada mode kertas 77mm -> dipakai 70 byte (560px) sebagai batas aman.
CALIBRATED_BYTES_PER_ROW = {77: 70}
# =====================================================================


# =====================================================================
# PILIHAN PROTOKOL: RAW vs COMPRESSED
#
# Hasil reverse-engineering app resmi PeriPage (method `u0.h.l()`, lihat
# PERIPAGE_PROTOCOL.md yang diberikan pengguna, Juli 2026): printer
# generasi baru (A9 dst) sebenarnya menerima bitmap TERKOMPRESI zlib
# (header `1F 00 ...`), BUKAN format RAW 1bpp polos (header `1D 76 30`)
# yang sejauh ini dipakai fungsi ini untuk SEMUA device.
#
# PENTING -- KEPUTUSAN DESAIN: mode RAW (di bawah) TIDAK DIUBAH SAMA
# SEKALI, tetap jadi DEFAULT untuk device yang tidak match persis daftar
# resmi -- karena RAW sudah terbukti menghasilkan print fisik yang benar
# (sudah dikalibrasi & di-screenshot sukses). Matching device compressed
# SENGAJA ketat (persis seperti kode asli u0.h.l(), tidak ada heuristik
# tambahan seperti strip suffix "_BLE") karena salah pilih protokol bisa
# bikin hasil cetak rusak/blank total, dan itu tidak bisa saya verifikasi
# tanpa akses ke hardware fisik. Device dengan nama tidak match persis
# (termasuk "PeriPage_A9_BLE") tetap dapat RAW secara default, TAPI bisa
# di-force manual lewat parameter `force_protocol` (diekspos ke UI lewat
# Settings > Protokol Cetak) supaya user yang PUNYA unit fisik bisa tes
# & verifikasi sendiri mode mana yang benar untuk device mereka.
# =====================================================================
COMPRESSED_MODE_EXACT_NAMES = {
    "PeriPage_A9", "PeriPage_A9+", "PeriPage_A9Pro+", "PeriPage_A9s",
    "PeriPage_Q9s", "PeriPage_A9sMAX", "PeriPage_A9MAX", "PeriPage_Q9Pro+",
    "PeriPage_Q10s", "PeriPage_A40", "PeriPage_H2", "PeriPage_H2+",
    "PeriPage_P40", "PeriPage_P9", "SQAI_PP_G10", "SQAI_PP_G40",
    "PeriPage_A3X", "PeriPage_A3X+", "PeriPage_A40+", "PeriPage_A40Pro+",
    "PeriPage_A40Pro", "PeriPage_Y200", "PeriPage_Y200+",
}
COMPRESSED_MODE_PREFIXES = (
    "PeriPage_A8_", "PeriPage_A8+", "PRT1_", "PPG_P40W", "PPG_P40",
)


def uses_compressed_protocol(device_name) -> bool:
    """
    True kalau nama device COCOK PERSIS dengan daftar resmi printer yang
    pakai protokol COMPRESSED (zlib) -- lihat komentar arsitektur di atas.
    """
    if not device_name:
        return False
    if device_name in COMPRESSED_MODE_EXACT_NAMES:
        return True
    return any(device_name.startswith(p) for p in COMPRESSED_MODE_PREFIXES)


def _pack_bitmap_1bpp(bw_img, target_width_px, height):
    """
    Bit-packing 1bpp MSB-first per baris, dipadatkan ke target_width_px
    (lebar kertas fisik AKTIF, bukan lebar mentah gambar) -- logic BYTE-
    FOR-BYTE SAMA dengan cara mode RAW membangun row_bytes di bawah, cuma
    hasilnya diakumulasi jadi satu buffer besar (buat di-zlib) alih-alih
    ditulis baris per baris. Ini menjamin kedua mode WYSIWYG-konsisten:
    crop & bit pattern-nya identik, bedanya cuma kompresi + cara kirim.
    """
    row_bytes_count = target_width_px // 8
    img_width, _ = bw_img.size
    out = bytearray(row_bytes_count * height)
    for y in range(height):
        for x in range(0, target_width_px, 8):
            byte_val = 0
            for bit in range(8):
                px_x = x + bit
                if px_x < img_width and bw_img.getpixel((px_x, y)) == 0:  # 0 = hitam
                    byte_val |= (1 << (7 - bit))
            out[y * row_bytes_count + (x // 8)] = byte_val
    return bytes(out)


def _build_compressed_page_packet(width_dots, height, bitmap_1bpp):
    """Header `1F 00` + payload zlib (2-byte header zlib CMF+FLG dibuang) --
    format resmi printer generasi baru (A9 dst). Lihat PERIPAGE_PROTOCOL.md
    §2.2 & §3 untuk detail hasil reverse-engineering-nya."""
    compressed = zlib.compress(bitmap_1bpp)[2:]
    length = len(compressed)
    header = bytes([
        0x1f, 0x00,
        (width_dots >> 8) & 0xff, width_dots & 0xff,
        (height >> 8) & 0xff, height & 0xff,
        (length >> 24) & 0xff, (length >> 16) & 0xff,
        (length >> 8) & 0xff, length & 0xff,
    ])
    return header + compressed


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


def crop_to_rect(pil_img, left: float, top: float, right: float, bottom: float, error_tag="LOGIC"):
    """
    Manual Crop Editor: potong gambar sesuai rectangle yang user pilih
    sendiri (drag di UI), dalam koordinat ternormalisasi 0.0-1.0 (bukan
    pixel) supaya konsisten dipakai lintas resolusi gambar/thumbnail.

    Beda dengan `resize_to_paper_width` (yang cuma resize tanpa crop apa
    pun) -- ini benar-benar MEMOTONG gambar ke area pilihan user, baru
    hasilnya diserahkan ke resize_to_paper_width() buat dikunci ke lebar
    kertas fisik.

    Args:
        left, top, right, bottom: fraksi 0.0-1.0 dari lebar/tinggi gambar asli.
    """
    try:
        img = pil_img.convert("RGB")
        w, h = img.size
        box = (
            max(0, int(left * w)),
            max(0, int(top * h)),
            min(w, int(right * w)),
            min(h, int(bottom * h)),
        )
        if box[2] <= box[0] or box[3] <= box[1]:
            raise ValueError(f"Crop rect tidak valid: {box}")
        return img.crop(box)
    except Exception as e:
        print(f"\n[{error_tag} ERROR] Gagal pada fungsi crop_to_rect:")
        traceback.print_exc()
        raise e


def resize_to_paper_width(pil_img, paper_width_mm=DEFAULT_PAPER_WIDTH_MM, error_tag="LOGIC"):
    """
    Mode MANUAL (lawan dari smart_crop_and_resize): cuma resize gambar ASLI
    ke lebar kertas, TANPA auto-trim whitespace 4-arah. Dipakai kalau user
    pilih toggle "Manual Crop" di Print Screen -- untuk kasus gambar yang
    memang sengaja punya margin/whitespace yang tidak boleh dipotong
    otomatis (mis. label dengan border kosong yang disengaja).
    """
    try:
        img = pil_img.convert("RGB")
        orig_w, orig_h = img.size
        target_width, _ = get_paper_dimensions(paper_width_mm)
        width_percent = target_width / float(orig_w)
        target_height = int(orig_h * width_percent)
        return img.resize((target_width, target_height), Image.Resampling.LANCZOS)
    except Exception as e:
        print(f"\n[{error_tag} ERROR] Gagal pada fungsi resize_to_paper_width:")
        traceback.print_exc()
        raise e


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


def send_print_job(transport, pages_to_print, cropped_images_dict, paper_width_mm=DEFAULT_PAPER_WIDTH_MM,
                    progress_tag="SISTEM", done_tag="LOGIC", device_name=None, force_protocol=None):
    """
    Membangun & mengirim urutan byte protokol PeriPage A9 lewat `transport`.

    `transport` harus punya method `.write(data: bytes)` -- bisa diisi
    UsbTransport atau BluetoothTransport, keduanya harus sudah dalam
    keadaan `connect()`-ed sebelum fungsi ini dipanggil.

    RAW mode (default, TIDAK DIUBAH dari implementasi lama): pindahan 1:1
    dari execute_printing() versi lama, HANYA `ep_out.write(...)` yang
    diganti `transport.write(...)`. Urutan command, nilai byte, dan seluruh
    `time.sleep(...)` tetap persis sama -- ini yang sudah terbukti jalan
    lewat kalibrasi fisik & print sukses.

    COMPRESSED mode (baru, Juli 2026): dipilih otomatis kalau `device_name`
    match persis daftar resmi (lihat uses_compressed_protocol()), atau
    dipaksa manual lewat `force_protocol` ("raw"|"compressed"|None=auto).
    Kirim SATU packet berisi bitmap zlib-compressed per halaman (bukan
    ribuan write per baris) -- lihat PERIPAGE_PROTOCOL.md §2.2/§3.

    `progress_tag` / `done_tag` cuma memengaruhi label di console log --
    tidak memengaruhi byte yang dikirim ke printer.
    """
    if force_protocol == "compressed":
        use_compressed = True
    elif force_protocol == "raw":
        use_compressed = False
    else:
        use_compressed = uses_compressed_protocol(device_name)

    paper_width_px, bytes_per_row = get_paper_dimensions(paper_width_mm)

    # JABAT TANGAN UTAMA PERIPAGE A9 (TIDAK DIUBAH -- sudah terbukti jalan
    # lewat kalibrasi fisik, lihat CALIBRATED_BYTES_PER_ROW di atas). Sama
    # dipakai untuk KEDUA mode -- ini handshake koneksi, bukan bagian dari
    # format encoding bitmap.
    init_bytes = [0x10, 0xff, 0xfe, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    transport.write(bytes(init_bytes))
    time.sleep(0.2)

    for idx in pages_to_print:
        protocol_label = "COMPRESSED" if use_compressed else "RAW"
        print(f"[{progress_tag}] Mengirim data biner Halaman {idx+1}... (kertas {paper_width_mm}mm, protokol {protocol_label})")
        final_img = cropped_images_dict[idx]

        bw_img = final_img.convert("1")
        width, height = bw_img.size

        if use_compressed:
            # ================================================================
            # MODE COMPRESSED: bangun 1 buffer bitmap penuh, zlib-compress,
            # kirim SATU packet (header 1F 00 + payload) -- bukan ribuan
            # write per baris seperti RAW. Ini juga mengurangi jumlah
            # operasi transport (khususnya BLE) per halaman secara drastis.
            # ================================================================
            bitmap_1bpp = _pack_bitmap_1bpp(bw_img, paper_width_px, height)
            packet = _build_compressed_page_packet(paper_width_px, height, bitmap_1bpp)
            transport.write(packet)
            time.sleep(0.1)
        else:
            # ================================================================
            # MODE RAW (default, TIDAK DIUBAH): kirim header lalu bitmap
            # baris-per-baris, persis seperti implementasi lama.
            # ================================================================
            page_header = bytearray([
                0x1d, 0x76, 0x30, 0x00,
                bytes_per_row & 0xff, (bytes_per_row >> 8) & 0xff,
                height & 0xff, (height >> 8) & 0xff
            ])
            transport.write(bytes(page_header))
            time.sleep(0.1)

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

                transport.write(bytes(row_bytes))
                time.sleep(0.005)

        # Perintah gulung kertas maju di akhir halaman (ESC J 64) -- SAMA
        # untuk kedua mode (perintah generik, bukan bagian format bitmap).
        transport.write(bytes([0x1b, 0x4a, 0x40]))
        time.sleep(0.5)

    transport.write(bytes([0x1b, 0x40]))
    print(f"[{done_tag}] Proses cetak dokumen selesai total!")
