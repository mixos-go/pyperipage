import 'dart:io';
import 'dart:convert';
import '../core/utils/app_logger.dart';

/// Service untuk menjalankan Python backend secara otomatis di Desktop
class DesktopBackendService {
  static final DesktopBackendService _instance = DesktopBackendService._internal();
  factory DesktopBackendService() => _instance;
  DesktopBackendService._internal();

  Process? _backendProcess;
  bool _isRunning = false;
  final String _host = '127.0.0.1';
  final int _port = 8000;
  final StringBuffer _stderrBuffer = StringBuffer();

  /// Cek apakah platform mendukung desktop backend
  bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Status backend
  bool get isRunning => _isRunning;

  /// Pesan error TERAKHIR & SEBENARNYA dari proses backend (stderr, exit
  /// code, dst) -- dipakai UI buat menampilkan alasan asli kalau auto-start
  /// gagal, BUKAN pesan generik statis.
  String? get lastError => _lastError;
  String? _lastError;

  /// Mulai Python backend secara otomatis
  Future<bool> startBackend({String? executablePath}) async {
    if (!isDesktop) {
      appLog('Backend', '❌ DesktopBackendService hanya untuk platform desktop');
      return false;
    }

    if (_isRunning) {
      appLog('Backend', '✅ Backend sudah berjalan');
      return true;
    }

    _lastError = null;
    _stderrBuffer.clear();

    try {
      // Tentukan path executable
      String backendPath = executablePath ?? _findBackendExecutable();

      appLog('Backend', '🚀 Starting backend dari: $backendPath');

      if (backendPath == 'python') {
        // _findBackendExecutable() sudah print warning detail -- di sini
        // cukup pastikan error itu juga sampai ke UI (bukan cuma console).
        _lastError = 'Binary peripage-backend tidak ditemukan di folder aplikasi. '
            'Pastikan file peripage-backend ada di folder yang sama dengan aplikasi utama.';
        return false;
      }

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

      final process = _backendProcess!;

      // Listen output (juga dikumpulkan ke buffer buat ditampilkan ke UI
      // kalau proses ternyata gagal start).
      process.stdout.transform(utf8.decoder).listen((data) {
        appLog('Backend', '🐍 [Backend] $data');
      });
      process.stderr.transform(utf8.decoder).listen((data) {
        appLog('Backend', '❌ [Backend Error] $data');
        _stderrBuffer.write(data);
      });

      // Race antara: (a) proses keluar duluan sebelum port kebuka -> gagal,
      // atau (b) port 8000 berhasil di-connect -> beneran jalan.
      // GANTI dari `Future.delayed(3 detik)` lalu asumsi sukses tanpa
      // verifikasi apa pun -- itu bikin app bilang "backend jalan" padahal
      // proses-nya sudah crash duluan (misal .so hilang saat packaging).
      final exitedEarly = process.exitCode.then((code) => _ExitedEarly(code));
      final portReady = _waitForPort(timeout: const Duration(seconds: 10))
          .then((ok) => ok ? _PortReady() : _PortReady(timedOut: true));

      final result = await Future.any([exitedEarly, portReady]);

      if (result is _ExitedEarly) {
        _lastError = 'Proses backend keluar sendiri (exit code ${result.code}) sebelum '
            'server siap.\n\nOutput error:\n${_stderrBuffer.toString().trim().isEmpty ? '(tidak ada output)' : _stderrBuffer.toString().trim()}';
        appLog('Backend', '❌ Backend exited early: ${result.code}');
        _isRunning = false;
        return false;
      }

      if (result is _PortReady && result.timedOut) {
        _lastError = 'Backend tidak merespons di port $_port setelah 10 detik.\n\n'
            'Output sejauh ini:\n${_stderrBuffer.toString().trim().isEmpty ? '(tidak ada output)' : _stderrBuffer.toString().trim()}';
        appLog('Backend', '❌ Backend timeout menunggu port $_port');
        _isRunning = false;
        return false;
      }

      _isRunning = true;
      appLog('Backend', '✅ Backend berhasil dijalankan di $_host:$_port');
      return true;
    } catch (e) {
      appLog('Backend', '❌ Gagal memulai backend: $e');
      _lastError = 'Gagal menjalankan proses backend: $e';
      _isRunning = false;
      return false;
    }
  }

  /// Poll port TCP sampai kebuka (server FastAPI/uvicorn siap menerima
  /// koneksi) atau timeout. Jauh lebih andal daripada nunggu waktu tetap.
  Future<bool> _waitForPort({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final socket = await Socket.connect(_host, _port, timeout: const Duration(milliseconds: 500));
        await socket.close();
        return true;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    return false;
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

    appLog('Backend', 
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
      appLog('Backend', '🛑 Stopping backend...');
      
      if (Platform.isWindows) {
        // Windows: kill process tree
        await Process.run('taskkill', ['/pid', '${_backendProcess!.pid}', '/f', '/t']);
      } else {
        // Unix: send SIGTERM
        _backendProcess!.kill();
      }
      
      _backendProcess = null;
      _isRunning = false;
      appLog('Backend', '✅ Backend stopped');
    }
  }

  /// Restart backend -- dipakai tombol "Coba Lagi" di banner UI, supaya
  /// user bisa retry START ULANG backend langsung dari dalam app, TANPA
  /// perlu buka terminal atau file manager sama sekali.
  Future<bool> restartBackend() async {
    await stopBackend();
    return startBackend();
  }

  /// Dapatkan URL backend
  String get baseUrl => 'http://$_host:$_port';

  /// Cleanup saat aplikasi ditutup
  Future<void> dispose() async {
    await stopBackend();
  }
}

/// Helper internal buat Future.any() di startBackend() -- proses backend
/// keluar sendiri sebelum port kebuka (kemungkinan besar CRASH saat startup).
class _ExitedEarly {
  final int code;
  _ExitedEarly(this.code);
}

/// Helper internal buat Future.any() di startBackend() -- hasil polling port.
class _PortReady {
  final bool timedOut;
  _PortReady({this.timedOut = false});
}
