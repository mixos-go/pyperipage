#!/usr/bin/env bash
# ==============================================================================
# install_linux.sh -- Installer PeriPage A9 GUI untuk Linux
#
# Yang dilakukan skrip ini:
#   1. Menyalin source code aplikasi ke  ~/.local/share/pyperipage-a9/app
#   2. Membuat virtualenv Python khusus + install semua dependency (pip)
#   3. Membuat launcher  ~/.local/bin/pyperipage-a9
#   4. Membuat shortcut menu aplikasi (.desktop) + ikon, jadi muncul di
#      menu aplikasi seperti software lain (GNOME/KDE/XFCE, dll)
#   5. (Opsional, best-effort) Menyiapkan udev rule supaya printer PeriPage
#      A9 bisa diakses via USB tanpa sudo/root.
#
# Cara pakai:
#   chmod +x install_linux.sh
#   ./install_linux.sh
#
# Update di kemudian hari cukup pakai tombol "🔄 Cek Pembaruan..." di
# dalam aplikasi -- TIDAK perlu menjalankan skrip ini lagi, kecuali kamu
# sengaja mau instalasi ulang dari nol.
# ==============================================================================
set -euo pipefail

APP_NAME="PeriPage A9 GUI"
APP_ID="pyperipage-a9"
INSTALL_DIR="$HOME/.local/share/${APP_ID}"
APP_DIR="${INSTALL_DIR}/app"
VENV_DIR="${INSTALL_DIR}/venv"
BIN_DIR="$HOME/.local/bin"
LAUNCHER="${BIN_DIR}/${APP_ID}"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/${APP_ID}.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
ICON_FILE="${ICON_DIR}/${APP_ID}.png"

# Folder tempat skrip ini berada = folder source code aplikasi
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Memasang ${APP_NAME} ke ${INSTALL_DIR}"

# ------------------------------------------------------------------
# 1) Cek Python3 tersedia
# ------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 tidak ditemukan. Install python3 dulu (mis. 'sudo apt install python3 python3-venv')." >&2
    exit 1
fi

# ------------------------------------------------------------------
# 2) Best-effort: cek/pasang poppler-utils (dibutuhkan pdf2image) &
#    python3-venv/tk kalau distro berbasis apt. Tidak fatal kalau gagal
#    atau bukan distro apt -- pengguna tinggal pasang manual sesuai pesan.
# ------------------------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
    MISSING_APT_PKGS=()
    command -v pdftoppm >/dev/null 2>&1 || MISSING_APT_PKGS+=(poppler-utils)
    python3 -c "import tkinter" >/dev/null 2>&1 || MISSING_APT_PKGS+=(python3-tk)
    python3 -c "import venv" >/dev/null 2>&1 || MISSING_APT_PKGS+=(python3-venv)
    if [ "${#MISSING_APT_PKGS[@]}" -gt 0 ]; then
        echo "==> Beberapa paket sistem yang dibutuhkan belum terpasang: ${MISSING_APT_PKGS[*]}"
        echo "    Mencoba memasang otomatis via apt (butuh sudo)..."
        sudo apt-get update -y || true
        sudo apt-get install -y "${MISSING_APT_PKGS[@]}" || \
            echo "    Gagal memasang otomatis -- silakan pasang manual: sudo apt-get install ${MISSING_APT_PKGS[*]}"
    fi
else
    if ! command -v pdftoppm >/dev/null 2>&1; then
        echo "PERINGATAN: 'poppler-utils' (pdftoppm) tidak terdeteksi." >&2
        echo "  Aplikasi butuh ini untuk membaca file PDF. Pasang lewat package manager distro-mu," >&2
        echo "  misalnya: sudo dnf install poppler-utils   /   sudo pacman -S poppler" >&2
    fi
fi

# ------------------------------------------------------------------
# 3) Salin source code ke folder instalasi
# ------------------------------------------------------------------
mkdir -p "$INSTALL_DIR"
if [ -d "$APP_DIR" ]; then
    echo "==> Instalasi lama terdeteksi, membuat backup..."
    mv "$APP_DIR" "${APP_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
fi
mkdir -p "$APP_DIR"

# Salin HANYA berkas yang dipakai aplikasi desktop Tkinter ini -- SENGAJA
# tidak ikut menyalin folder flutter_app/, core_python/, library/, scripts/,
# .github/, atau dokumen markdown, karena itu bagian lain dari monorepo
# (app Flutter & backend servernya) yang tidak dibutuhkan sama sekali oleh
# installer desktop ini.
DESKTOP_APP_FILES=(
    "peripage_gui.py"
    "peripage_logic.py"
    "peripage_protocol.py"
    "crop_editor.py"
    "app_updater.py"
    "transport_usb.py"
    "bluetooth.py"
    "requirements.txt"
    "VERSION"
    "peripage-icon.png"
)
for f in "${DESKTOP_APP_FILES[@]}"; do
    if [ -f "${SOURCE_DIR}/${f}" ]; then
        cp "${SOURCE_DIR}/${f}" "${APP_DIR}/${f}"
    else
        echo "PERINGATAN: berkas '${f}' tidak ditemukan di source, dilewati." >&2
    fi
done
if [ -d "${SOURCE_DIR}/tools" ]; then
    cp -r "${SOURCE_DIR}/tools" "${APP_DIR}/tools"
fi

echo "==> Source code tersalin ke ${APP_DIR}"

# ------------------------------------------------------------------
# 4) Virtualenv + dependency
# ------------------------------------------------------------------
if [ ! -d "$VENV_DIR" ]; then
    echo "==> Membuat virtualenv Python di ${VENV_DIR}..."
    python3 -m venv "$VENV_DIR"
fi

echo "==> Memasang dependency Python (pip)..."
"${VENV_DIR}/bin/pip" install --upgrade pip --quiet
"${VENV_DIR}/bin/pip" install -r "${APP_DIR}/requirements.txt"

# ------------------------------------------------------------------
# 5) Launcher di ~/.local/bin
# ------------------------------------------------------------------
mkdir -p "$BIN_DIR"
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
# Launcher otomatis untuk ${APP_NAME} -- jangan diedit manual,
# dibuat ulang tiap kali install_linux.sh dijalankan.
exec "${VENV_DIR}/bin/python3" "${APP_DIR}/peripage_gui.py" "\$@"
EOF
chmod +x "$LAUNCHER"
echo "==> Launcher dibuat: ${LAUNCHER}"

if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo "PERINGATAN: ${BIN_DIR} belum ada di PATH kamu." >&2
    echo "  Tambahkan baris ini ke ~/.bashrc atau ~/.zshrc supaya bisa jalankan '${APP_ID}' dari terminal:" >&2
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" >&2
fi

# ------------------------------------------------------------------
# 6) Ikon + shortcut menu aplikasi (.desktop)
# ------------------------------------------------------------------
mkdir -p "$ICON_DIR"
if [ -f "${APP_DIR}/peripage-icon.png" ]; then
    cp "${APP_DIR}/peripage-icon.png" "$ICON_FILE"
fi

mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=Smart PDF/Image printer & preview untuk thermal printer PeriPage A9
Exec=${LAUNCHER}
Icon=${ICON_FILE}
Terminal=false
Categories=Utility;Office;Printing;
StartupWMClass=${APP_ID}
EOF
chmod +x "$DESKTOP_FILE"

update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true

echo "==> Shortcut menu aplikasi dibuat: ${DESKTOP_FILE}"

# ------------------------------------------------------------------
# 7) (Opsional, best-effort) udev rule supaya USB printer tidak butuh sudo
# ------------------------------------------------------------------
UDEV_RULE_FILE="/etc/udev/rules.d/99-peripage-a9.rules"
if command -v udevadm >/dev/null 2>&1 && [ ! -f "$UDEV_RULE_FILE" ]; then
    echo "==> Ingin memasang udev rule supaya printer bisa diakses tanpa sudo? (butuh sudo sekali) [y/N]"
    read -r ANSWER || ANSWER="n"
    if [[ "$ANSWER" =~ ^[Yy]$ ]]; then
        # Vendor ID umum utk PeriPage A9 (Bluetooth Low Energy printer dgn
        # jembatan USB serial) -- kalau device-mu beda VID/PID, edit rule
        # ini manual setelah instalasi.
        sudo tee "$UDEV_RULE_FILE" >/dev/null <<'EOR'
SUBSYSTEM=="usb", ATTR{idVendor}=="0483", MODE="0666", GROUP="plugdev"
EOR
        sudo udevadm control --reload-rules && sudo udevadm trigger || true
        echo "    udev rule dipasang. Cabut-colok ulang printer supaya berlaku."
    fi
fi

echo ""
echo "=================================================================="
echo " Instalasi selesai!"
echo " Buka '${APP_NAME}' dari menu aplikasi, atau jalankan dari terminal:"
echo "     ${LAUNCHER}"
echo ""
echo " Untuk update aplikasi nanti, TIDAK perlu jalankan skrip ini lagi --"
echo " cukup pakai tombol '🔄 Cek Pembaruan...' di dalam aplikasi."
echo "=================================================================="
