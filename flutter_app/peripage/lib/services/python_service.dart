import 'package:flutter/services.dart';

class PrinterService {
  static const MethodChannel _channel = MethodChannel('com.pyperipage/printer');

  /// Scan perangkat BLE (iOS Native / Android Chaquopy)
  static Future<Map<String, dynamic>> scanDevices() async {
    try {
      final result = await _channel.invokeMethod('scanDevices');
      return result as Map<String, dynamic>;
    } on PlatformException catch (e) {
      print('Scan error: ${e.message}');
      return {'status': 'error', 'message': e.message};
    }
  }

  /// Connect ke printer
  static Future<Map<String, dynamic>> connectToDevice(String deviceId) async {
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

  /// Disconnect dari printer
  static Future<Map<String, dynamic>> disconnect() async {
    try {
      final result = await _channel.invokeMethod('disconnect');
      return result as Map<String, dynamic>;
    } on PlatformException catch (e) {
      print('Disconnect error: ${e.message}');
      return {'status': 'error', 'message': e.message};
    }
  }

  /// Print teks dengan formatting
  static Future<Map<String, dynamic>> printText({
    required String text,
    String align = 'left',
    bool bold = false,
    bool doubleSize = false,
  }) async {
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

  /// Print gambar dari path file
  static Future<Map<String, dynamic>> printImage(String imagePath) async {
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

  /// Print PDF (akan diimplementasikan nanti)
  static Future<Map<String, dynamic>> printPDF(String pdfPath) async {
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
}
