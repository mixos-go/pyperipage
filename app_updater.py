"""
app_updater.py

Mekanisme "Cek Pembaruan" sederhana untuk PeriPage A9 GUI, dua mode:

1. MODE GIT -- kalau folder aplikasi ini adalah git repo (ada folder
   `.git`), tombol "Cek Pembaruan" akan menjalankan `git fetch` lalu
   `git pull --ff-only` supaya sinkron dengan remote (mis. GitHub/GitLab
   tempat kamu simpan codebase-nya).

2. MODE PAKET (fallback, tanpa git) -- pengguna memilih file .zip "paket
   update" (hasil export/download source code terbaru dari developer),
   lalu seluruh berkas kode disalin menimpa folder aplikasi ini.

Di KEDUA mode, sebelum menimpa apa pun, selalu dibuat backup folder
aplikasi lama ke `<app_dir>_backup_<timestamp>` supaya pengguna bisa
rollback manual kalau update ternyata bermasalah.

PENTING: konfigurasi milik pengguna (lebar kertas terakhir, kalibrasi,
dsb.) TIDAK disimpan di folder aplikasi ini -- itu ada di
`~/.pyperipage/settings.json` (lihat CONFIG_DIR di peripage_protocol.py).
Jadi meng-update / menimpa folder aplikasi TIDAK akan menghapus
pengaturan pengguna.
"""
import os
import shutil
import subprocess
import zipfile
import tempfile
import datetime


def get_app_dir():
    """Folder tempat kode aplikasi ini berada (folder yang berisi
    app_updater.py, peripage_gui.py, dst)."""
    return os.path.dirname(os.path.abspath(__file__))


def is_git_repo(app_dir=None):
    app_dir = app_dir or get_app_dir()
    return os.path.isdir(os.path.join(app_dir, ".git"))


def read_local_version(app_dir=None):
    app_dir = app_dir or get_app_dir()
    vpath = os.path.join(app_dir, "VERSION")
    try:
        with open(vpath) as f:
            return f.read().strip()
    except Exception:
        return "unknown"


# Nama file/folder yang TIDAK ikut di-backup / TIDAK ikut ditimpa saat
# update -- cache python & metadata git tidak perlu (dan tidak boleh)
# ikut disalin sebagai "kode". Juga skip folder-folder lain di monorepo
# (Flutter app, backend server, package library, dsb) kalau kebetulan
# paket update dibuat dari export seluruh repo -- desktop app ini cuma
# butuh berkas Python root-nya saja.
SKIP_NAMES = {
    "__pycache__", ".git", ".gitignore",
    "flutter_app", "core_python", "library", "scripts", ".github",
}


def backup_app_dir(app_dir=None):
    app_dir = app_dir or get_app_dir()
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = f"{app_dir}_backup_{ts}"
    shutil.copytree(
        app_dir, backup_dir,
        ignore=shutil.ignore_patterns(
            "__pycache__", "*.pyc", ".git",
            "flutter_app", "core_python", "library", "scripts",
        )
    )
    return backup_dir


def git_pull(app_dir=None):
    """Jalankan git fetch + pull --ff-only. Return (ok: bool, pesan: str)."""
    app_dir = app_dir or get_app_dir()
    try:
        subprocess.run(
            ["git", "fetch", "--all"], cwd=app_dir,
            check=True, capture_output=True, text=True
        )
        status = subprocess.run(
            ["git", "status", "-uno"], cwd=app_dir,
            capture_output=True, text=True
        )
        if "up to date" in status.stdout.lower() or "up-to-date" in status.stdout.lower():
            return False, "Aplikasi sudah menggunakan versi terbaru dari remote."

        backup_dir = backup_app_dir(app_dir)

        pull = subprocess.run(
            ["git", "pull", "--ff-only"], cwd=app_dir,
            capture_output=True, text=True
        )
        if pull.returncode != 0:
            return False, (
                "Gagal menarik pembaruan (git pull):\n\n"
                f"{pull.stderr.strip()}\n\n"
                "Kemungkinan ada perubahan lokal yang bentrok. "
                "Backup versi lama tetap dibuat di:\n"
                f"{backup_dir}"
            )
        return True, (
            "Berhasil update ke versi terbaru.\n\n"
            f"{pull.stdout.strip()}\n\n"
            f"Backup versi lama disimpan di:\n{backup_dir}"
        )
    except FileNotFoundError:
        return False, (
            "Perintah 'git' tidak ditemukan di sistem ini.\n"
            "Install git terlebih dulu, atau gunakan mode Paket Update (.zip)."
        )
    except subprocess.CalledProcessError as e:
        return False, f"Gagal menghubungi remote git:\n\n{e.stderr}"
    except Exception as e:
        return False, f"Error tidak terduga saat update:\n\n{e}"


def extract_zip_to_temp(zip_path):
    """Ekstrak paket update .zip ke folder sementara, lalu kembalikan
    path folder yang benar-benar berisi source code (turun satu level
    kalau ternyata isi zip cuma satu folder pembungkus di root)."""
    tmp_dir = tempfile.mkdtemp(prefix="peripage_update_")
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(tmp_dir)

    entries = [e for e in os.listdir(tmp_dir) if not e.startswith("__MACOSX")]
    if len(entries) == 1 and os.path.isdir(os.path.join(tmp_dir, entries[0])):
        return os.path.join(tmp_dir, entries[0])
    return tmp_dir


def apply_package_update(source_dir, app_dir=None):
    """Salin semua berkas dari `source_dir` (folder paket update yang
    sudah diekstrak) ke `app_dir`, menimpa yang lama. Backup dibuat
    dulu sebelum menimpa apa pun. Return (ok: bool, pesan: str)."""
    app_dir = app_dir or get_app_dir()

    if not os.path.isdir(source_dir):
        return False, f"Folder sumber update tidak ditemukan:\n{source_dir}"

    try:
        backup_dir = backup_app_dir(app_dir)

        copied = []
        for root, dirs, files in os.walk(source_dir):
            dirs[:] = [d for d in dirs if d not in SKIP_NAMES]
            rel = os.path.relpath(root, source_dir)
            target_root = app_dir if rel == "." else os.path.join(app_dir, rel)
            os.makedirs(target_root, exist_ok=True)
            for fname in files:
                if fname in SKIP_NAMES:
                    continue
                src_f = os.path.join(root, fname)
                dst_f = os.path.join(target_root, fname)
                shutil.copy2(src_f, dst_f)
                copied.append(os.path.relpath(dst_f, app_dir))

        return True, (
            f"Berhasil menyalin {len(copied)} berkas dari paket update.\n\n"
            f"Backup versi lama disimpan di:\n{backup_dir}"
        )
    except Exception as e:
        return False, f"Gagal menerapkan paket update:\n\n{e}"
