import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Satu entri file yang baru-baru ini di-print -- ditampilkan di Workspace
/// (Home) sebagai "Recent Files", mirip pola workspace app AI modern
/// (riwayat chat/file terakhir).
class RecentFile {
  final String path;
  final String name;
  final String type; // 'image' | 'pdf' | 'batch'
  final DateTime printedAt;

  RecentFile({required this.path, required this.name, required this.type, required this.printedAt});

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'type': type,
        'printedAt': printedAt.toIso8601String(),
      };

  factory RecentFile.fromJson(Map<String, dynamic> json) => RecentFile(
        path: json['path'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        printedAt: DateTime.parse(json['printedAt'] as String),
      );
}

/// Service persist daftar recent files (maks 15 entri terbaru) pakai
/// shared_preferences -- ringan, tidak butuh database.
class RecentFilesService {
  static const _prefsKey = 'recent_printed_files';
  static const _maxEntries = 15;

  Future<List<RecentFile>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey) ?? [];
      return raw.map((s) => RecentFile.fromJson(jsonDecode(s))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(RecentFile file) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await load();
      // Hapus duplikat path yang sama, taruh yang baru di paling atas.
      current.removeWhere((f) => f.path == file.path);
      current.insert(0, file);
      final trimmed = current.take(_maxEntries).toList();
      await prefs.setStringList(_prefsKey, trimmed.map((f) => jsonEncode(f.toJson())).toList());
    } catch (_) {
      // Gagal persist -- bukan fatal, cuma riwayat tidak tersimpan.
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}
