# PeriPage A9 - Desktop Build Guide

Panduan build aplikasi PeriPage A9 untuk Windows, macOS, dan Linux dengan Python backend embedded.

## Arsitektur

Aplikasi desktop menggunakan arsitektur hybrid:
- **Flutter**: UI/UX modern (Windows, macOS, Linux)
- **Python Backend**: Logika printer, protokol ESC/POS, USB/BLE transport
- **PyInstaller**: Membungkus Python menjadi executable standalone
- **Auto-start**: Backend otomatis dijalankan saat aplikasi Flutter dibuka

## Prerequisites

### Semua Platform
- Python 3.11+
- Flutter 3.x
- Git

### Windows
```bash
pip install pyinstaller
```

### macOS
```bash
pip install pyinstaller
# Untuk M1/M2: tambahkan --target_arch flag jika perlu
```

### Linux
```bash
pip install pyinstaller
sudo apt-get install libusb-1.0-0-dev  # Untuk USB support
```

## Build Steps

### 1. Build Python Backend

#### Windows
```bash
cd /workspace
build\\desktop\\build.bat
```

#### macOS / Linux
```bash
cd /workspace
chmod +x build/desktop/build.sh
./build/desktop/build.sh
```

Output akan tersimpan di: `build/desktop/dist/`
- Windows: `peripage-backend.exe`
- macOS/Linux: `peripage-backend`

### 2. Build Flutter Desktop

```bash
cd flutter_app/peripage

# Windows
flutter build windows

# macOS
flutter build macos

# Linux
flutter build linux
```

### 3. Distribusi

#### Windows
Copy folder hasil build:
```
build/windows/x64/runner/Release/
├── peripage.exe          # Flutter app
└── ../../../../../build/desktop/dist/peripage-backend.exe  # Python backend
```

#### macOS
Bundle Python backend ke dalam app:
```bash
cp build/desktop/dist/peripage-backend \
   build/macos/Build/Products/Release/peripage.app/Contents/Resources/backend/
```

#### Linux
Copy binary ke folder yang sama dengan executable Flutter:
```bash
cp build/desktop/dist/peripage-backend \
   build/linux/x64/release/bundle/
```

## Cara Kerja

1. **Auto-start Backend**
   - Saat aplikasi Flutter dibuka, `DesktopBackendService` akan otomatis menjalankan Python backend
   - Backend berjalan sebagai subprocess di background
   - Komunikasi via HTTP localhost:8000

2. **Communication Flow**
   ```
   Flutter UI → HTTP Request → Python Backend → USB/BLE → Printer
   ```

3. **Cleanup**
   - Backend otomatis ditutup saat aplikasi Flutter ditutup
   - Menggunakan signal handling yang proper untuk setiap OS

## Troubleshooting

### Backend tidak start
- Cek apakah Python executable ada di folder yang benar
- Lihat log di console Flutter untuk error message
- Pastikan port 8000 tidak digunakan aplikasi lain

### Permission Error (Linux/macOS)
```bash
chmod +x build/desktop/dist/peripage-backend
```

### USB tidak terdeteksi (Linux)
```bash
sudo usermod -aG plugdev $USER
# Logout dan login kembali
```

### BLE tidak berfungsi (Windows)
- Pastikan Bluetooth adapter aktif
- Install driver Bluetooth terbaru
- Run aplikasi sebagai Administrator jika perlu

## Development Mode

Untuk development tanpa build PyInstaller:

```bash
# Terminal 1: Jalankan Python backend
cd /workspace
python -m uvicorn core_python.server:app --reload

# Terminal 2: Jalankan Flutter
cd flutter_app/peripage
flutter run -d windows  # atau macos/linux
```

## Multi-ABI Support

Build untuk berbagai arsitektur:

### Windows (x64, x86, ARM64)
```bash
pyinstaller --target-arch=64bit build/desktop/pyinstaller.spec
```

### macOS (Intel, Apple Silicon)
```bash
# Intel
pyinstaller --target-arch=x86_64 build/desktop/pyinstaller.spec

# Apple Silicon
pyinstaller --target-arch=arm64 build/desktop/pyinstaller.spec

# Universal Binary (keduanya)
lipo -create -output peripage-backend-universal \
  dist/intel/peripage-backend \
  dist/arm/peripage-backend
```

### Linux (x64, ARM64)
Build di mesin dengan arsitektur target atau gunakan cross-compilation.

## File Structure

```
/workspace
├── core_python/              # Python source code
│   ├── desktop_main.py       # Entry point untuk desktop
│   ├── server.py             # FastAPI server
│   └── requirements-desktop.txt
├── build/desktop/            # Build configuration
│   ├── pyinstaller.spec      # PyInstaller config
│   ├── build.sh              # Build script (Unix)
│   └── build.bat             # Build script (Windows)
└── flutter_app/peripage/     # Flutter application
    ├── lib/
    │   ├── main.dart         # Auto-start backend
    │   └── services/
    │       ├── desktop_backend_service.dart  # Backend manager
    │       └── python_service.dart           # Unified API
    └── pubspec.yaml
```

## Next Steps

- [ ] Code signing untuk macOS
- [ ] MSI installer untuk Windows
- [ ] AppImage/DEB/RPM untuk Linux
- [ ] Auto-update mechanism
- [ ] Crash reporting
