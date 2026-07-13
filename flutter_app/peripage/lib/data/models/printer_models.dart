/// Model data untuk printer status
class PrinterStatus {
  final bool connected;
  final String transportType; // 'usb' atau 'ble'
  final int paperWidthMm;
  final String message;
  final String? deviceAddress; // MAC address BLE, null untuk USB/tidak konek
  final String? deviceName;
  /// Protokol yang akan dipakai otomatis saat print ("raw" atau
  /// "compressed") -- hasil deteksi berdasarkan nama device, lihat
  /// PERIPAGE_PROTOCOL.md (reverse-engineering, Juli 2026).
  final String? detectedProtocol;

  PrinterStatus({
    required this.connected,
    required this.transportType,
    required this.paperWidthMm,
    required this.message,
    this.deviceAddress,
    this.deviceName,
    this.detectedProtocol,
  });

  factory PrinterStatus.fromJson(Map<String, dynamic> json) {
    return PrinterStatus(
      connected: json['connected'] ?? false,
      transportType: json['transport_type'] ?? 'usb',
      paperWidthMm: json['paper_width_mm'] ?? 58,
      message: json['message'] ?? '',
      deviceAddress: json['device_address'] as String?,
      deviceName: json['device_name'] as String?,
      detectedProtocol: json['detected_protocol'] as String?,
    );
  }

  PrinterStatus copyWith({
    bool? connected,
    String? transportType,
    int? paperWidthMm,
    String? message,
    String? deviceAddress,
    String? deviceName,
    String? detectedProtocol,
  }) {
    return PrinterStatus(
      connected: connected ?? this.connected,
      transportType: transportType ?? this.transportType,
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      message: message ?? this.message,
      deviceAddress: deviceAddress ?? this.deviceAddress,
      deviceName: deviceName ?? this.deviceName,
      detectedProtocol: detectedProtocol ?? this.detectedProtocol,
    );
  }
}

/// Model untuk konfigurasi printer
class PrinterConfig {
  final List<int> supportedPaperWidths;
  final int defaultPaperWidth;
  final int currentPaperWidth;
  final bool pdfSupport;
  final List<String> transportTypes;

  PrinterConfig({
    required this.supportedPaperWidths,
    required this.defaultPaperWidth,
    required this.currentPaperWidth,
    required this.pdfSupport,
    required this.transportTypes,
  });

  factory PrinterConfig.fromJson(Map<String, dynamic> json) {
    return PrinterConfig(
      supportedPaperWidths: List<int>.from(json['supported_paper_widths'] ?? [58, 77]),
      defaultPaperWidth: json['default_paper_width'] ?? 58,
      currentPaperWidth: json['current_paper_width'] ?? 58,
      pdfSupport: json['pdf_support'] ?? false,
      transportTypes: List<String>.from(json['transport_types'] ?? ['usb', 'ble']),
    );
  }
}

/// Model untuk device BLE
class BleDevice {
  final String address;
  final String name;
  final int? rssi;

  BleDevice({
    required this.address,
    required this.name,
    this.rssi,
  });

  factory BleDevice.fromJson(Map<String, dynamic> json) {
    return BleDevice(
      address: json['address'] ?? '',
      name: json['name'] ?? 'Unknown',
      rssi: json['rssi'],
    );
  }
}

/// Rect crop manual (dari Manual Crop Editor), koordinat ternormalisasi
/// 0.0-1.0 relatif ke gambar ASLI (bukan pixel) -- supaya konsisten dipakai
/// baik untuk thumbnail preview maupun gambar resolusi penuh saat print.
class CropRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const CropRect({
    this.left = 0.0,
    this.top = 0.0,
    this.right = 1.0,
    this.bottom = 1.0,
  });

  Map<String, double> toJson() => {'left': left, 'top': top, 'right': right, 'bottom': bottom};

  /// Crop rect default (seluruh gambar, tidak ada crop).
  static const CropRect full = CropRect();

  bool get isFullImage => left == 0.0 && top == 0.0 && right == 1.0 && bottom == 1.0;
}

/// Model untuk print job
class PrintJob {
  final String filePath;
  final String fileType; // 'image' atau 'pdf'
  final List<int>? pages; // Untuk PDF, halaman mana yang akan dicetak
  final int? paperWidthMm;

  PrintJob({
    required this.filePath,
    required this.fileType,
    this.pages,
    this.paperWidthMm,
  });
}
