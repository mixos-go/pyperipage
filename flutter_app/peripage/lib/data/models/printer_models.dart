/// Model data untuk printer status
class PrinterStatus {
  final bool connected;
  final String transportType; // 'usb' atau 'ble'
  final int paperWidthMm;
  final String message;

  PrinterStatus({
    required this.connected,
    required this.transportType,
    required this.paperWidthMm,
    required this.message,
  });

  factory PrinterStatus.fromJson(Map<String, dynamic> json) {
    return PrinterStatus(
      connected: json['connected'] ?? false,
      transportType: json['transport_type'] ?? 'usb',
      paperWidthMm: json['paper_width_mm'] ?? 58,
      message: json['message'] ?? '',
    );
  }

  PrinterStatus copyWith({
    bool? connected,
    String? transportType,
    int? paperWidthMm,
    String? message,
  }) {
    return PrinterStatus(
      connected: connected ?? this.connected,
      transportType: transportType ?? this.transportType,
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      message: message ?? this.message,
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
