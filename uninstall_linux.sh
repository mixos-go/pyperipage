#!/usr/bin/env bash
# Uninstaller PeriPage A9 GUI untuk Linux.
# Menghapus instalasi (venv + source code + shortcut menu + ikon).
# Pengaturan pengguna di ~/.pyperipage TIDAK dihapus otomatis -- dihapus
# manual kalau memang mau bersih total, lihat pesan di akhir skrip.
set -euo pipefail

APP_ID="pyperipage-a9"
INSTALL_DIR="$HOME/.local/share/${APP_ID}"
BIN_DIR="$HOME/.local/bin"
LAUNCHER="${BIN_DIR}/${APP_ID}"
DESKTOP_FILE="$HOME/.local/share/applications/${APP_ID}.desktop"
ICON_FILE="$HOME/.local/share/icons/hicolor/256x256/apps/${APP_ID}.png"

echo "Ini akan menghapus:"
echo "  - $INSTALL_DIR"
echo "  - $LAUNCHER"
echo "  - $DESKTOP_FILE"
echo "  - $ICON_FILE"
read -rp "Lanjutkan? [y/N] " ANSWER
if [[ ! "$ANSWER" =~ ^[Yy]$ ]]; then
    echo "Dibatalkan."
    exit 0
fi

rm -rf "$INSTALL_DIR"
rm -f "$LAUNCHER"
rm -f "$DESKTOP_FILE"
rm -f "$ICON_FILE"
update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

echo "Selesai. Aplikasi sudah dihapus."
echo "Pengaturan pengguna (lebar kertas, kalibrasi) masih ada di ~/.pyperipage"
echo "Hapus manual folder itu juga kalau mau benar-benar bersih:"
echo "  rm -rf ~/.pyperipage"
