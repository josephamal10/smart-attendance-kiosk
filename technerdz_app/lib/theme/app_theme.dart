import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colors
  static const Color background   = Color(0xFF0A0A0A);
  static const Color surface      = Color(0xFF1A1A1A);
  static const Color card         = Color(0xFF222222);
  static const Color border       = Color(0xFF333333);
  static const Color accent       = Color(0xFFFFFFFF);
  static const Color accentGrey   = Color(0xFF888888);
  static const Color textPrimary  = Color(0xFFFFFFFF);
  static const Color textSecondary= Color(0xFFAAAAAA);
  static const Color success      = Color(0xFF4CAF50);
  static const Color error        = Color(0xFFCF6679);
  static const Color divider      = Color(0xFF2A2A2A);

  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      surface: surface,
      primary: accent,
      secondary: accentGrey,
      error: error,
    ),
    textTheme: GoogleFonts.interTextTheme(
      const TextTheme(
        displayLarge:  TextStyle(color: textPrimary,   fontSize: 72, fontWeight: FontWeight.w200, letterSpacing: -2),
        displayMedium: TextStyle(color: textPrimary,   fontSize: 48, fontWeight: FontWeight.w300, letterSpacing: -1),
        headlineLarge: TextStyle(color: textPrimary,   fontSize: 32, fontWeight: FontWeight.w600),
        headlineMedium:TextStyle(color: textPrimary,   fontSize: 24, fontWeight: FontWeight.w500),
        titleLarge:    TextStyle(color: textPrimary,   fontSize: 18, fontWeight: FontWeight.w500),
        bodyLarge:     TextStyle(color: textPrimary,   fontSize: 16),
        bodyMedium:    TextStyle(color: textSecondary, fontSize: 14),
        labelLarge:    TextStyle(color: textPrimary,   fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1.2),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: accentGrey),
      hintStyle: const TextStyle(color: accentGrey),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: background,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1.2),
      ),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: divider, thickness: 1),
  );
}