/// Constants untuk aplikasi
class ApiConstants {
  // URL backend Python server
  // Untuk Android emulator: gunakan 10.0.2.2 instead of localhost
  // Untuk physical device: gunakan IP address komputer Anda
  static const String baseUrl = 'http://localhost:8000';
  
  // Timeout untuk request HTTP
  static const Duration timeout = Duration(seconds: 30);
}

/// Constants untuk UI
class UiConstants {
  // Colors (akan digunakan di theme)
  static const int primaryColorHex = 0xFF1976D2;
  static const int secondaryColorHex = 0xFF424242;
  
  // Spacing
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  
  // Border radius
  static const double borderRadiusSm = 4.0;
  static const double borderRadiusMd = 8.0;
  static const double borderRadiusLg = 16.0;
}

/// Constants untuk printer
class PrinterConstants {
  static const List<int> supportedPaperWidths = [58, 77];
  static const int defaultPaperWidth = 58;
  
  // Nama device BLE untuk Peripage A9
  static const String bleDeviceNamePrefix = 'PeriPage';
}
