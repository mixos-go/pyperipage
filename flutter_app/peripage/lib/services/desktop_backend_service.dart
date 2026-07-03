import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Service untuk menjalankan Python backend secara otomatis di Desktop
class DesktopBackendService {
  static final DesktopBackendService _instance = DesktopBackendService._internal();
  factory DesktopBackendService() => _instance;
  DesktopBackendService._internal();

  Process? _backendProcess;
  bool _isRunning = false;
  final String _host = '127.0.0.1';
  final int _port = 8000;

  /// Cek apakah platform mendukung desktop backend
  bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Status backend
  bool get isRunning => _isRunning;

  /// Mulai Python backend secara otomatis
  Future<bool> startBackend({String? executablePath}) async {
    if (!isDesktop) {
      debugPrint('❌ DesktopBackendService hanya untuk platform desktop');
      return false;
    }

    if (_isRunning) {
      debugPrint('✅ Backend sudah berjalan');
      return true;
    }

    try {
      // Tentukan path executable
      String backendPath = executablePath ?? _findBackendExecutable();
      
      debugPrint('🚀 Starting backend dari: $backendPath');
      
      // Jalankan proses
      _backendProcess = await Process.start(
        backendPath,
        [],
        environment: {
          'PERIPAGE_HOST': _host,
          'PERIPAGE_PORT': _port.toString(),
        },
        runInShell: true,
      );

      // Listen output
      _backendProcess!.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('🐍 [Backend] $data');
      });

      _backendProcess!.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('❌ [Backend Error] $data');
      });

      // Tunggu sebentar untuk memastikan server siap
      await Future.delayed(const Duration(seconds: 3));
      
      _isRunning = true;
      debugPrint('✅ Backend berhasil dijalankan di $_host:$_port');
      
      return true;
    } catch (e) {
      debugPrint('❌ Gagal memulai backend: $e');
      _isRunning = false;
      return false;
    }
  }

  /// Cari executable backend di berbagai lokasi
  String _findBackendExecutable() {
    String exeName = Platform.isWindows ? 'peripage-backend.exe' : 'peripage-backend';
    
    // Coba berbagai lokasi
    List<String> possiblePaths = [
      // Relative dari working directory
      'build/desktop/dist/$exeName',
      '../build/desktop/dist/$exeName',
      // Absolute dari bundle aplikasi
      if (Platform.isMacOS)
        '${Platform.resolvedExecutable}/../Resources/backend/$exeName',
      // Current directory
      exeName,
    ];

    for (var path in possiblePaths) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    // Fallback: coba jalankan dengan python langsung
    return 'python'; // Akan dijalankan dengan script desktop_main.py
  }

  /// Stop backend
  Future<void> stopBackend() async {
    if (_backendProcess != null) {
      debugPrint('🛑 Stopping backend...');
      
      if (Platform.isWindows) {
        // Windows: kill process tree
        await Process.run('taskkill', ['/pid', '${_backendProcess!.pid}', '/f', '/t']);
      } else {
        // Unix: send SIGTERM
        _backendProcess!.kill();
      }
      
      _backendProcess = null;
      _isRunning = false;
      debugPrint('✅ Backend stopped');
    }
  }

  /// Dapatkan URL backend
  String get baseUrl => 'http://$_host:$_port';

  /// Cleanup saat aplikasi ditutup
  Future<void> dispose() async {
    await stopBackend();
  }
}
