import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'desktop_backend_service.dart';

class PrinterService {
  static const MethodChannel _channel = MethodChannel('com.pyperipage/printer');
  static final DesktopBackendService _desktopBackend = DesktopBackendService();
  
  /// Cek apakah menggunakan desktop backend (HTTP) atau mobile native (MethodChannel)
  static bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  
  /// Dapatkan base URL untuk desktop
  static String get _baseUrl => _desktopBackend.baseUrl;

  /// Scan perangkat BLE (iOS Native / Android Chaquopy / Desktop HTTP)
  static Future<Map<String, dynamic>> scanDevices() async {
    if (_isDesktop) {
      return await _scanDevicesHttp();
    }
    
    try {
      final result = await _channel.invokeMethod('scanDevices');
      return result as Map<String, dynamic>;
    } on PlatformException catch (e) {
      print('Scan error: ${e.message}');
      return {'status': 'error', 'message': e.message};
    }
  }

  /// HTTP implementation untuk desktop
  static Future<Map<String, dynamic>> _scanDevicesHttp() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/ble/scan'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'Failed to scan devices'};
      }
    } catch (e) {
      print('HTTP Scan error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// Connect ke printer
  static Future<Map<String, dynamic>> connectToDevice(String deviceId) async {
    if (_isDesktop) {
      return await _connectToDeviceHttp(deviceId);
    }
    
    try {
      final result = await _channel.invokeMethod('connectToDevice', {
        'deviceId': deviceId,
      });
      return result as Map<String, dynamic>;
    } on PlatformException catch (e) {
      print('Connect error: ${e.message}');
      return {'status': 'error', 'message': e.message};
    }
  }

  static Future<Map<String, dynamic>> _connectToDeviceHttp(String deviceId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/printer/connect'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'device_id': deviceId}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'Failed to connect'};
      }
    } catch (e) {
      print('HTTP Connect error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// Disconnect dari printer
  static Future<Map<String, dynamic>> disconnect() async {
    if (_isDesktop) {
      return await _disconnectHttp();
    }
    
    try {
      final result = await _channel.invokeMethod('disconnect');
      return result as Map<String, dynamic>;
    } on PlatformException catch (e) {
      print('Disconnect error: ${e.message}');
      return {'status': 'error', 'message': e.message};
    }
  }

  static Future<Map<String, dynamic>> _disconnectHttp() async {
    try {
      final response = await http.post(Uri.parse('$_baseUrl/api/printer/disconnect'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'Failed to disconnect'};
      }
    } catch (e) {
      print('HTTP Disconnect error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// Print teks dengan formatting
  static Future<Map<String, dynamic>> printText({
    required String text,
    String align = 'left',
    bool bold = false,
    bool doubleSize = false,
  }) async {
    if (_isDesktop) {
      return await _printTextHttp(text, align, bold, doubleSize);
    }
    
    try {
      final result = await _channel.invokeMethod('printText', {
        'text': text,
        'align': align,
        'bold': bold,
        'doubleSize': doubleSize,
      });
      return result as Map<String, dynamic>;
    } on PlatformException catch (e) {
      print('Print text error: ${e.message}');
      return {'status': 'error', 'message': e.message};
    }
  }

  static Future<Map<String, dynamic>> _printTextHttp(
    String text, String align, bool bold, bool doubleSize) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/print/text'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'text': text,
          'align': align,
          'bold': bold,
          'double_size': doubleSize,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'Failed to print text'};
      }
    } catch (e) {
      print('HTTP Print text error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// Print gambar dari path file
  static Future<Map<String, dynamic>> printImage(String imagePath) async {
    if (_isDesktop) {
      return await _printImageHttp(imagePath);
    }
    
    try {
      final result = await _channel.invokeMethod('printImage', {
        'imagePath': imagePath,
      });
      return result as Map<String, dynamic>;
    } on PlatformException catch (e) {
      print('Print image error: ${e.message}');
      return {'status': 'error', 'message': e.message};
    }
  }

  static Future<Map<String, dynamic>> _printImageHttp(String imagePath) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/print/image'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'image_path': imagePath}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'Failed to print image'};
      }
    } catch (e) {
      print('HTTP Print image error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// Print PDF (akan diimplementasikan nanti)
  static Future<Map<String, dynamic>> printPDF(String pdfPath) async {
    if (_isDesktop) {
      return await _printPDFHttp(pdfPath);
    }
    
    try {
      final result = await _channel.invokeMethod('printPDF', {
        'pdfPath': pdfPath,
      });
      return result as Map<String, dynamic>;
    } on PlatformException catch (e) {
      print('Print PDF error: ${e.message}');
      return {'status': 'error', 'message': e.message};
    }
  }

  static Future<Map<String, dynamic>> _printPDFHttp(String pdfPath) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/print/pdf'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'pdf_path': pdfPath}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'Failed to print PDF'};
      }
    } catch (e) {
      print('HTTP Print PDF error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }
}
