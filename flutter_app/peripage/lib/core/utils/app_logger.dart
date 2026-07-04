import 'package:flutter/foundation.dart';

/// Satu baris log aplikasi.
class LogEntry {
  final DateTime timestamp;
  final String tag;
  final String message;

  LogEntry(this.tag, this.message) : timestamp = DateTime.now();

  @override
  String toString() {
    final t = timestamp.toIso8601String().substring(11, 23); // HH:mm:ss.SSS
    return '[$t] [$tag] $message';
  }
}

/// Logger terpusat buat seluruh app -- dipakai SEBAGAI GANTI `debugPrint`
/// langsung di service-service kritikal (DesktopBackendService, ApiService,
/// dll), supaya semua log tersimpan di satu buffer yang bisa DILIHAT dan
/// DI-EXPORT langsung dari dalam app (Settings > Log Aplikasi) -- tanpa
/// perlu adb logcat atau sambungan komputer sama sekali.
///
/// Buffer dibatasi (lihat _maxEntries) supaya tidak membengkak tanpa batas
/// kalau app dipakai berjam-jam.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const int _maxEntries = 2000;
  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void log(String tag, String message) {
    final entry = LogEntry(tag, message);
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeAt(0);
    }
    // Tetap print ke console juga (kelihatan lewat `flutter run` / adb logcat
    // buat yang masih mau pakai itu), TIDAK menggantikan, cuma menambah.
    debugPrint(entry.toString());
  }

  void clear() {
    _entries.clear();
  }

  /// Gabungkan semua entry jadi 1 teks, buat ditampilkan atau di-export.
  String exportAsText() {
    if (_entries.isEmpty) return '(Belum ada log tercatat.)';
    final buffer = StringBuffer();
    buffer.writeln('=== PeriPage A9 - Log Aplikasi ===');
    buffer.writeln('Diexport: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total entri: ${_entries.length}');
    buffer.writeln('=' * 40);
    for (final e in _entries) {
      buffer.writeln(e.toString());
    }
    return buffer.toString();
  }
}

/// Shortcut global -- panggil `appLog('TAG', 'pesan')` di mana pun, sama
/// mudahnya dengan `debugPrint()` tapi otomatis masuk buffer juga.
void appLog(String tag, String message) => AppLogger.instance.log(tag, message);
