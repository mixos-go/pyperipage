import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import '../../data/models/printer_models.dart';

/// Service untuk komunikasi dengan Python backend.
///
/// PENTING (fix arsitektur Juli 2026): sebelumnya class ini SELALU pakai HTTP
/// ke server lokal, gak peduli platform -- itu sebabnya APK Android tetap
/// minta "server berjalan" walau Chaquopy sudah terpasang. Sekarang ada
/// percabangan platform:
/// - Desktop (Windows/Linux/macOS): tetap HTTP ke Python sidecar (unchanged).
/// - Android/iOS: manggil `python_service.py` LANGSUNG lewat MethodChannel
///   ke Chaquopy (Android) -- tanpa proses server terpisah sama sekali.
///
/// Semua method signature publik di class ini TIDAK BERUBAH dari versi lama,
/// supaya PrinterProvider dan seluruh screen yang sudah pakai ApiService
/// tidak perlu disentuh sama sekali.
class ApiService {
  final String baseUrl;

  static const MethodChannel _channel = MethodChannel('com.pyperipage/printer');

  ApiService({this.baseUrl = ApiConstants.baseUrl});

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// Panggil method channel Chaquopy, decode JSON string hasil dari Kotlin,
  /// dan lempar Exception kalau status == "error" (biar konsisten dengan
  /// pola http.Exception yang sudah dipakai di seluruh method HTTP di bawah).
  Future<Map<String, dynamic>> _invokeNative(String method, [Map<String, dynamic>? args]) async {
    try {
      final jsonStr = await _channel.invokeMethod<String>(method, args);
      final data = json.decode(jsonStr ?? '{}') as Map<String, dynamic>;
      if (data['status'] == 'error') {
        throw Exception(data['message'] ?? 'Terjadi kesalahan pada printer.');
      }
      return data;
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Gagal berkomunikasi dengan modul printer native.');
    }
  }

  /// Health check -- di mobile, Chaquopy selalu "tersedia" begitu APK jalan
  /// (gak ada proses server terpisah yang perlu dicek), jadi langsung true.
  Future<Map<String, dynamic>> healthCheck() async {
    if (_isMobile) {
      return {'status': 'ok'};
    }
    try {
      final response = await http.get(Uri.parse('$baseUrl/'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to connect to server: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Server tidak tersedia. Pastikan Python backend berjalan.');
    }
  }

  Future<PrinterStatus> getPrinterStatus() async {
    if (_isMobile) {
      final data = await _invokeNative('getPrinterStatus');
      return PrinterStatus.fromJson(data);
    }
    final response = await http.get(Uri.parse('$baseUrl/api/status'));
    if (response.statusCode == 200) {
      return PrinterStatus.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to get printer status');
    }
  }

  Future<bool> connectUsb() async {
    if (_isMobile) {
      await _invokeNative('connectUsb');
      return true;
    }
    final response = await http.post(
      Uri.parse('$baseUrl/api/connect/usb'),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception('Failed to connect via USB');
    }
  }

  Future<bool> connectBle({String? deviceAddress}) async {
    if (_isMobile) {
      await _invokeNative('connectBle', {'deviceAddress': deviceAddress});
      return true;
    }
    final response = await http.post(
      Uri.parse('$baseUrl/api/connect/ble'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'device_address': deviceAddress}),
    );
    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception('Failed to connect via BLE');
    }
  }

  Future<List<BleDevice>> discoverBleDevices({double timeout = 5.0}) async {
    if (_isMobile) {
      final data = await _invokeNative('discoverBleDevices', {'timeout': timeout});
      final devicesList = data['devices'] as List;
      return devicesList.map((d) => BleDevice.fromJson(d)).toList();
    }
    final response = await http.get(
      Uri.parse('$baseUrl/api/ble/discover?timeout=$timeout'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final devicesList = data['devices'] as List;
      return devicesList.map((d) => BleDevice.fromJson(d)).toList();
    } else {
      throw Exception('Failed to discover BLE devices');
    }
  }

  Future<bool> setPaperWidth(int widthMm) async {
    if (_isMobile) {
      await _invokeNative('setPaperWidth', {'widthMm': widthMm});
      return true;
    }
    final response = await http.post(
      Uri.parse('$baseUrl/api/paper-width'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'width_mm': widthMm}),
    );
    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception('Failed to set paper width');
    }
  }

  Future<PrinterConfig> getPaperWidthConfig() async {
    if (_isMobile) {
      final data = await _invokeNative('getConfig');
      return PrinterConfig(
        supportedPaperWidths: List<int>.from(data['supported_paper_widths'] ?? [58, 77]),
        defaultPaperWidth: data['default_paper_width'] ?? 58,
        currentPaperWidth: data['current_paper_width'] ?? 58,
        pdfSupport: true,
        transportTypes: ['usb', 'ble'],
      );
    }
    final response = await http.get(Uri.parse('$baseUrl/api/paper-width'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return PrinterConfig(
        supportedPaperWidths: List<int>.from(data['supported_widths'] ?? [58, 77]),
        defaultPaperWidth: 58,
        currentPaperWidth: data['paper_width_mm'] ?? 58,
        pdfSupport: true,
        transportTypes: ['usb', 'ble'],
      );
    } else {
      throw Exception('Failed to get paper width config');
    }
  }

  Future<PrinterConfig> getConfig() async {
    if (_isMobile) {
      final data = await _invokeNative('getConfig');
      return PrinterConfig.fromJson(data);
    }
    final response = await http.get(Uri.parse('$baseUrl/api/config'));
    if (response.statusCode == 200) {
      return PrinterConfig.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to get config');
    }
  }

  Future<String> previewImage(File imageFile, {int? paperWidthMm}) async {
    if (_isMobile) {
      final data = await _invokeNative('previewImage', {
        'imagePath': imageFile.path,
        'paperWidthMm': paperWidthMm,
      });
      return data['image_base64'] as String;
    }
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/preview/image'),
    );

    request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));

    if (paperWidthMm != null) {
      request.fields['paper_width_mm'] = paperWidthMm.toString();
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return base64Encode(response.bodyBytes);
    } else {
      throw Exception('Failed to preview image');
    }
  }

  Future<bool> printImage(File imageFile, {int? paperWidthMm}) async {
    if (_isMobile) {
      await _invokeNative('printImage', {
        'imagePath': imageFile.path,
        'paperWidthMm': paperWidthMm,
      });
      return true;
    }
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/print/image'),
    );

    request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));

    if (paperWidthMm != null) {
      request.fields['paper_width_mm'] = paperWidthMm.toString();
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception('Failed to print image');
    }
  }

  Future<bool> printPdf(File pdfFile, List<int> pages, {int? paperWidthMm}) async {
    if (_isMobile) {
      await _invokeNative('printPdf', {
        'pdfPath': pdfFile.path,
        'pages': pages,
        'paperWidthMm': paperWidthMm,
      });
      return true;
    }
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/print/pdf'),
    );

    request.files.add(await http.MultipartFile.fromPath('pdf_file', pdfFile.path));
    request.fields['pages'] = pages.join(',');

    if (paperWidthMm != null) {
      request.fields['paper_width_mm'] = paperWidthMm.toString();
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception('Failed to print PDF');
    }
  }

  Future<bool> printBatch(List<File> files, {int? paperWidthMm}) async {
    if (_isMobile) {
      await _invokeNative('printBatch', {
        'filePaths': files.map((f) => f.path).toList(),
        'paperWidthMm': paperWidthMm,
      });
      return true;
    }
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/print/batch'),
    );

    for (var file in files) {
      request.files.add(await http.MultipartFile.fromPath('files', file.path));
    }

    if (paperWidthMm != null) {
      request.fields['paper_width_mm'] = paperWidthMm.toString();
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception('Failed to print batch');
    }
  }
}
