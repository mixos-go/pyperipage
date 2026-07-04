"""
Desktop Entry Point for PeriPage A9 Application
Menjalankan FastAPI server secara headless untuk Flutter Desktop
"""
import uvicorn
import sys
import os

# Pastikan path core_python ada di sys.path
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

# PENTING (fix Juli 2026): import `server` LANGSUNG di sini (statement biasa
# di top-level), BUKAN cuma dirujuk lewat string "server:app" di
# uvicorn.run(). PyInstaller melakukan analisis statis untuk tahu module apa
# saja yang perlu dibundle -- `import server` biasa BISA terdeteksi & ikut
# dibundle, sedangkan uvicorn.run("server:app", ...) minta uvicorn
# nge-import ulang "server" secara DINAMIS lewat importlib saat runtime, dan
# itu gagal di binary hasil PyInstaller dengan error persis:
#   "ERROR: Error loading ASGI app. Could not import module 'server'."
# walau file server.py ada persis di folder yang sama dengan binary-nya.
import server


def main():
    """
    Menjalankan server FastAPI untuk komunikasi dengan Flutter Desktop
    Server berjalan di localhost:8000 (default) atau port dari environment variable
    """
    port = int(os.environ.get("PERIPAGE_PORT", 8000))
    host = os.environ.get("PERIPAGE_HOST", "127.0.0.1")
    
    print(f"🖨️  Starting PeriPage Desktop Backend on {host}:{port}")
    print(f"📡 Waiting for Flutter Desktop connection...")
    
    # Kirim OBJEK app yang sudah di-import langsung (server.app), BUKAN
    # string "server:app" -- lihat komentar `import server` di atas.
    # Catatan: `workers` dihapus karena uvicorn MEWAJIBKAN app dikirim
    # sebagai string kalau workers > 1 (butuh re-import per worker process);
    # untuk workers=1 (default) app instance langsung tetap didukung penuh.
    uvicorn.run(
        server.app,
        host=host,
        port=port,
        reload=False,
        log_level="info",
    )

if __name__ == "__main__":
    main()
