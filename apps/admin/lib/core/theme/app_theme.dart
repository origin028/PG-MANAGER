import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme {
  // --------------------------------------------------------------------------
  // Reference Palette from PG_Pilot_Admin_Pro.html
  // --------------------------------------------------------------------------
  static const Color primaryNavy = Color(0xFF0B2231); // #0B2231 Sidebar Start / Navy
  static const Color darkNavy = Color(0xFF0A1E2B); // #0A1E2B Sidebar End / Deep Navy
  static const Color primaryTeal = Color(0xFF0B6B63); // #0B6B63 Primary Brand Accent
  static const Color brightTeal = Color(0xFF14B8A6); // #14B8A6 Glow / Accent Bright
  static const Color glowTeal = Color(0xFF5EEAD4); // #5EEAD4 Bright Active Indicator
  static const Color lightTeal = Color(0xFFE2F0EE); // #E2F0EE Soft Teal Pill / Tint
  static const Color lightTealDark = Color(0xFF14312F); // #14312F Dark Mode Soft Teal

  static const Color scaffoldBackground = Color(0xFFF3F6F6); // #F3F6F6 Light Page Background
  static const Color scaffoldBackgroundDark = Color(0xFF0A1418); // #0A1418 Dark Page Background
  static const Color cardBackground = Color(0xFFFFFFFF); // #FFFFFF Light Card
  static const Color cardBackgroundDark = Color(0xFF111F25); // #111F25 Dark Card

  static const Color primaryText = Color(0xFF0E1A1F); // #0E1A1F Main Text Light
  static const Color primaryTextDark = Color(0xFFE8F0EE); // #E8F0EE Main Text Dark
  static const Color secondaryText = Color(0xFF56626B); // #56626B Muted Text Light
  static const Color secondaryTextDark = Color(0xFF9AABB0); // #9AABB0 Muted Text Dark
  static const Color borderColor = Color(0xFFE2E8E7); // #E2E8E7 Border Light
  static const Color borderColorDark = Color(0xFF223238); // #223238 Border Dark
  static const Color softBackground = Color(0xFFF6F9F8); // #F6F9F8 Soft Light
  static const Color softBackgroundDark = Color(0xFF16272D); // #16272D Soft Dark

  // Semantic Status Colors
  static const Color statusOk = Color(0xFF0F6B4A); // #0F6B4A Success Green
  static const Color statusOkSoft = Color(0xFFDDF3E8); // #DDF3E8 Success Soft
  static const Color statusAmb = Color(0xFF92400E); // #92400E Warning Amber
  static const Color statusAmbSoft = Color(0xFFFEF3C7); // #FEF3C7 Warning Soft
  static const Color statusRed = Color(0xFFB42318); // #B42318 Error / Overdue Red
  static const Color statusRedSoft = Color(0xFFFDE8E6); // #FDE8E6 Error Soft
  static const Color statusBlu = Color(0xFF0B5CAD); // #0B5CAD Info Blue
  static const Color statusBluSoft = Color(0xFFE1EEFB); // #E1EEFB Info Soft

  // Backward-compatible aliases for existing widget references & tests
  static const Color primaryBlue = primaryTeal; // Color(0xFF0B6B63)
  static const Color primaryOrange = Color(0xFFB45309);
  static const Color brandPurple = Color(0xFF8B5CF6);
  static const Color primaryLight = lightTeal;
  static const Color backgroundWhite = Colors.white;
  static const Color textDark = primaryText;
  static const Color textGrey = secondaryText;
  static const Color inputBorder = borderColor;
  static const Color successGreen = statusOk;
  static const Color logoutRed = statusRed;

  /// Standard decoration for Form Dropdowns across the application
  static InputDecoration formDropdownDecoration({
    String? labelText,
    String? hintText,
    Widget? prefixIcon,
    Color? fillColor,
  }) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: const TextStyle(color: secondaryText, fontSize: 13.5, fontWeight: FontWeight.w600),
      floatingLabelStyle: const TextStyle(color: primaryTeal, fontSize: 14, fontWeight: FontWeight.w700),
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: fillColor ?? Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: primaryTeal, width: 1.5),
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
      fillColor: softBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: primaryTeal, width: 1.5),
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
        seedColor: primaryTeal,
        primary: primaryTeal,
        secondary: brightTeal,
        surface: cardBackground,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: scaffoldBackground,
      cardColor: cardBackground,
      dividerColor: borderColor,
      
      // Modern Manrope Typography
      textTheme: GoogleFonts.manropeTextTheme().copyWith(
        headlineLarge: GoogleFonts.manrope(
          color: primaryText,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineMedium: GoogleFonts.manrope(
          color: primaryText,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: GoogleFonts.manrope(
          color: primaryText,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        titleMedium: GoogleFonts.manrope(
          color: primaryText,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: GoogleFonts.manrope(
          color: primaryText,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: GoogleFonts.manrope(
          color: secondaryText,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        labelLarge: GoogleFonts.manrope(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),

      // Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: cardBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderColor, width: 1.2),
        ),
        titleTextStyle: GoogleFonts.manrope(
          color: primaryText,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        contentTextStyle: GoogleFonts.manrope(
          color: secondaryText,
          fontSize: 13.5,
          height: 1.45,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      ),

      // Date Picker Theme
      datePickerTheme: DatePickerThemeData(
        backgroundColor: cardBackground,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: primaryTeal,
        headerForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderColor),
        ),
        headerHeadlineStyle: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w800),
        dayStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13),
        yearStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13),
        todayBorder: const BorderSide(color: primaryTeal, width: 1.5),
        todayForegroundColor: const WidgetStatePropertyAll(primaryTeal),
      ),

      // Bottom Sheet Theme
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // Standard Button Style
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryTeal,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.manrope(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
          elevation: 0,
        ),
      ),

      // Standard Input Field Style
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBackground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: primaryTeal, width: 1.5),
        ),
        labelStyle: GoogleFonts.manrope(
          color: secondaryText,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: GoogleFonts.manrope(
          color: primaryTeal,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: GoogleFonts.manrope(
          color: const Color(0xFF9AA7AD),
          fontSize: 13.5,
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
        seedColor: brightTeal,
        primary: brightTeal,
        secondary: glowTeal,
        brightness: Brightness.dark,
        surface: cardBackgroundDark,
      ),
      scaffoldBackgroundColor: scaffoldBackgroundDark,
      cardColor: cardBackgroundDark,
      dividerColor: borderColorDark,
      
      textTheme: GoogleFonts.manropeTextTheme(ThemeData.dark().textTheme).copyWith(
        headlineLarge: GoogleFonts.manrope(
          color: primaryTextDark,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineMedium: GoogleFonts.manrope(
          color: primaryTextDark,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: GoogleFonts.manrope(
          color: primaryTextDark,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        titleMedium: GoogleFonts.manrope(
          color: primaryTextDark,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: GoogleFonts.manrope(
          color: primaryTextDark,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: GoogleFonts.manrope(
          color: secondaryTextDark,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        labelLarge: GoogleFonts.manrope(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),

      // Dark Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: cardBackgroundDark,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderColorDark, width: 1.2),
        ),
        titleTextStyle: GoogleFonts.manrope(
          color: primaryTextDark,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        contentTextStyle: GoogleFonts.manrope(
          color: secondaryTextDark,
          fontSize: 13.5,
          height: 1.45,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      ),

      // Dark Date Picker Theme
      datePickerTheme: DatePickerThemeData(
        backgroundColor: cardBackgroundDark,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: brightTeal,
        headerForegroundColor: const Color(0xFF06201D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderColorDark),
        ),
        headerHeadlineStyle: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF06201D)),
        dayStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13, color: primaryTextDark),
        yearStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13, color: primaryTextDark),
        todayBorder: const BorderSide(color: brightTeal, width: 1.5),
        todayForegroundColor: const WidgetStatePropertyAll(brightTeal),
      ),

      // Dark Bottom Sheet Theme
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brightTeal,
          foregroundColor: const Color(0xFF06201D),
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.manrope(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
          ),
          elevation: 0,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: softBackgroundDark,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderColorDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderColorDark),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: brightTeal, width: 1.5),
        ),
        labelStyle: GoogleFonts.manrope(
          color: secondaryTextDark,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: GoogleFonts.manrope(
          color: brightTeal,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: GoogleFonts.manrope(
          color: const Color(0xFF64748B),
          fontSize: 13.5,
        ),
      ),
    );
  }
}
