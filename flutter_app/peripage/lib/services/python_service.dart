import 'package:flutter/services.dart';

class PythonService {
  static const MethodChannel _channel = MethodChannel('com.example.peripage/python');

  /// Print file menggunakan Python core
  static Future<bool> printFile({
    required String filePath,
    String paperSize = '58mm',
    String transportType = 'ble',
  }) async {
    try {
      final result = await _channel.invokeMethod('printFile', {
        'filePath': filePath,
        'paperSize': paperSize,
        'transportType': transportType,
      });
      return result == true;
    } on PlatformException catch (e) {
      print('Python print error: ${e.message}');
      return false;
    }
  }

  /// Scan devices BLE menggunakan Python
  static Future<List<dynamic>> scanDevices() async {
    try {
      final result = await _channel.invokeMethod('scanDevices');
      return result as List<dynamic>? ?? [];
    } on PlatformException catch (e) {
      print('Python scan error: ${e.message}');
      return [];
    }
  }

  /// Get printer status dari Python
  static Future<Map<String, dynamic>?> getPrinterStatus() async {
    try {
      final result = await _channel.invokeMethod('getPrinterStatus');
      return result as Map<String, dynamic>?;
    } on PlatformException catch (e) {
      print('Python status error: ${e.message}');
      return null;
    }
  }
}
