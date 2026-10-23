import 'package:flutter/material.dart';

/// Design tokens + Material theme, in light and dark.
///
/// Light, neutral surfaces with a single blue accent for actions. Status colours are
/// only used for status (present / late / error), never decoration. Camera screens use
/// the dark `ink` palette in both modes so the video stays the focus.
///
/// Colours are getters that read [isDark], so flipping the mode and rebuilding the
/// widget tree (see `Appearance.toggle`) recolours every screen without restarting.
class AppTheme {
  static bool isDark = false;

  static Color _p(int light, int dark) => Color(isDark ? dark : light);

  // ── Neutrals ──────────────────────────────────────────
  static Color get background    => _p(0xFFF5F7FA, 0xFF0E1117);
  static Color get surface       => _p(0xFFFFFFFF, 0xFF161B22);
  static Color get surfaceMuted  => _p(0xFFF9FAFB, 0xFF1C222B);
  static Color get border        => _p(0xFFE5E7EB, 0xFF2A313C);
  static Color get borderStrong  => _p(0xFFD0D5DD, 0xFF3A4250);
  static Color get textPrimary   => _p(0xFF111827, 0xFFF0F3F6);
  static Color get textSecondary => _p(0xFF4B5563, 0xFFB3BCC8);
  static Color get textMuted     => _p(0xFF9CA3AF, 0xFF7D8796);
  static Color get neutralSoft   => _p(0xFFF2F4F7, 0xFF222934);

  // ── Brand ─────────────────────────────────────────────
  static Color get primary       => _p(0xFF2563EB, 0xFF4C8DF6);
  static Color get primaryDark   => _p(0xFF1E3A8A, 0xFF1E3A8A);
  static Color get primarySoft   => _p(0xFFEFF4FF, 0xFF15233F);

  // ── Status ────────────────────────────────────────────
  static Color get success       => _p(0xFF16A34A, 0xFF3FB86B);
  static Color get successSoft   => _p(0xFFECFDF3, 0xFF12291C);
  static Color get warning       => _p(0xFFD97706, 0xFFE9A23B);
  static Color get warningSoft   => _p(0xFFFFFAEB, 0xFF2D2312);
  static Color get danger        => _p(0xFFDC2626, 0xFFEF5350);
  static Color get dangerSoft    => _p(0xFFFEF3F2, 0xFF2E1517);
  static Color get teal          => _p(0xFF0D9488, 0xFF2DD4BF);  // work from home
  static Color get tealSoft      => _p(0xFFE6FAF7, 0xFF0F2A27);

  // ── Chart series (validated for colour-blind separation on both surfaces) ──
  static Color get chartOnTime   => _p(0xFF2A78D6, 0xFF3987E5);
  static Color get chartLate     => _p(0xFFEB6834, 0xFFD95926);
  static Color get chartGrid     => _p(0xFFEEF0F3, 0xFF232A33);

  // ── Camera screens (same in both modes) ───────────────
  static const Color ink         = Color(0xFF0B1220);
  static const Color inkSoft     = Color(0xFF1F2937);

  // ── Shape & spacing ───────────────────────────────────
  static const double radius   = 12;
  static const double radiusSm = 8;
  static const double gap      = 16;

  static const String font = 'Inter';

  /// Digits that don't jiggle when a clock ticks.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static TextStyle get h1 => TextStyle(
      fontSize: 28, fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.6);
  static TextStyle get h2 => TextStyle(
      fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary, letterSpacing: -0.3);
  static TextStyle get h3 => TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary);
  static TextStyle get body => TextStyle(fontSize: 14, color: textPrimary, height: 1.45);
  static TextStyle get muted => TextStyle(fontSize: 13, color: textSecondary, height: 1.45);
  static TextStyle get label => TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary, letterSpacing: 0.2);
  static TextStyle get overline => TextStyle(
      fontSize: 11, fontWeight: FontWeight.w600, color: textMuted, letterSpacing: 0.8);

  static ThemeData get theme {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: isDark ? Brightness.dark : Brightness.light,
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
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      splashFactory: InkSparkle.splashFactory,
      textTheme: TextTheme(
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
        hintStyle: TextStyle(color: textMuted, fontSize: 14),
        labelStyle: TextStyle(color: textSecondary, fontSize: 14),
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
          side: BorderSide(color: borderStrong),
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
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: TextStyle(
            fontFamily: font, fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: primary,
        headerForegroundColor: Colors.white,
      ),
      timePickerTheme: TimePickerThemeData(backgroundColor: surface),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          side: BorderSide(color: border),
        ),
        textStyle: TextStyle(fontFamily: font, fontSize: 14, color: textPrimary),
      ),
      listTileTheme: ListTileThemeData(textColor: textPrimary, iconColor: textSecondary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : textMuted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : border),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2A313C) : const Color(0xFF111827),
        contentTextStyle: const TextStyle(fontFamily: font, fontSize: 14, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm + 2)),
        width: 460,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A313C) : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontFamily: font, fontSize: 12, color: Colors.white),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary, linearTrackColor: border, circularTrackColor: Colors.transparent),
    );
  }
}
