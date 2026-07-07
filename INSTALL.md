# PeriPage A9 GUI — Panduan Instalasi & Update

> Repo ini adalah monorepo: aplikasi desktop Tkinter (file `.py` di root,
> panduan ini), `flutter_app/` (aplikasi mobile Flutter), `core_python/`
> (backend server untuk app Flutter), dan `library/` (paket Python
> `peripage_a9` yang bisa diinstal via pip). **Installer & tombol Cek
> Pembaruan di panduan ini HANYA mengurus aplikasi desktop Tkinter** --
> tidak menyentuh/menyalin `flutter_app/`, `core_python/`, atau `library/`.

## Instalasi (sekali jalan)

### Linux
```bash
chmod +x install_linux.sh
./install_linux.sh
```
Ini akan:
- Menyalin aplikasi ke `~/.local/share/pyperipage-a9/app`
- Membuat virtualenv Python + install semua dependency-nya sendiri
- Membuat shortcut di **menu aplikasi** (muncul seperti software lain, lengkap dengan ikon)
- Membuat perintah `pyperipage-a9` yang bisa dipanggil dari terminal

Butuh `python3` dan `poppler-utils` (untuk baca PDF) — skrip akan mencoba memasang otomatis lewat `apt` kalau memungkinkan; kalau distro-mu bukan berbasis `apt`, pasang manual dulu (`dnf install poppler-utils`, `pacman -S poppler`, dst).

### Windows
Buka PowerShell **di folder source code ini**, lalu:
```powershell
powershell -ExecutionPolicy Bypass -File install_windows.ps1
```
Ini akan:
- Menyalin aplikasi ke `%LOCALAPPDATA%\PyPeriPageA9\app`
- Membuat virtual environment Python + install dependency
- Membuat shortcut di **Desktop** dan **Start Menu**

Butuh Python 3 sudah terpasang (centang "Add python.exe to PATH" saat instal Python). Aplikasi ini juga butuh **poppler** untuk membaca PDF — instruksinya akan muncul di layar saat instalasi kalau belum terpasang.

---

## Update aplikasi (kalau ada perubahan kode)

**Tidak perlu jalankan installer lagi.** Di dalam aplikasi ada tombol:

> 🔄 **Cek Pembaruan...** (pojok kiri atas)

Ada 2 cara kerja tombol ini, otomatis dipilih sesuai situasi:

1. **Kalau folder aplikasi adalah git repository** (misalnya kamu clone dari GitHub/GitLab) → tombol ini akan otomatis `git pull` versi terbaru dari remote.
2. **Kalau bukan git repo** → tombol ini akan minta kamu memilih file **.zip** paket update (source code terbaru), lalu menyalinnya menimpa instalasi yang ada.

Di kedua cara, **backup otomatis** dibuat dulu sebelum menimpa apa pun (folder `..._backup_<tanggal_jam>` di sebelah folder aplikasi), dan **pengaturan pengguna** (lebar kertas terakhir, kalibrasi) **tidak pernah ikut tertimpa** karena disimpan terpisah di:
- Linux: `~/.pyperipage/settings.json`
- Windows: `%USERPROFILE%\.pyperipage\settings.json`

Setelah update, tutup dan buka ulang aplikasi supaya perubahan kode berlaku.

---

## Uninstall

- Linux: `./uninstall_linux.sh`
- Windows: `powershell -ExecutionPolicy Bypass -File uninstall_windows.ps1`

Keduanya akan menanyakan konfirmasi dulu, dan tidak menghapus folder pengaturan pengguna (`~/.pyperipage`) secara otomatis.
