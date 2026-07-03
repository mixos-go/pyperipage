"""
Alat Kalibrasi Lebar Cetak Fisik PeriPage A9
==============================================
Tujuan: mencari tahu LEBAR CETAK ASLI (dalam byte/piksel) yang benar-benar
sanggup dicetak utuh oleh unit printer kamu -- karena asumsi generik
"203dpi = 8 dot/mm" dari spesifikasi marketing ternyata TIDAK selalu cocok
dengan kapasitas riil firmware/hardware tiap unit.

CARA PAKAI:
1. Pastikan printer nyala & tersambung USB, kertas terpasang.
2. Jalankan:  python3 tools/calibrate_paper_width.py
3. Printer akan mencetak pola penggaris: garis vertikal tiap byte (8px),
   dan ANGKA INDEKS BYTE setiap 5 byte (0, 5, 10, 15, ... dst) dari kiri.
4. Lihat hasil cetakan fisik: catat ANGKA TERAKHIR yang masih tercetak
   PENUH & UTUH sebelum sisi kanan mulai terpotong/hilang.
5. Kalikan angka itu dengan 8 untuk dapat lebar piksel aman, atau langsung
   pakai nilai byte itu. Masukkan hasilnya sebagai CUSTOM_BYTES_PER_ROW di
   peripage_logic.py / driver.py (lihat instruksi di akhir skrip ini).

Pola dicetak pada lebar uji besar (100 byte / 800px) supaya mencakup semua
kemungkinan realistis (dari 58mm hingga lebih dari 77mm), lalu kamu tinggal
baca di mana potongannya terjadi.
"""
import sys
import os
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from PIL import Image, ImageDraw, ImageFont
import usb.core
import usb.util

from peripage_logic import force_detach_kernel

# Lebar uji: sengaja dibuat BESAR (lebih besar dari kemungkinan lebar asli)
# supaya potongannya justru kelihatan jelas -- itulah petunjuk batas aslinya.
TEST_WIDTH_BYTES = 100          # 800 px
TEST_WIDTH_PX = TEST_WIDTH_BYTES * 8
TICK_EVERY_BYTES = 5            # angka & garis panjang tiap 5 byte
IMG_HEIGHT = 260


def build_ruler_image():
    img = Image.new("1", (TEST_WIDTH_PX, IMG_HEIGHT), 1)  # 1 = putih
    draw = ImageDraw.Draw(img)

    try:
        font = ImageFont.load_default()
    except Exception:
        font = None

    for byte_idx in range(TEST_WIDTH_BYTES + 1):
        x = byte_idx * 8
        if x >= TEST_WIDTH_PX:
            break
        is_major = (byte_idx % TICK_EVERY_BYTES == 0)
        tick_h = 60 if is_major else 20
        draw.line([(x, 40), (x, 40 + tick_h)], fill=0, width=2 if is_major else 1)

        if is_major:
            label = str(byte_idx)
            draw.text((x + 2, 105), label, fill=0, font=font)
            # Garis vertikal panjang penuh supaya gampang dihitung di kertas fisik
            draw.line([(x, 0), (x, IMG_HEIGHT)], fill=0, width=1)

    draw.text((4, 4), f"KALIBRASI - Angka = indeks BYTE (kelipatan 8px) dari kiri", fill=0, font=font)
    draw.text((4, 20), f"Catat angka TERAKHIR yang masih utuh sebelum terpotong", fill=0, font=font)
    return img


def send_test_pattern(img):
    dev = force_detach_kernel()
    if dev is None:
        raise Exception("Printer tidak ditemukan secara fisik di port USB.")

    try:
        dev.set_configuration()
        cfg = dev.get_active_configuration()
        intf = cfg[(0, 0)]

        ep_out = usb.util.find_descriptor(
            intf,
            custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_OUT
        )
        if ep_out is None:
            raise Exception("Gagal memetakan pipa data (Endpoint OUT) USB Printer.")

        init_bytes = [0x10, 0xff, 0xfe, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        ep_out.write(bytes(init_bytes))
        time.sleep(0.2)

        bw_img = img.convert("1")
        width, height = bw_img.size
        bytes_per_row = TEST_WIDTH_BYTES

        page_header = bytearray([
            0x1d, 0x76, 0x30, 0x00,
            bytes_per_row & 0xff, (bytes_per_row >> 8) & 0xff,
            height & 0xff, (height >> 8) & 0xff
        ])
        ep_out.write(bytes(page_header))
        time.sleep(0.1)

        for y in range(height):
            row_bytes = bytearray()
            for x in range(0, TEST_WIDTH_PX, 8):
                byte_val = 0
                for bit in range(8):
                    if x + bit < width:
                        pixel = bw_img.getpixel((x + bit, y))
                        if pixel == 0:  # 0 = Hitam
                            byte_val |= (1 << (7 - bit))
                row_bytes.append(byte_val)
            ep_out.write(bytes(row_bytes))
            time.sleep(0.005)

        ep_out.write(bytes([0x1b, 0x4a, 0x40]))
        time.sleep(0.5)
        ep_out.write(bytes([0x1b, 0x40]))
        print("[KALIBRASI] Pola penggaris terkirim. Cek hasil cetak fisik.")

    finally:
        try:
            usb.util.release_interface(dev, 0)
            dev.attach_kernel_driver(0)
        except Exception:
            pass


if __name__ == "__main__":
    print(__doc__)
    input("Tekan ENTER untuk mulai mencetak pola kalibrasi...")
    try:
        ruler = build_ruler_image()
        send_test_pattern(ruler)
        print("""
=====================================================================
LANGKAH SELANJUTNYA:
1. Lihat kertas hasil cetak. Cari angka byte TERAKHIR yang masih utuh
   tercetak lengkap sebelum sisi kanan mulai kepotong/hilang.
2. Contoh: kalau angka terakhir yang utuh adalah 60, berarti lebar aman
   kamu adalah 60 byte (480px).
3. Buka peripage_logic.py dan library/peripage_a9/driver.py, lalu ganti:
       DOTS_PER_MM = 8
   dengan nilai kalibrasi manual, ATAU (lebih simpel) langsung override
   fungsi get_paper_dimensions() agar SELALU mengembalikan angka byte
   hasil kalibrasi kamu, tidak dihitung dari mm lagi. Kirim angka byte
   yang kamu temukan, saya bantu terapkan ke kode secara otomatis.
=====================================================================
""")
    except Exception:
        print("\n[KALIBRASI ERROR] Gagal mencetak pola uji:")
        traceback.print_exc()
