#!/usr/bin/env python3
"""
sync_peripage_a9.py

`library/peripage_a9/` adalah SOURCE OF TRUTH untuk logic driver printer
PeriPage A9 (kalibrasi, smart-crop, protokol byte, dst) yang dipakai SEMUA
developer & SEMUA target build (desktop via core_python/, Android via
Chaquopy). Sebelumnya ada 3 copy `peripage_a9/` yang di-maintain manual
(library/, core_python/, android/.../python/) TANPA mekanisme apa pun buat
mendeteksi kalau salah satu ketinggalan update -- ini bikin logic yang
sudah terkalibrasi bisa diam-diam divergen tanpa ada yang sadar.

Script ini punya 2 mode:

  --check   (dipakai CI, lihat build-multi-platform.yml job `setup`)
            Bandingkan isi core_python/ & android/ terhadap library/.
            Exit code 1 kalau ADA perbedaan -- build langsung gagal dengan
            pesan jelas, developer wajib jalankan --apply & commit dulu
            sebelum bisa merge/build.

  --apply   (dipakai developer secara lokal)
            Copy file dari library/ ke core_python/ & android/, timpa apa
            pun yang ada di sana. Jalankan ini SETELAH mengedit
            library/peripage_a9/, supaya perubahan ikut ke semua target.

PENTING -- FILE YANG DIKECUALIKAN dari sync ke Android:
  transport_usb.py, transport_ble.py, & barcode_detect.py TIDAK di-sync ke
  folder Android. Ketiganya SENGAJA berbeda di Android -- isinya jembatan
  tipis ke implementasi Kotlin native (NativeUsbTransport.kt,
  NativeBleTransport.kt, NativeBarcodeDetector.kt), BUKAN implementasi
  pyusb/bleak/pyzbar seperti di desktop, karena ketiga library itu butuh
  native code yang tidak bisa jalan di Android lewat Chaquopy (lihat
  komentar di file-file itu sendiri untuk detail). File-file lain
  (driver.py, protocol.py, __init__.py) 100% platform-agnostic dan WAJIB
  identik di semua tempat.

Cara pakai:
  python scripts/sync_peripage_a9.py --check    # dipanggil CI
  python scripts/sync_peripage_a9.py --apply    # dipanggil developer
"""
import argparse
import filecmp
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO_ROOT / "library" / "peripage_a9"

# (target_dir, files_to_sync)
TARGETS = [
    (
        REPO_ROOT / "core_python" / "peripage_a9",
        ["__init__.py", "driver.py", "protocol.py", "transport_usb.py", "transport_ble.py", "barcode_detect.py"],
    ),
    (
        REPO_ROOT / "flutter_app" / "peripage" / "android" / "app" / "src" / "main" / "python" / "peripage_a9",
        # transport_usb.py, transport_ble.py, & barcode_detect.py SENGAJA
        # TIDAK disync -- ketiganya butuh implementasi native yang tidak
        # bisa jalan di Chaquopy (pyusb/bleak/pyzbar semua butuh native
        # code), jadi Android punya versi sendiri yang delegasi ke Kotlin.
        # Lihat docstring di masing-masing file untuk detail.
        ["__init__.py", "driver.py", "protocol.py"],
    ),
]


def check() -> int:
    mismatches = []
    for target_dir, files in TARGETS:
        for filename in files:
            src = SOURCE_DIR / filename
            dst = target_dir / filename
            if not dst.exists():
                mismatches.append(f"HILANG: {dst.relative_to(REPO_ROOT)} (tidak ada, seharusnya sync dari library/)")
                continue
            if not filecmp.cmp(src, dst, shallow=False):
                mismatches.append(f"BEDA:   {dst.relative_to(REPO_ROOT)} != library/peripage_a9/{filename}")

    if mismatches:
        print("=" * 70)
        print("SYNC CHECK GAGAL: peripage_a9 tidak sinkron dengan library/ (source of truth)")
        print("=" * 70)
        for m in mismatches:
            print(f"  - {m}")
        print()
        print("Jalankan ini lokal, lalu commit hasilnya:")
        print("    python scripts/sync_peripage_a9.py --apply")
        print("=" * 70)
        return 1

    print("OK: core_python/ & android/ sudah sinkron dengan library/peripage_a9/ (source of truth).")
    return 0


def apply() -> int:
    for target_dir, files in TARGETS:
        target_dir.mkdir(parents=True, exist_ok=True)
        for filename in files:
            src = SOURCE_DIR / filename
            dst = target_dir / filename
            shutil.copyfile(src, dst)
            print(f"Synced -> {dst.relative_to(REPO_ROOT)}")
    print("Selesai. Review `git diff`, lalu commit.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true", help="Cek sinkronisasi (dipakai CI), exit 1 kalau beda.")
    group.add_argument("--apply", action="store_true", help="Timpa core_python/ & android/ dari library/.")
    args = parser.parse_args()

    if not SOURCE_DIR.exists():
        print(f"ERROR: source of truth tidak ditemukan di {SOURCE_DIR}")
        return 1

    return check() if args.check else apply()


if __name__ == "__main__":
    sys.exit(main())
