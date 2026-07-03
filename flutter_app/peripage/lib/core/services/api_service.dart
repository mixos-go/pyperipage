import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import '../../data/models/printer_models.dart';

/// Service untuk komunikasi HTTP dengan Python backend
class ApiService {
  final String baseUrl;
  
  ApiService({this.baseUrl = ApiConstants.baseUrl});

  /// Health check endpoint
  Future<Map<String, dynamic>> healthCheck() async {
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

  /// Get printer status
  Future<PrinterStatus> getPrinterStatus() async {
    final response = await http.get(Uri.parse('$baseUrl/api/status'));
    if (response.statusCode == 200) {
      return PrinterStatus.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to get printer status');
    }
  }

  /// Connect via USB
  Future<bool> connectUsb() async {
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

  /// Connect via BLE
  Future<bool> connectBle({String? deviceAddress}) async {
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

  /// Discover BLE devices
  Future<List<BleDevice>> discoverBleDevices({double timeout = 5.0}) async {
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

  /// Set paper width
  Future<bool> setPaperWidth(int widthMm) async {
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

  /// Get paper width config
  Future<PrinterConfig> getPaperWidthConfig() async {
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

  /// Get full config
  Future<PrinterConfig> getConfig() async {
    final response = await http.get(Uri.parse('$baseUrl/api/config'));
    if (response.statusCode == 200) {
      return PrinterConfig.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to get config');
    }
  }

  /// Preview image (return base64)
  Future<String> previewImage(File imageFile, {int? paperWidthMm}) async {
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
      // Return base64 string
      return base64Encode(response.bodyBytes);
    } else {
      throw Exception('Failed to preview image');
    }
  }

  /// Print image
  Future<bool> printImage(File imageFile, {int? paperWidthMm}) async {
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

  /// Print PDF
  Future<bool> printPdf(File pdfFile, List<int> pages, {int? paperWidthMm}) async {
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

  /// Print batch (multiple files)
  Future<bool> printBatch(List<File> files, {int? paperWidthMm}) async {
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
