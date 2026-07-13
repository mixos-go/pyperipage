import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../utils/app_logger.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import '../utils/constants.dart';
import '../../data/models/printer_models.dart';

/// Exception khusus buat panggilan native (MethodChannel) yang membawa
/// `details` (stack trace lengkap dari Kotlin/Chaquopy) TERPISAH dari
/// `message` (ringkas, buat SnackBar) -- supaya user bisa lihat traceback
/// PERSIS di dalam app (lewat dialog "Lihat Detail") tanpa perlu adb logcat
/// sama sekali.
class NativeCallException implements Exception {
  final String message;
  final String? details;

  NativeCallException(this.message, {this.details});

  @override
  String toString() => message;
}

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
        appLog('ApiService', '❌ Error dari python_service (method "$method"): ${data['message']}');
        if (data['details'] != null) {
          appLog('ApiService', '❌ Traceback Python:\n${data['details']}');
        }
        throw NativeCallException(
          data['message'] ?? 'Terjadi kesalahan pada printer.',
          details: data['details'] as String?,
        );
      }
      return data;
    } on PlatformException catch (e) {
      // `e.details` berisi stackTraceToString() lengkap dari Kotlin (lihat
      // MainActivity.handlePythonCall) -- SEBELUMNYA dibuang total di sini,
      // padahal itu satu-satunya cara lihat traceback Python asli tanpa
      // adb logcat. Sekarang di-log penuh (kelihatan lewat `adb logcat`,
      // tag flutter, bahkan di APK release) supaya debugging tidak buta.
      appLog('ApiService', '❌ PlatformException di method "$method": ${e.message}');
      appLog('ApiService', '❌ Detail lengkap (dari Kotlin/Chaquopy):\n${e.details}');
      throw NativeCallException(
        e.message ?? 'Gagal berkomunikasi dengan modul printer native.',
        details: e.details?.toString(),
      );
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

  Future<bool> disconnect() async {
    if (_isMobile) {
      await _invokeNative('disconnect');
      return true;
    }
    final response = await http.post(Uri.parse('$baseUrl/api/disconnect'));
    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception('Failed to disconnect');
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

  Future<bool> connectBle({String? deviceAddress, String? deviceName}) async {
    if (_isMobile) {
      await _invokeNative('connectBle', {'deviceAddress': deviceAddress, 'deviceName': deviceName});
      return true;
    }
    final response = await http.post(
      Uri.parse('$baseUrl/api/connect/ble'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'device_address': deviceAddress, 'device_name': deviceName}),
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

  /// Cek keberadaan barcode/QR di setiap gambar (satu per halaman/file) --
  /// dipakai fitur "Auto-deselect halaman tanpa barcode" di Print Screen.
  /// Return list boolean sejajar urutan `images` (true = ada barcode).
  Future<List<bool>> checkPagesForBarcode(List<Uint8List> images) async {
    if (_isMobile) {
      final imagesBase64 = images.map((bytes) => base64Encode(bytes)).toList();
      final data = await _invokeNative('checkPagesForBarcode', {'imagesBase64': imagesBase64});
      return (data['results'] as List).map((e) => e as bool).toList();
    }
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/check-barcodes'),
    );
    for (int i = 0; i < images.length; i++) {
      request.files.add(http.MultipartFile.fromBytes('images', images[i], filename: 'page_$i.png'));
    }
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['results'] as List).map((e) => e as bool).toList();
    } else if (response.statusCode == 503) {
      throw Exception(json.decode(response.body)['detail'] ?? 'Deteksi barcode tidak tersedia di sistem ini.');
    } else {
      throw Exception('Gagal cek barcode.');
    }
  }

  Future<String> previewImage(File imageFile, {int? paperWidthMm, bool smartCrop = true, CropRect? cropRect}) async {
    if (_isMobile) {
      final data = await _invokeNative('previewImage', {
        'imagePath': imageFile.path,
        'paperWidthMm': paperWidthMm,
        'smartCrop': smartCrop,
        'cropRect': cropRect?.toJson(),
      });
      return data['image_base64'] as String;
    }
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/preview/image'),
    );

    request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
    request.fields['smart_crop'] = smartCrop.toString();
    if (cropRect != null && !cropRect.isFullImage) {
      request.fields['crop_left'] = cropRect.left.toString();
      request.fields['crop_top'] = cropRect.top.toString();
      request.fields['crop_right'] = cropRect.right.toString();
      request.fields['crop_bottom'] = cropRect.bottom.toString();
    }

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

  Future<bool> printImage(File imageFile, {int? paperWidthMm, bool smartCrop = true, CropRect? cropRect, String? protocolOverride}) async {
    if (_isMobile) {
      await _invokeNative('printImage', {
        'imagePath': imageFile.path,
        'paperWidthMm': paperWidthMm,
        'smartCrop': smartCrop,
        'cropRect': cropRect?.toJson(),
        'protocolOverride': protocolOverride,
      });
      return true;
    }
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/print/image'),
    );

    request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
    request.fields['smart_crop'] = smartCrop.toString();
    if (protocolOverride != null) request.fields['protocol_override'] = protocolOverride;
    if (cropRect != null && !cropRect.isFullImage) {
      request.fields['crop_left'] = cropRect.left.toString();
      request.fields['crop_top'] = cropRect.top.toString();
      request.fields['crop_right'] = cropRect.right.toString();
      request.fields['crop_bottom'] = cropRect.bottom.toString();
    }

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

  /// Render halaman-halaman PDF yang diminta jadi file gambar PNG lokal,
  /// dipakai HANYA untuk jalur mobile (Chaquopy tidak bisa pasang PyMuPDF).
  /// Skala render disamakan dengan implementasi lama (zoom 3.0 dari fitz,
  /// ~216 DPI) supaya kualitas cetak thermal tetap sama.
  Future<List<String>> _renderPdfPagesToImages(File pdfFile, List<int> pages) async {
    final document = await PdfDocument.openFile(pdfFile.path);
    final tempDir = await getTemporaryDirectory();
    final imagePaths = <String>[];
    try {
      for (final pageIndex in pages) {
        // pdfx pakai penomoran halaman mulai dari 1, `pages` di kontrak
        // ApiService ini 0-indexed (konsisten dengan implementasi fitz lama).
        final page = await document.getPage(pageIndex + 1);
        try {
          final rendered = await page.render(
            width: page.width * 3,
            height: page.height * 3,
            format: PdfPageImageFormat.png,
          );
          if (rendered == null) {
            throw Exception('Gagal render halaman PDF ke-${pageIndex + 1}.');
          }
          final outPath = p.join(
            tempDir.path,
            'pdf_page_${pageIndex}_${DateTime.now().microsecondsSinceEpoch}.png',
          );
          final outFile = File(outPath);
          await outFile.writeAsBytes(rendered.bytes);
          imagePaths.add(outPath);
        } finally {
          await page.close();
        }
      }
    } finally {
      await document.close();
    }
    return imagePaths;
  }

  Future<bool> printPdf(File pdfFile, List<int> pages, {int? paperWidthMm, bool smartCrop = true, Map<int, CropRect>? cropRects, String? protocolOverride}) async {
    if (_isMobile) {
      // Rasterisasi PDF->gambar di Dart (pdfx/PDFium) dulu, karena
      // python_service.py di Android tidak bisa pasang PyMuPDF (fitz) --
      // Chaquopy tidak punya wheel untuk itu. Hasil render (satu gambar per
      // halaman) dikirim ke native lewat channel `printPdfPages`, sinkron
      // index-ke-index dengan `pages`.
      final imagePaths = await _renderPdfPagesToImages(pdfFile, pages);
      await _invokeNative('printPdfPages', {
        'imagePaths': imagePaths,
        'pages': pages,
        'paperWidthMm': paperWidthMm,
        'smartCrop': smartCrop,
        'cropRects': cropRects?.map((k, v) => MapEntry(k.toString(), v.toJson())),
        'protocolOverride': protocolOverride,
      });
      return true;
    }
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/print/pdf'),
    );

    request.files.add(await http.MultipartFile.fromPath('pdf_file', pdfFile.path));
    request.fields['pages'] = pages.join(',');
    request.fields['smart_crop'] = smartCrop.toString();
    if (cropRects != null && cropRects.isNotEmpty) {
      request.fields['crop_rects_json'] = json.encode(cropRects.map((k, v) => MapEntry(k.toString(), v.toJson())));
    }
    if (protocolOverride != null) request.fields['protocol_override'] = protocolOverride;

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

  Future<bool> printBatch(List<File> files, {int? paperWidthMm, bool smartCrop = true, Map<int, CropRect>? cropRects, String? protocolOverride}) async {
    if (_isMobile) {
      await _invokeNative('printBatch', {
        'filePaths': files.map((f) => f.path).toList(),
        'paperWidthMm': paperWidthMm,
        'smartCrop': smartCrop,
        'cropRects': cropRects?.map((k, v) => MapEntry(k.toString(), v.toJson())),
        'protocolOverride': protocolOverride,
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
    request.fields['smart_crop'] = smartCrop.toString();
    if (cropRects != null && cropRects.isNotEmpty) {
      request.fields['crop_rects_json'] = json.encode(cropRects.map((k, v) => MapEntry(k.toString(), v.toJson())));
    }
    if (protocolOverride != null) request.fields['protocol_override'] = protocolOverride;

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
