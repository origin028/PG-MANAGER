import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme {
  // Brand Colors
  static const Color primaryBlue = Color(0xFF0066FF); // Brand Electric Blue
  static const Color primaryOrange = Color(0xFF0066FF); // Pointed to Blue for full blue theme
  static const Color brandPurple = Color(0xFF8B5CF6); // Purple for Add Resident
  static const Color primaryLight = Color(0xFFEFF6FF); // Soft blue active tint
  static const Color scaffoldBackground = Color(0xFFF8FAFC); // Clean page background
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF0F172A); // Dark slate
  static const Color textGrey = Color(0xFF64748B); // Slate grey
  static const Color inputBorder = Color(0xFFE2E8F0);
  static const Color successGreen = Color(0xFF10B981);
  static const Color logoutRed = Color(0xFFEF4444);

  /// Standard decoration for Form Dropdowns across the application
  static InputDecoration formDropdownDecoration({
    String? labelText,
    String? hintText,
    Widget? prefixIcon,
    Color? fillColor,
  }) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: const TextStyle(color: textGrey, fontSize: 14),
      floatingLabelStyle: const TextStyle(color: textGrey, fontSize: 14, fontWeight: FontWeight.w500),
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: fillColor ?? Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: inputBorder),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: primaryBlue, width: 1.5),
      ),
    );
  }

  /// Standard decoration for Form Inputs across the application
  static InputDecoration formInputDecoration({
    String? labelText,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF5F7FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: primaryBlue, width: 1.5),
      ),
    );
  }

  // Dynamic Theme Mode Notifier
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
  static final ValueNotifier<String> themeNameNotifier = ValueNotifier<String>('System Default');

  static Future<void> initTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString('app_theme_mode');
      if (savedTheme == 'Light') {
        themeModeNotifier.value = ThemeMode.light;
        themeNameNotifier.value = 'Light';
      } else if (savedTheme == 'Dark') {
        themeModeNotifier.value = ThemeMode.dark;
        themeNameNotifier.value = 'Dark';
      } else {
        themeModeNotifier.value = ThemeMode.system;
        themeNameNotifier.value = 'System Default';
      }
    } catch (_) {}
  }

  static Future<void> setThemeMode(String modeName) async {
    themeNameNotifier.value = modeName;
    if (modeName == 'Light') {
      themeModeNotifier.value = ThemeMode.light;
    } else if (modeName == 'Dark') {
      themeModeNotifier.value = ThemeMode.dark;
    } else {
      themeModeNotifier.value = ThemeMode.system;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_theme_mode', modeName);
    } catch (_) {}
  }

  // Light Theme Configuration
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        surface: backgroundWhite,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: scaffoldBackground,
      cardColor: Colors.white,
      dividerColor: const Color(0xFFF1F5F9),
      
      // Typography using Google Fonts
      textTheme: GoogleFonts.interTextTheme().copyWith(
        headlineMedium: GoogleFonts.inter(
          color: textDark,
          fontWeight: FontWeight.bold,
        ),
        bodyMedium: GoogleFonts.inter(
          color: textGrey,
        ),
      ),

      // Standard Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: backgroundWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        titleTextStyle: GoogleFonts.inter(
          color: textDark,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: GoogleFonts.inter(
          color: textGrey,
          fontSize: 14,
          height: 1.5,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      ),

      // Standard Button Style
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30), // Pill shape
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          elevation: 0,
        ),
      ),

      // Standard Input Field Style
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: backgroundWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: inputBorder),
        ),
        labelStyle: GoogleFonts.inter(
          color: textGrey,
          fontSize: 14,
        ),
        floatingLabelStyle: GoogleFonts.inter(
          color: textGrey,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: GoogleFonts.inter(
          color: const Color(0xFF94A3B8),
          fontSize: 14,
        ),
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
        primary: primaryBlue,
        brightness: Brightness.dark,
        surface: const Color(0xFF1E293B),
      ),
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      cardColor: const Color(0xFF1E293B),
      dividerColor: const Color(0xFF334155),
      
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        headlineMedium: GoogleFonts.inter(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        bodyMedium: GoogleFonts.inter(
          color: const Color(0xFF94A3B8),
        ),
      ),

      // Standard Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF1E293B),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF334155), width: 1),
        ),
        titleTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: GoogleFonts.inter(
          color: const Color(0xFF94A3B8),
          fontSize: 14,
          height: 1.5,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          elevation: 0,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        labelStyle: GoogleFonts.inter(
          color: const Color(0xFF94A3B8),
          fontSize: 14,
        ),
        floatingLabelStyle: GoogleFonts.inter(
          color: const Color(0xFF94A3B8),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: GoogleFonts.inter(
          color: const Color(0xFF64748B),
          fontSize: 14,
        ),
      ),
    );
  }
}