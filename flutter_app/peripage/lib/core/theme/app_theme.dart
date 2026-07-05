import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/constants.dart';

/// Mode tema yang didukung app. `amoled` beda dari `dark` biasa: background
/// & surface benar-benar hitam murni (#000000), bukan abu-abu gelap --
/// menghemat daya di layar OLED/AMOLED (piksel hitam = mati total).
enum AppThemeMode { light, dark, amoled }

/// Theme configuration untuk aplikasi PeriPage A9.
class AppTheme {
  // Primary color scheme -- brand blue, dipilih sesuai palet icon app.
  static const Color primaryColor = Color(0xFF1976D2);
  static const Color primaryLight = Color(0xFF42A5F5);
  static const Color primaryDark = Color(0xFF0D47A1);
  static const Color secondaryColor = Color(0xFF424242);
  static const Color accentColor = Color(0xFFFF5722);

  // Background colors (light)
  static const Color backgroundColor = Color(0xFFF5F5F5);
  static const Color surfaceColor = Colors.white;

  // Background colors (dark biasa, bukan AMOLED)
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);

  // Background colors (AMOLED -- hitam murni)
  static const Color amoledBackground = Color(0xFF000000);
  static const Color amoledSurface = Color(0xFF0A0A0A);

  // Text colors
  static const Color textPrimaryColor = Color(0xFF212121);
  static const Color textSecondaryColor = Color(0xFF757575);
  static const Color textLightColor = Colors.white;

  // Status colors -- konstan lintas tema (error tetap merah di light/dark/amoled).
  static const Color successColor = Color(0xFF4CAF50);
  static const Color errorColor = Color(0xFFF44336);
  static const Color warningColor = Color(0xFFFF9800);
  static const Color infoColor = Color(0xFF2196F3);

  /// Gradient brand utama -- dipakai header, tombol utama, avatar placeholder,
  /// elemen "3D-style" (soft gradient + shadow) di seluruh redesign UI.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryLight, primaryColor, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Gradient lembut buat background card/section (bukan solid flat).
  static LinearGradient softGradient(Brightness brightness) {
    return brightness == Brightness.light
        ? LinearGradient(
            colors: [primaryColor.withValues(alpha: 0.08), Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        : LinearGradient(
            colors: [primaryColor.withValues(alpha: 0.15), Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
  }

  static ThemeData _baseTheme({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color onSurface,
  }) {
    final isLight = brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primaryColor,
        secondary: secondaryColor,
        tertiary: accentColor,
        surface: surface,
        error: errorColor,
        onPrimary: textLightColor,
        onSecondary: textLightColor,
        onSurface: onSurface,
        onError: textLightColor,
      ),
      textTheme: (isLight ? GoogleFonts.robotoTextTheme() : GoogleFonts.robotoTextTheme(ThemeData.dark().textTheme)).copyWith(
        displayLarge: GoogleFonts.roboto(fontSize: 32, fontWeight: FontWeight.bold, color: onSurface),
        headlineMedium: GoogleFonts.roboto(fontSize: 24, fontWeight: FontWeight.w600, color: onSurface),
        titleLarge: GoogleFonts.roboto(fontSize: 20, fontWeight: FontWeight.w600, color: onSurface),
        bodyLarge: GoogleFonts.roboto(fontSize: 16, color: onSurface),
        bodyMedium: GoogleFonts.roboto(fontSize: 14, color: onSurface.withValues(alpha: 0.7)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? primaryColor : surface,
        foregroundColor: isLight ? textLightColor : onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.roboto(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: isLight ? textLightColor : onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: isLight ? 2 : 0,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiConstants.borderRadiusLg),
          side: isLight ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: textLightColor,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: UiConstants.spacingLg, vertical: UiConstants.spacingMd),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UiConstants.borderRadiusLg)),
          textStyle: GoogleFonts.roboto(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: UiConstants.spacingLg, vertical: UiConstants.spacingMd),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UiConstants.borderRadiusLg)),
          textStyle: GoogleFonts.roboto(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiConstants.borderRadiusLg),
          borderSide: BorderSide(color: onSurface.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiConstants.borderRadiusLg),
          borderSide: BorderSide(color: onSurface.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiConstants.borderRadiusLg),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiConstants.borderRadiusLg),
          borderSide: const BorderSide(color: errorColor),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: UiConstants.spacingMd, vertical: UiConstants.spacingMd),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: textLightColor,
        elevation: 4,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isLight ? secondaryColor : surface,
        contentTextStyle: GoogleFonts.roboto(color: isLight ? textLightColor : onSurface, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UiConstants.borderRadiusMd)),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primaryColor),
      dividerTheme: DividerThemeData(color: onSurface.withValues(alpha: 0.12), thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primaryColor.withValues(alpha: 0.16),
      ),
    );
  }

  static ThemeData get lightTheme => _baseTheme(
        brightness: Brightness.light,
        background: backgroundColor,
        surface: surfaceColor,
        onSurface: textPrimaryColor,
      );

  static ThemeData get darkTheme => _baseTheme(
        brightness: Brightness.dark,
        background: darkBackground,
        surface: darkSurface,
        onSurface: Colors.white,
      );

  /// AMOLED -- hitam murni, dioptimalkan buat layar OLED (hemat daya).
  static ThemeData get amoledTheme => _baseTheme(
        brightness: Brightness.dark,
        background: amoledBackground,
        surface: amoledSurface,
        onSurface: Colors.white,
      );

  static ThemeData themeFor(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return lightTheme;
      case AppThemeMode.dark:
        return darkTheme;
      case AppThemeMode.amoled:
        return amoledTheme;
    }
  }
}
