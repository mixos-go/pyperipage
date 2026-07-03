# Flutter App Scaffold untuk PeriPage A9

Karena Flutter belum terinstall di environment ini, berikut adalah struktur lengkap yang siap Anda gunakan:

## 📁 Struktur Folder Flutter

```
flutter_app/
├── android/                    # Android-specific code
├── ios/                        # iOS-specific code
├── lib/
│   ├── main.dart              # Entry point
│   ├── app.dart               # App configuration & theme
│   ├── config/
│   │   └── api_config.dart    # API endpoint configuration
│   ├── models/
│   │   ├── printer_status.dart
│   │   ├── print_job.dart
│   │   └── device_info.dart
│   ├── services/
│   │   ├── api_service.dart   # HTTP client ke Python server
│   │   ├── printer_service.dart
│   │   └── ble_service.dart   # Direct BLE (optional)
│   ├── screens/
│   │   ├── home_screen.dart
│   │   ├── printer_connect_screen.dart
│   │   ├── file_picker_screen.dart
│   │   ├── preview_screen.dart
│   │   └── settings_screen.dart
│   ├── widgets/
│   │   ├── printer_status_card.dart
│   │   ├── page_selector.dart
│   │   ├── preview_widget.dart
│   │   └── custom_buttons.dart
│   └── utils/
│       ├── constants.dart
│       └── helpers.dart
├── test/                       # Unit tests
├── pubspec.yaml               # Dependencies
└── README.md
```

## 🚀 Langkah Setup

### 1. Install Flutter

Download dari: https://docs.flutter.dev/get-started/install

### 2. Create Project

```bash
cd /workspace/flutter_app
flutter create --project-name peripage_app --org com.peripage .
```

### 3. Update pubspec.yaml

Tambahkan dependencies berikut:

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # HTTP & API
  http: ^1.1.0
  dio: ^5.4.0
  
  # State Management
  provider: ^6.1.1
  # atau get_it + riverpod jika prefer
  
  # File Handling
  file_picker: ^6.1.1
  path_provider: ^2.1.1
  
  # Image Processing
  image_picker: ^1.0.5
  cached_network_image: ^3.3.0
  
  # UI Components
  google_fonts: ^6.1.0
  flutter_svg: ^2.0.9
  shimmer: ^3.0.0
  
  # Bluetooth (untuk direct BLE mode - optional)
  flutter_blue_plus: ^1.31.0
  
  # Utilities
  intl: ^0.18.1
  logger: ^2.0.2+1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.1
```

### 4. Run App

```bash
flutter run
```

## 🎨 Design System

### Color Palette

```dart
// Modern, clean, professional
primaryColor: Color(0xFF2563EB)      // Blue 600
secondaryColor: Color(0xFF10B981)    // Emerald 500
errorColor: Color(0xFFEF4444)        // Red 500
backgroundColor: Color(0xFFF8FAFC)   // Slate 50
surfaceColor: Colors.white
```

### Typography

```dart
// Gunakan Google Fonts Inter atau Roboto
fontFamily: 'Inter'
```

### Components Priority

1. **Printer Connection Screen**
   - Auto-detect USB/BLE
   - Manual connect button
   - Device list for BLE
   - Status indicator (connected/disconnected)

2. **File Picker Screen**
   - Support PDF & Images
   - Recent files
   - Multi-select
   - File preview thumbnail

3. **Preview Screen**
   - Smart crop preview
   - Page navigation
   - Paper width selector
   - Zoom & pan

4. **Print Controls**
   - Page selection (checkboxes)
   - Print all / Select all
   - Paper width dropdown
   - Print button dengan progress

5. **Settings Screen**
   - Default paper width
   - Auto-connect preference
   - Dark/Light mode
   - About & version

## 🔌 API Integration

### Service Example (api_service.dart)

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiService {
  final String baseUrl = 'http://localhost:8000/api';
  
  Future<Map<String, dynamic>> getStatus() async {
    final response = await http.get(Uri.parse('$baseUrl/status'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to get status');
  }
  
  Future<bool> connectUsb() async {
    final response = await http.post(Uri.parse('$baseUrl/connect/usb'));
    return response.statusCode == 200;
  }
  
  Future<void> setPaperWidth(int widthMm) async {
    final response = await http.post(
      Uri.parse('$baseUrl/paper-width'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'width_mm': widthMm}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to set paper width');
    }
  }
  
  // ... method lainnya sesuai endpoint
}
```

## 📱 Platform-Specific Notes

### Android
- Add permissions in `AndroidManifest.xml`:
  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.BLUETOOTH"/>
  <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
  ```

### iOS
- Add permissions in `Info.plist`:
  ```xml
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Aplikasi perlu akses Bluetooth untuk koneksi ke printer</string>
  <key>NSBluetoothPeripheralUsageDescription</key>
  <string>Aplikasi perlu akses Bluetooth untuk koneksi ke printer</string>
  ```

### Desktop (Windows/macOS/Linux)
- Pastikan loopback network diizinkan
- Untuk production, Python server bisa di-embed sebagai background service

## 🔄 Development Workflow

1. **Phase 1**: Basic UI + API connection
2. **Phase 2**: File picker & preview
3. **Phase 3**: Print functionality
4. **Phase 4**: Polish & optimization
5. **Phase 5**: Direct BLE mode (optional)

## 🎯 Next Steps

Setelah Flutter terinstall:
1. Jalankan `flutter create` command di atas
2. Copy struktur folder yang disarankan
3. Implementasi screen satu per satu
4. Test dengan Python server yang sudah running

Server Python sudah siap di `http://localhost:8000` dengan dokumentasi lengkap di `http://localhost:8000/docs`
