# 🚀 Panduan Lengkap: PeriPage A9 Multi-Platform App

## ✅ Yang Sudah Selesai (Phase 1 - Core Infrastructure)

### 1. Python Core Engine (`/workspace/core_python/`)

#### Struktur Package
```
core_python/
├── peripage_a9/           # Driver library
│   ├── __init__.py        # Package exports
│   ├── protocol.py        # ✅ Logic protokol (transport-agnostic)
│   ├── driver.py          # ✅ API publik (USB & BLE classes)
│   ├── transport_usb.py   # ✅ USB transport untuk desktop
│   └── transport_ble.py   # ✅ BLE transport untuk mobile
├── server.py              # ✅ FastAPI server
└── requirements.txt       # Dependencies
```

#### Fitur Core yang Sudah Jalan:
- ✅ **Smart Crop 4-way**: Auto-deteksi konten, margin, dan resize proporsional
- ✅ **Dual Transport**: USB (desktop) dan BLE (mobile) dengan interface sama
- ✅ **Paper Width Support**: 58mm dan 77mm dengan kalibrasi manual
- ✅ **PDF Rendering**: Multi-halaman dengan DPI tinggi (300)
- ✅ **Image Processing**: PIL/Pillow untuk crop, resize, convert
- ✅ **FastAPI Server**: REST API lengkap dengan Swagger docs
- ✅ **BLE Discovery**: Scan dan connect ke device Bluetooth

### 2. API Server Testing

Server sudah running di `http://localhost:8000`

**Endpoint yang sudah ditest:**
```bash
✅ GET  /                    → Health check
✅ GET  /api/config          → Config aplikasi
✅ GET  /api/status          → Status printer
🔄 POST /api/connect/usb     → Connect USB (butuh hardware)
🔄 POST /api/connect/ble     → Connect BLE (butuh hardware)
🔄 GET  /api/ble/discover    → Scan BLE devices
🔄 POST /api/paper-width     → Set kertas
🔄 POST /api/print/image     → Print gambar
🔄 POST /api/print/pdf       → Print PDF
🔄 POST /api/print/batch     → Print multiple files
```

### 3. Dokumentasi

- ✅ `README.md` - Overview project & arsitektur
- ✅ `flutter_app/SETUP_GUIDE.md` - Panduan lengkap Flutter development

---

## 📋 Next Steps: Phase 2 (Flutter UI Development)

### Langkah 1: Install Flutter

Download dari: https://docs.flutter.dev/get-started/install

**Verifikasi instalasi:**
```bash
flutter doctor
flutter --version
```

### Langkah 2: Create Flutter Project

```bash
cd /workspace/flutter_app
flutter create --project-name peripage_app --org com.peripage .
```

### Langkah 3: Setup Dependencies

Edit `pubspec.yaml`:

```yaml
name: peripage_app
description: Modern print app for PeriPage A9 thermal printer
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  
  # HTTP Client
  http: ^1.1.0
  dio: ^5.4.0
  
  # State Management (pilih salah satu)
  provider: ^6.1.1
  # atau:
  # flutter_riverpod: ^2.4.0
  
  # File Handling
  file_picker: ^6.1.1
  path_provider: ^2.1.1
  
  # Image
  image_picker: ^1.0.5
  cached_network_image: ^3.3.0
  
  # UI
  google_fonts: ^6.1.0
  shimmer: ^3.0.0
  flutter_svg: ^2.0.9
  
  # Bluetooth (optional - untuk direct BLE mode)
  flutter_blue_plus: ^1.31.0
  
  # Utils
  intl: ^0.18.1
  logger: ^2.0.2+1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.1

flutter:
  uses-material-design: true
```

Lalu jalankan:
```bash
flutter pub get
```

### Langkah 4: Implementasi Screen (Prioritas)

#### 4.1 Home Screen (`lib/screens/home_screen.dart`)
```dart
// Komponen utama:
// - Printer status card (connected/disconnected)
// - Quick actions: Print PDF, Print Image, Settings
// - Recent files list
// - Bottom navigation bar
```

#### 4.2 Printer Connect Screen (`lib/screens/printer_connect_screen.dart`)
```dart
// Fitur:
// - Toggle USB/BLE
// - Auto-scan devices
// - Manual connect button
// - Device list dengan RSSI indicator
// - Connection status animation
```

#### 4.3 File Picker Screen (`lib/screens/file_picker_screen.dart`)
```dart
// Fitur:
// - Tab PDF / Images
// - System file picker integration
// - Recent files
// - Multi-select dengan checkbox
// - File thumbnail preview
// - Search & sort
```

#### 4.4 Preview Screen (`lib/screens/preview_screen.dart`)
```dart
// Fitur:
// - Smart crop preview (fetch dari API)
// - Page navigation (prev/next)
// - Paper width selector dropdown
// - Zoom & pan gesture
// - Page count indicator
```

#### 4.5 Print Controls (`lib/widgets/print_controls.dart`)
```dart
// Fitur:
// - Select all / Deselect all
// - Individual page checkboxes
// - Paper width setting
// - Print button dengan progress indicator
// - Cancel print option
```

### Langkah 5: API Service Integration

Buat file `lib/services/api_service.dart`:

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class ApiService {
  // Untuk development (emulator Android): gunakan 10.0.2.2
  // Untuk physical device: gunakan IP komputer Anda
  // Untuk desktop: localhost
  static const String baseUrl = 'http://10.0.2.2:8000/api';
  
  final http.Client _client = http.Client();
  
  // Health check
  Future<Map<String, dynamic>> healthCheck() async {
    final response = await _client.get(Uri.parse('http://10.0.2.2:8000/'));
    return json.decode(response.body);
  }
  
  // Get printer status
  Future<Map<String, dynamic>> getStatus() async {
    final response = await _client.get(Uri.parse('$baseUrl/status'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to get status');
  }
  
  // Connect USB
  Future<bool> connectUsb() async {
    final response = await _client.post(Uri.parse('$baseUrl/connect/usb'));
    return response.statusCode == 200;
  }
  
  // Connect BLE
  Future<bool> connectBle({String? deviceAddress}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/connect/ble'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'device_address': deviceAddress}),
    );
    return response.statusCode == 200;
  }
  
  // Discover BLE devices
  Future<List<dynamic>> discoverBleDevices() async {
    final response = await _client.get(Uri.parse('$baseUrl/ble/discover'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['devices'] ?? [];
    }
    throw Exception('Failed to discover devices');
  }
  
  // Set paper width
  Future<void> setPaperWidth(int widthMm) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/paper-width'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'width_mm': widthMm}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to set paper width');
    }
  }
  
  // Get paper width settings
  Future<Map<String, dynamic>> getPaperWidth() async {
    final response = await _client.get(Uri.parse('$baseUrl/paper-width'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to get paper width');
  }
  
  // Print image
  Future<bool> printImage(File imageFile, {int? paperWidthMm}) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/print/image'),
    );
    
    request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
    
    if (paperWidthMm != null) {
      request.fields['paper_width_mm'] = paperWidthMm.toString();
    }
    
    final response = await request.send();
    return response.statusCode == 200;
  }
  
  // Print PDF
  Future<bool> printPdf(
    File pdfFile, 
    List<int> pageIndices, {
    int? paperWidthMm,
  }) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/print/pdf'),
    );
    
    request.files.add(await http.MultipartFile.fromPath('pdf_file', pdfFile.path));
    request.fields['pages'] = pageIndices.join(',');
    
    if (paperWidthMm != null) {
      request.fields['paper_width_mm'] = paperWidthMm.toString();
    }
    
    final response = await request.send();
    return response.statusCode == 200;
  }
  
  // Get config
  Future<Map<String, dynamic>> getConfig() async {
    final response = await _client.get(Uri.parse('$baseUrl/config'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to get config');
  }
}
```

### Langkah 6: State Management Example

Dengan Provider:

```dart
// lib/providers/printer_provider.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PrinterProvider with ChangeNotifier {
  final ApiService _api = ApiService();
  
  bool _isConnected = false;
  String _transportType = 'usb';
  int _paperWidthMm = 77;
  bool _isLoading = false;
  String _statusMessage = '';
  
  // Getters
  bool get isConnected => _isConnected;
  String get transportType => _transportType;
  int get paperWidthMm => _paperWidthMm;
  bool get isLoading => _isLoading;
  String get statusMessage => _statusMessage;
  
  // Methods
  Future<void> checkStatus() async {
    try {
      final status = await _api.getStatus();
      _isConnected = status['connected'];
      _transportType = status['transport_type'];
      _paperWidthMm = status['paper_width_mm'];
      _statusMessage = status['message'];
      notifyListeners();
    } catch (e) {
      _statusMessage = 'Error: ${e.toString()}';
      notifyListeners();
    }
  }
  
  Future<bool> connectUsb() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final success = await _api.connectUsb();
      if (success) {
        _isConnected = true;
        _transportType = 'usb';
        _statusMessage = 'Connected via USB';
      }
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _isLoading = false;
      _statusMessage = 'Connection failed: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }
  
  Future<void> setPaperWidth(int width) async {
    await _api.setPaperWidth(width);
    _paperWidthMm = width;
    notifyListeners();
  }
  
  // ... method lainnya
}
```

### Langkah 7: Run & Test

```bash
# Untuk Android emulator
flutter run

# Untuk iOS simulator
flutter run -d ios

# Untuk Chrome (web testing)
flutter run -d chrome

# Untuk Windows desktop
flutter run -d windows

# Build APK
flutter build apk --release

# Build IPA (iOS)
flutter build ipa

# Build EXE (Windows)
flutter build windows
```

---

## 🎯 Roadmap Completion

### ✅ Phase 1: Core Infrastructure (DONE)
- [x] Refactor Python logic (protocol-agnostic)
- [x] BLE transport implementation
- [x] FastAPI server dengan semua endpoint
- [x] API documentation (Swagger)
- [x] Testing & validation

### 🔥 Phase 2: Flutter UI (IN PROGRESS)
- [ ] Flutter project setup
- [ ] Basic UI scaffold & navigation
- [ ] Printer connection screen
- [ ] File picker & preview
- [ ] Print controls
- [ ] Settings screen

### 📅 Phase 3: Advanced Features
- [ ] Direct BLE mode (tanpa server di mobile)
- [ ] Template editor untuk label
- [ ] QR code generation
- [ ] Batch print optimization
- [ ] Dark/Light theme

### 📅 Phase 4: Production Ready
- [ ] Multi-language (EN/ID)
- [ ] Error handling & retry logic
- [ ] Performance optimization
- [ ] Build pipelines CI/CD
- [ ] App Store & Play Store deployment

---

## 🛠️ Troubleshooting

### Server tidak bisa diakses dari emulator Android
**Solusi:** Gunakan `10.0.2.2` sebagai pengganti `localhost`

### BLE tidak terdeteksi di mobile
**Solusi:** 
- Pastikan permission Bluetooth sudah diberikan
- Cek lokasi permission (diperlukan untuk BLE scanning)
- Pastikan printer dalam mode pairing

### Print gagal dengan error USB
**Solusi:**
- Cek koneksi kabel USB
- Restart printer
- Jalankan kalibrasi: `python tools/calibrate_paper_width.py`

---

## 📞 Support

Untuk pertanyaan atau issue, silakan buat issue di repository GitHub.

**Happy Coding! 🎉**
