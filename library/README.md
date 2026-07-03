# PeriPage A9 Universal Native USB Driver & GUI Printer

Driver native USB dan aplikasi antarmuka (GUI) mandiri yang ditulis menggunakan Python untuk printer thermal portabel **PeriPage A9**. Proyek ini dibuat karena ketiadaan driver USB resmi yang stabil untuk sistem operasi Linux. 

Driver ini **bebas dari ketergantungan library pihak ketiga seperti `ppa6` atau `PyBluez`**, murni menggunakan komunikasi *low-level* `pyusb` dengan integrasi algoritma **Full 4-Way Smart Crop** adaptif yang menjamin hasil cetakan fisik presisi 100% lurus di tengah (mengikuti spesifikasi kertas 77mm / area cetak efektif 72mm) tanpa terpotong di sisi kanan.

---

## ✨ Fitur Utama
* **Native USB Bitstream Driver**: Mengirimkan instruksi perintah biner dan pemanasan head thermal langsung ke endpoint USB printer (`0x09c5:0x0200`).
* **Full 4-Way Smart Crop**: Otomatis mendeteksi dan memotong ruang putih kosong (*whitespace margin*) di sisi Atas, Bawah, Kiri, dan Kanan dokumen PDF secara dinamis.
* **Scientific Center Locking (576px / Offset 32px)**: Mengonversi skala dokumen secara proporsional ke lebar cetak efektif printer (72mm) agar cetakan simetris di tengah gulungan kertas thermal.
* **Multi-Page Live Preview**: Navigasi interaktif halaman (`◀ Seb` dan `Sel ▶`) untuk melihat simulasi hasil potongan lembar kertas thermal secara real-time sebelum dicetak.
* **Linux Kernel Safe Detach**: Otomatis melepas kuncian driver bawaan Linux (`usblp`) dan mengembalikan status port secara aman pasca-cetak untuk mencegah error `[Errno 16] Resource Busy`.
* **Traceback Debugger**: Sistem pencatatan error mendalam yang otomatis mencetak log kegagalan sistem langsung ke tab terminal.

---

## 📂 Struktur Proyek Package
Pastikan susunan folder di komputer Linux Anda tertata dengan struktur modular standard Python berikut:

```text
peripage/
├── venv/                       # Virtual environment Python
├── requirements.txt            # Daftar dependensi library
├── pyproject.toml              # Konfigurasi standard modern build package
├── peripage_a9/                # Folder INTI Modul/Library Driver
│   ├── __init__.py             # Penanda modular package Python
│   └── driver.py               # Kode Logika Kelas Driver (PeriPageA9USB)
├── app.py                      # Aplikasi GUI utama (Tkinter Interface)
└── peripage-icon.png           # Gambar logo icon aplikasi (Format PNG)
```

---

## 🚀 Panduan Instalasi Lokal & Penggunaan

### 1. Install Dependensi Sistem Linux
Library pengolah dokumen `pdf2image` membutuhkan utilitas sistem `poppler`. Buka terminal Linux dan jalankan:
```bash
sudo apt update && sudo apt install poppler-utils -y
```

### 2. Setup Virtual Environment & Install Requirements
Masuk ke direktori utama proyek, buat ruang isolasi `venv`, dan pasang library dari file `requirements.txt`:
```bash
cd ~/Desktop/peripage
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3. Menjalankan Aplikasi
Karena aplikasi membutuhkan akses *low-level* untuk mengklaim kontrol port hardware USB, jalankan script `app.py` menggunakan akses administrator grafis:
```bash
sudo -E ./venv/bin/python3 app.py
```

---

## 🛠️ Panduan Build Menjadi Distribusi Package (`.whl`)

Proyek ini telah dikonfigurasi menggunakan standar modern `pyproject.toml` sehingga modul `peripage_a9` bisa dikompilasi menjadi file package distribusi biner (`.whl`) resmi yang dapat dibagikan atau dipasang di proyek lain menggunakan `pip`.

### 1. Install Utilitas Build Python
Pastikan virtual environment Anda aktif, lalu instal alat kompilasinya:
```bash
pip install build
```

### 2. Jalankan Proses Kompilasi Package
Jalankan perintah berikut di folder utama proyek tempat file `pyproject.toml` berada:
```bash
python3 -m build
```

### 3. Hasil Build
Setelah proses selesai, folder baru bernama `dist/` akan tercipta secara otomatis. Di dalamnya terdapat file distribusi biner library Anda:
* **`dist/peripage_a9_usb-1.0.0-py3-none-any.whl`** (Siap didistribusikan)

### 4. Cara Install dan Pakai Library di Komputer Lain
Di komputer Linux mana pun, Anda tidak perlu lagi menyalin kode mentah. Cukup bawa file `.whl` tersebut dan pasang langsung via pip:
```bash
pip install peripage_a9_usb-1.0.0-py3-none-any.whl
```
Setelah terinstal, programmer lain bisa mencetak dokumen lewat kabel USB menggunakan kode ringkas berikut:
```python
from peripage_a9 import PeriPageA9USB
from PIL import Image

# Hubungkan printer
printer = PeriPageA9USB()
if printer.connect():
    # Load gambar dokumen asli
    raw_img = Image.open("resi_nota.png")
    
    # Proses smart crop presisi tengah
    processed_img = printer.smart_crop_and_resize(raw_img)
    
    # Eksekusi cetak langsung ke USB
    printer.print_pages([0], {0: processed_img})
```

---

## 🖥️ Membuat Shortcut Desktop & Otomatis Login (Tanpa Password)

Agar aplikasi profesional ini bisa dibuka langsung lewat icon di Desktop secara instan tanpa perlu mengetikkan password `sudo` setiap saat, terapkan konfigurasi bypass berikut:

### 1. Daftarkan Pengecualian Keamanan Sudo (`visudo`)
Buka file keamanan sistem Linux dengan perintah:
```bash
sudo visudo
```
Gulir ke baris paling bawah, lalu tambahkan aturan berikut (Ganti `bagasalfariz` dengan username Linux Anda):
```text
bagasalfariz ALL=(ALL) NOPASSWD: /usr/local/bin/peripage-printer
```
*Simpan (`Ctrl+O`, `Enter`) dan keluar (`Ctrl+X`).*

### 2. Buat Script Executable Launcher
Buat file pembungkus agar sistem memanggil python dari dalam folder `venv` secara otomatis:
```bash
sudo nano /usr/local/bin/peripage-printer
```
Tempelkan kode skrip di bawah ini ke dalamnya:
```bash
#!/bin/bash
cd /home/bagasalfariz/Desktop/peripage
./venv/bin/python3 app.py
```
*Simpan dan berikan izin eksekusi penuh pada file biner tersebut:*
```bash
sudo chmod +x /usr/local/bin/peripage-printer
```

### 3. Buat File Shortcut Desktop (`.desktop`)
Buat file pintasan launcher baru langsung di Desktop Anda:
```bash
nano ~/Desktop/peripage-printer.desktop
```
Salin dan tempelkan konfigurasi entri berikut (Pastikan path Icon mengarah ke file gambar logo Anda yang valid):
```text
[Desktop Entry]
Version=1.0
Type=Application
Name=PeriPage PDF Printer
Comment=Smart Printer PDF via USB untuk PeriPage A9
Exec=sudo /usr/local/bin/peripage-printer
Icon=/home/bagasalfariz/Desktop/peripage/peripage-icon.png
Terminal=false
Categories=Utility;Office;
```
*Simpan, keluar, lalu berikan izin eksekusi grafis pada file shortcut:*
```bash
chmod +x ~/Desktop/peripage-printer.desktop
```
*(Opsional) Daftarkan juga ke menu start pencarian aplikasi sistem Linux Anda:*
```bash
sudo cp ~/Desktop/peripage-printer.desktop /usr/share/applications/
```

Sekarang Anda bisa mencetak file PDF secara cerdas, cepat, dan presisi langsung dengan melakukan klik ganda pada icon di Desktop Anda!
