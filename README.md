# 🖨️ PeriPage A9 - Modern Multi-Platform App

<p align="center">
  <img src="readme_icon_original.png" alt="PeriPage A9 Icon" width="160">
</p>

Aplikasi print modern untuk printer thermal **PeriPage A9** dengan dukungan multi-platform:
- **Desktop**: Windows, macOS, Linux (via USB)
- **Mobile**: Android, iOS (via Bluetooth BLE)

## 🏗️ Arsitektur

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter UI/UX Layer                      │
│  (Modern, Responsive, Adaptive - Single Codebase)           │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP REST API
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Python Core (FastAPI Server)                   │
│  • Logic Protokol Printer (ESC/POS-like)                    │
│  • Smart Crop & Image Processing                            │
│  • Transport Layer: USB (desktop) / BLE (mobile)            │
│  • PDF & Image Rendering                                    │
└─────────────────────────────────────────────────────────────┘
```

## 📁 Struktur Project

```
/workspace
├── core_python/                 # Python Core Engine
│   ├── peripage_a9/            # Driver library
│   │   ├── __init__.py
│   │   ├── protocol.py         # ✅ Logic protokol (transport-agnostic)
│   │   ├── driver.py           # ✅ API publik (USB & BLE)
│   │   ├── transport_usb.py    # ✅ USB transport (desktop)
│   │   └── transport_ble.py    # 🔥 BLE transport (mobile)
│   └── server.py               # 🔥 FastAPI server
│
├── flutter_app/                # 🔥 Flutter UI (akan dibuat)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── services/
│   │   ├── screens/
│   │   └── widgets/
│   └── pubspec.yaml
│
└── tools/                      # Utility tools
    └── calibrate_paper_width.py
```

## 🚀 Fitur Utama

### ✅ Sudah Tersedia (Python Core)
- [x] Smart Crop 4-way (auto-deteksi konten & margin)
- [x] Support 2 lebar kertas: 58mm & 77mm
- [x] Print PDF multi-halaman
- [x] Print gambar (PNG, JPG, dll)
- [x] USB transport (desktop)
- [x] BLE transport (mobile) - *siap integrasi*
- [x] Kalibrasi manual lebar cetak
- [x] Preview WYSIWYG (What You See Is What You Print)
- [x] FastAPI server untuk bridge ke Flutter

### 🔥 Dalam Pengembangan
- [ ] Flutter UI modern
- [ ] BLE device discovery & pairing di mobile
- [ ] Batch print (multiple files)
- [ ] QR code generation & print
- [ ] Template label (Shopee, TikTok, dll)
- [ ] Dark mode & adaptive themes
- [ ] Offline mode (direct BLE tanpa server)

## 🛠️ Instalasi

### 1. Install Dependencies Python

```bash
cd /workspace/core_python
pip install -r requirements.txt
```

**Dependencies utama:**
- `pyusb` - USB communication
- `bleak` - BLE communication
- `pillow` - Image processing
- `pdf2image` - PDF rendering
- `fastapi` + `uvicorn` - API server

### 2. Jalankan Server

```bash
python server.py
```

Server akan berjalan di `http://localhost:8000`

**API Documentation:** `http://localhost:8000/docs` (Swagger UI)

### 3. Test API

```bash
# Cek status
curl http://localhost:8000/api/status

# Get config
curl http://localhost:8000/api/config

# Connect USB
curl -X POST http://localhost:8000/api/connect/usb
```

## 📱 Flutter App Development

*(Dalam pengembangan - struktur akan dibuat)*

```bash
cd flutter_app
flutter create .
flutter pub get
flutter run
```

## 🔧 Tools & Utilities

### Kalibrasi Lebar Cetak

Untuk mendapatkan hasil cetak yang presisi, gunakan tool kalibrasi:

```bash
python tools/calibrate_paper_width.py
```

Tool ini akan mencetak pola penggaris untuk menentukan lebar cetak fisik yang akurat dari printer Anda.

## 🎯 Use Cases

### 1. Print Resi E-commerce (Shopee, TikTok)
- Upload PDF resi
- Auto smart crop
- Print dengan lebar 77mm

### 2. Print Label Produk
- Upload gambar label
- QR code auto-generated
- Print batch multiple labels

### 3. Print Catatan/Dokumen
- Convert PDF ke thermal-friendly format
- Preview sebelum print
- Pilih halaman spesifik

## 📝 API Endpoints

| Method | Endpoint | Deskripsi |
|--------|----------|-----------|
| GET | `/api/status` | Cek status koneksi printer |
| POST | `/api/connect/usb` | Koneksi via USB |
| POST | `/api/connect/ble` | Koneksi via BLE |
| GET | `/api/ble/discover` | Scan device BLE |
| GET | `/api/paper-width` | Get setting kertas |
| POST | `/api/paper-width` | Set lebar kertas |
| POST | `/api/preview/image` | Preview smart crop gambar |
| POST | `/api/print/image` | Print gambar |
| POST | `/api/print/pdf` | Print PDF |
| POST | `/api/print/batch` | Print multiple files |
| GET | `/api/config` | Get konfigurasi |

## 🚧 Roadmap

### Phase 1: Core Infrastructure ✅
- [x] Refactor logic Python (protocol-agnostic)
- [x] BLE transport implementation
- [x] FastAPI server
- [x] API documentation

### Phase 2: Flutter UI (Current)
- [ ] Basic UI scaffold
- [ ] Printer connection screen
- [ ] File picker & preview
- [ ] Print controls

### Phase 3: Advanced Features
- [ ] BLE direct mode (tanpa server di mobile)
- [ ] Template editor
- [ ] Cloud sync settings
- [ ] Plugin system

### Phase 4: Production Ready
- [ ] Multi-language support
- [ ] Error handling & logging
- [ ] Performance optimization
- [ ] Build pipelines (APK, EXE, DMG, etc.)

## 🤝 Kontribusi

Project ini open untuk kontribusi! Silakan:
1. Fork repository
2. Buat feature branch
3. Commit perubahan
4. Push dan buat Pull Request

## 📄 License

MIT License - lihat file LICENSE untuk detail.

---

**Dibuat dengan ❤️ untuk komunitas developer Indonesia**
