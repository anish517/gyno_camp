import 'package:flutter/material.dart';

class AppTheme {
  // WFWSN Brand Colors (from official circular insignia logo)
  static const Color brandPurple = Color(0xFF30026E); // Deep Royal Violet / Indigo
  static const Color brandPurpleDark = Color(0xFF240046); // Executive dark violet
  static const Color brandMagenta = Color(0xFF81005D); // Rich Wine / Magenta
  static const Color brandMagentaDark = Color(0xFF6B0056); // Deep wine
  static const Color brandPink = Color(0xFFBE185D); // Vibrant dark pink
  static const Color brandPinkDark = Color(0xFF9D174D); // Deep rich pink
  static const Color brandPurpleLight = Color(0xFFF5F3FF); // Soft violet tint
  static const Color brandMagentaLight = Color(0xFFFDF2F8); // Soft rose tint
  static const Color brandPurpleBorder = Color(0xFFE9D5FF); // Light violet border

  // Brand aliases (migrated to WFWSN official brand purple palette)
  static const Color primaryTeal = brandPurple; // Alias for backward compatibility
  static const Color primaryDark = brandPurpleDark; // Alias
  static const Color primaryLight = brandPurpleLight; // Soft violet tint
  static const Color accentCyan = brandMagenta; // Brand Magenta
  static const Color successGreen = Color(0xFF16A34A);
  static const Color warningAmber = Color(0xFFD97706);
  static const Color dangerRose = Color(0xFFE11D48);

  // Neutrals
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color cardSurfaceLight = Colors.white;
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);

  // Brand AppBar Decorations
  static Widget get brandAppBarFlexibleSpace => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          gradient: LinearGradient(
            colors: [
              brandPurple.withValues(alpha: 0.08),
              brandMagenta.withValues(alpha: 0.05),
              const Color(0xFFF8FAFC),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      );

  static PreferredSizeWidget get brandAppBarBottomLine => PreferredSize(
        preferredSize: const Size.fromHeight(2.5),
        child: Container(
          height: 2.5,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF81005D), // WFWSN deep magenta/pink from logo
                Color(0xFFBE185D), // Vibrant dark pink
                Color(0xFF9D174D), // Deep rich pink
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
      );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandPurple,
        primary: brandPurple,
        onPrimary: Colors.white,
        secondary: brandMagenta,
        surface: cardSurfaceLight,
        error: dangerRose,
      ),
      scaffoldBackgroundColor: backgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF1E0A38),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Color(0xFF1E0A38)),
        actionsIconTheme: IconThemeData(color: Color(0xFF475569)),
        titleTextStyle: TextStyle(
          color: Color(0xFF1E0A38),
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardSurfaceLight,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderLight),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brandPurple,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandPurple,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderLight),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: brandPurple, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: dangerRose),
        ),
      ),
    );
  }
}
