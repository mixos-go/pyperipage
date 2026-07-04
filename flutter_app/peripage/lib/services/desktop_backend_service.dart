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

  /// Cari executable backend di berbagai lokasi.
  ///
  /// FIX (Juli 2026): sebelumnya path yang dicoba semuanya relatif ke
  /// Current Working Directory ('build/desktop/dist/...', atau nama file
  /// polos) -- ini TIDAK RELIABLE karena CWD app desktop bisa apa saja
  /// tergantung cara app dijalankan (double-click dari file manager,
  /// shortcut, terminal di folder lain, dst), BUKAN selalu folder tempat
  /// file .exe/binary utama berada. Makanya backend gagal ditemukan &
  /// auto-start gagal di Linux (dan berpotensi juga Windows/macOS,
  /// tergantung cara app dibuka).
  ///
  /// CI (build-multi-platform.yml) selalu meletakkan
  /// peripage-backend(.exe) di folder YANG SAMA dengan executable utama:
  /// - Windows: build/windows/x64/runner/Release/ (sama dengan peripage.exe)
  /// - Linux:   build/linux/x64/release/bundle/   (sama dengan peripage)
  /// - macOS:   .../peripage.app/Contents/MacOS/  (sama dengan peripage)
  ///
  /// Jadi path yang BENAR adalah relatif ke `Platform.resolvedExecutable`
  /// (lokasi app yang SEDANG BERJALAN), bukan CWD.
  String _findBackendExecutable() {
    String exeName = Platform.isWindows ? 'peripage-backend.exe' : 'peripage-backend';

    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final sameDir = '$executableDir${Platform.pathSeparator}$exeName';

    List<String> possiblePaths = [
      sameDir, // prioritas utama -- sesuai lokasi CI meletakkan backend
      // Fallback lama, dipertahankan buat kasus dev lokal yang jalanin
      // `flutter run` langsung dari root project (CWD == root project).
      'build/desktop/dist/$exeName',
      '../build/desktop/dist/$exeName',
      exeName,
    ];

    for (var path in possiblePaths) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    debugPrint(
      '⚠️ Backend executable tidak ditemukan di path manapun (dicoba: $possiblePaths). '
      'Fallback ke "python" -- ini HANYA akan berhasil kalau python & '
      'desktop_main.py ada di PATH, yang biasanya TIDAK BENAR untuk build '
      'rilis. Cek apakah CI benar-benar meng-copy $exeName ke $executableDir.',
    );
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
