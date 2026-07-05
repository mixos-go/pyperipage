import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

/// Controller tema global -- persist pilihan Light/Dark/AMOLED antar sesi
/// pakai shared_preferences. Dipasang di root MaterialApp lewat Provider.
class ThemeController extends ChangeNotifier {
  static const _prefsKey = 'app_theme_mode';

  AppThemeMode _mode = AppThemeMode.light;
  AppThemeMode get mode => _mode;
  ThemeData get themeData => AppTheme.themeFor(_mode);

  ThemeController() {
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        _mode = AppThemeMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => AppThemeMode.light,
        );
        notifyListeners();
      }
    } catch (_) {
      // Gagal baca preference (misal platform belum support) -- fallback ke light, tidak fatal.
    }
  }

  Future<void> setMode(AppThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // Gagal simpan -- tema tetap berubah untuk sesi ini, cuma tidak persist.
    }
  }
}
