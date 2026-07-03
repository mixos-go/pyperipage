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

def main():
    """
    Menjalankan server FastAPI untuk komunikasi dengan Flutter Desktop
    Server berjalan di localhost:8000 (default) atau port dari environment variable
    """
    port = int(os.environ.get("PERIPAGE_PORT", 8000))
    host = os.environ.get("PERIPAGE_HOST", "127.0.0.1")
    
    print(f"🖨️  Starting PeriPage Desktop Backend on {host}:{port}")
    print(f"📡 Waiting for Flutter Desktop connection...")
    
    # Jalankan server dengan reload=False untuk production
    uvicorn.run(
        "server:app",
        host=host,
        port=port,
        reload=False,
        log_level="info",
        workers=1
    )

if __name__ == "__main__":
    main()
