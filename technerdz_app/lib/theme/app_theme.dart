import 'package:flutter/material.dart';

/// Design tokens + Material theme.
///
/// Light, neutral surfaces with a single blue accent for actions. Status colours are
/// only used for status (present / late / error), never decoration. Camera screens use
/// the dark `ink` palette so the video stays the focus.
class AppTheme {
  // ── Neutrals ──────────────────────────────────────────
  static const Color background    = Color(0xFFF5F7FA);
  static const Color surface       = Color(0xFFFFFFFF);
  static const Color surfaceMuted  = Color(0xFFF9FAFB);
  static const Color border        = Color(0xFFE5E7EB);
  static const Color borderStrong  = Color(0xFFD0D5DD);
  static const Color textPrimary   = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF4B5563);
  static const Color textMuted     = Color(0xFF9CA3AF);

  // ── Brand ─────────────────────────────────────────────
  static const Color primary       = Color(0xFF2563EB);
  static const Color primaryDark   = Color(0xFF1E3A8A);
  static const Color primarySoft   = Color(0xFFEFF4FF);

  // ── Status ────────────────────────────────────────────
  static const Color success       = Color(0xFF16A34A);
  static const Color successSoft   = Color(0xFFECFDF3);
  static const Color warning       = Color(0xFFD97706);
  static const Color warningSoft   = Color(0xFFFFFAEB);
  static const Color danger        = Color(0xFFDC2626);
  static const Color dangerSoft    = Color(0xFFFEF3F2);

  // ── Camera screens ────────────────────────────────────
  static const Color ink           = Color(0xFF0B1220);
  static const Color inkSoft       = Color(0xFF1F2937);

  // ── Shape & spacing ───────────────────────────────────
  static const double radius   = 12;
  static const double radiusSm = 8;
  static const double gap      = 16;

  static const String font = 'Inter';

  /// Digits that don't jiggle when a clock ticks.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static TextStyle get h1 => const TextStyle(
      fontSize: 28, fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.6);
  static TextStyle get h2 => const TextStyle(
      fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary, letterSpacing: -0.3);
  static TextStyle get h3 => const TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary);
  static TextStyle get body => const TextStyle(fontSize: 14, color: textPrimary, height: 1.45);
  static TextStyle get muted => const TextStyle(fontSize: 13, color: textSecondary, height: 1.45);
  static TextStyle get label => const TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary, letterSpacing: 0.2);
  static TextStyle get overline => const TextStyle(
      fontSize: 11, fontWeight: FontWeight.w600, color: textMuted, letterSpacing: 0.8);

  static ThemeData get theme {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      error: danger,
      outline: borderStrong,
      outlineVariant: border,
    );

    final roundedSm = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm + 2));
    const buttonText = TextStyle(fontFamily: font, fontSize: 14, fontWeight: FontWeight.w600);

    OutlineInputBorder outline(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      fontFamily: font,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        bodyLarge:  TextStyle(fontSize: 15, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: textPrimary),
        bodySmall:  TextStyle(fontSize: 12, color: textSecondary),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
        labelLarge: buttonText,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hoverColor: surfaceMuted,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: const TextStyle(color: textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
        border: outline(borderStrong),
        enabledBorder: outline(borderStrong),
        focusedBorder: outline(primary, 1.6),
        errorBorder: outline(danger),
        focusedErrorBorder: outline(danger, 1.6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: primary.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: roundedSm,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: surface,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: const BorderSide(color: borderStrong),
          shape: roundedSm,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          shape: roundedSm,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: textSecondary),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(
            fontFamily: font, fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          side: const BorderSide(color: border),
        ),
        textStyle: const TextStyle(fontFamily: font, fontSize: 14, color: textPrimary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary,
        contentTextStyle: const TextStyle(fontFamily: font, fontSize: 14, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm + 2)),
        width: 420,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: textPrimary, borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontFamily: font, fontSize: 12, color: Colors.white),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary, linearTrackColor: border, circularTrackColor: Colors.transparent),
    );
  }
}
