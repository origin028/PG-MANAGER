import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme {
  // Brand colors: Modern Indigo/Purple theme matching reference design
  static const Color primaryBlue = Color(0xFF4F46E5); // Purple / Indigo
  static const Color primaryDarkBlue = Color(0xFF3730A3);
  static const Color primaryLightBlue = Color(0xFF818CF8);
  static const Color primaryOrange = Color(0xFF4F46E5);

  // Backgrounds and Neutrals
  static const Color backgroundWhite = Color(0xFFF7F8FE); // Soft lavender/periwinkle tinted background
  static const Color cardWhite = Colors.white;
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color textLight = Color(0xFF94A3B8);
  static const Color softGrey = Color(0xFFF1F5F9);
  static const Color inputBorder = Color(0xFFE2E8F0);

  // Dark Theme Neutral Colors
  static const Color darkBackground = Color(0xFF0F172A); // Slate 900
  static const Color darkCard = Color(0xFF1E293B); // Slate 800
  static const Color darkCardElevated = Color(0xFF243247);
  static const Color darkBorder = Color(0xFF334155); // Slate 700
  static const Color darkTextPrimary = Colors.white;
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  // Accent & Action Colors
  static const Color softPink = Color(0xFFFFECEF);
  static const Color accentPink = Color(0xFFFF4081);
  static const Color softGreen = Color(0xFFE6FFFA);
  static const Color accentGreen = Color(0xFF0D9488);
  static const Color successGreen = Color(0xFF16A34A);
  static const Color softAmber = Color(0xFFFFF7ED);
  static const Color accentAmber = Color(0xFFEA580C);
  static const Color softPurple = Color(0xFFEEF2FF);
  static const Color accentPurple = Color(0xFF6366F1);
  static const Color softSky = Color(0xFFE0F2FE);
  static const Color accentSky = Color(0xFF0284C7);

  // Signature Hero Card Gradient: Soft lavender/blue shaded background
  static const LinearGradient cardShadeGradient = LinearGradient(
    colors: [
      Color(0xFFE0E7FF), // Soft pastel periwinkle / lavender
      Color(0xFFEEF2FF),
      Color(0xFFF8FAFC),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardShadeDarkGradient = LinearGradient(
    colors: [
      Color(0xFF1E1B4B), // Deep indigo
      Color(0xFF1E293B), // Slate 800
      Color(0xFF0F172A), // Slate 900
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [
      Color(0xFF4F46E5),
      Color(0xFF6366F1),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient blueGradient = primaryGradient;
  static const LinearGradient heroCardGradient = cardShadeGradient;

  // Dynamic Theme Mode Notifier
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

  static Future<void> initTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString('resident_theme_mode');
      if (savedTheme == 'Dark') {
        themeModeNotifier.value = ThemeMode.dark;
      } else {
        themeModeNotifier.value = ThemeMode.light;
      }
    } catch (_) {}
  }

  static Future<void> toggleTheme(bool isDark) async {
    themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('resident_theme_mode', isDark ? 'Dark' : 'Light');
    } catch (_) {}
  }

  // Theme-aware helpers
  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color cardBg(BuildContext context) => isDark(context) ? darkCard : Colors.white;
  static Color borderCol(BuildContext context) => isDark(context) ? darkBorder : const Color(0xFFEDF2F7);
  static Color pageBg(BuildContext context) => isDark(context) ? darkBackground : backgroundWhite;
  static Color textPrimary(BuildContext context) => isDark(context) ? darkTextPrimary : textDark;
  static Color textSecondary(BuildContext context) => isDark(context) ? darkTextSecondary : textGrey;
  static LinearGradient heroGradient(BuildContext context) => isDark(context) ? cardShadeDarkGradient : cardShadeGradient;

  // Light Theme Configuration
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        surface: Colors.white,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: backgroundWhite,
      cardColor: Colors.white,
      dividerColor: const Color(0xFFEDF2F7),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: textDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: GoogleFonts.interTextTheme().copyWith(
        headlineMedium: GoogleFonts.inter(color: textDark, fontWeight: FontWeight.bold),
        bodyMedium: GoogleFonts.inter(color: textGrey),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF5F7FA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryBlue, width: 1.5),
        ),
        hintStyle: GoogleFonts.inter(color: textLight, fontSize: 14),
      ),
    );
  }

  // Dark Theme Configuration
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryLightBlue,
        surface: darkCard,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: darkBackground,
      cardColor: darkCard,
      dividerColor: darkBorder,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkCard,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        headlineMedium: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
        bodyMedium: GoogleFonts.inter(color: darkTextSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkBorder, width: 1.0),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: primaryLightBlue, width: 1.5),
        ),
        hintStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 14),
      ),
    );
  }
}
