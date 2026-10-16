import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/branding.dart';

/// Small shared building blocks so every screen looks like the same product.

enum Tone { neutral, primary, success, warning, danger }

extension ToneColors on Tone {
  Color get fg => switch (this) {
        Tone.neutral => AppTheme.textSecondary,
        Tone.primary => AppTheme.primary,
        Tone.success => AppTheme.success,
        Tone.warning => AppTheme.warning,
        Tone.danger  => AppTheme.danger,
      };
  Color get bg => switch (this) {
        Tone.neutral => AppTheme.neutralSoft,
        Tone.primary => AppTheme.primarySoft,
        Tone.success => AppTheme.successSoft,
        Tone.warning => AppTheme.warningSoft,
        Tone.danger  => AppTheme.dangerSoft,
      };
}

/// Logo tile + optional wordmark.
class BrandMark extends StatelessWidget {
  final double size;
  final bool showName;
  final bool onDark;
  final String? subtitle;
  const BrandMark({super.key, this.size = 36, this.showName = true, this.onDark = false, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: size, height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: onDark
            ? null
            : LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [const Color(0xFF3B82F6), AppTheme.primaryDark]),
        color: onDark ? Colors.white.withValues(alpha: 0.14) : null,
        border: onDark ? Border.all(color: Colors.white.withValues(alpha: 0.25)) : null,
      ),
      // Monogram of the company name, e.g. "N" for NanoNino
      child: Center(
        child: ValueListenableBuilder<String>(
          valueListenable: Branding.name,
          builder: (_, name, __) => Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(color: Colors.white, fontSize: size * 0.52, fontWeight: FontWeight.w700, height: 1)),
        ),
      ),
    );
    if (!showName) return tile;
    final nameColor = onDark ? Colors.white : AppTheme.textPrimary;
    final subColor  = onDark ? Colors.white.withValues(alpha: 0.7) : AppTheme.textMuted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      tile,
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        ValueListenableBuilder<String>(
          valueListenable: Branding.name,
          builder: (_, name, __) => Text(name.toUpperCase(), style: TextStyle(
              fontSize: size * 0.4, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: nameColor)),
        ),
        if (subtitle != null)
          Text(subtitle!, style: TextStyle(fontSize: 12, color: subColor, fontWeight: FontWeight.w500)),
      ]),
    ]);
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        clipBehavior: Clip.antiAlias, // so table header backgrounds follow the rounded corners
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [
            BoxShadow(color: Color(0x0A101828), blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
        child: child,
      );
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Tone tone;
  final bool dot;
  const StatusBadge(this.label, {super.key, this.tone = Tone.neutral, this.dot = true});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 6, height: 6,
                decoration: BoxDecoration(color: tone.fg, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tone.fg)),
        ]),
      );
}

class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;
  const InitialsAvatar(this.name, {super.key, this.size = 36});

  static const _palette = [
    Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFF0891B2),
    Color(0xFFDB2777), Color(0xFFEA580C), Color(0xFF059669),
  ];

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = _palette[name.hashCode.abs() % _palette.length];
    return Container(
      width: size, height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Text(_initials, style: TextStyle(
          fontSize: size * 0.38, fontWeight: FontWeight.w600, color: c)),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Tone tone;
  final String? caption;
  const StatCard({super.key, required this.label, required this.value,
      required this.icon, this.tone = Tone.primary, this.caption});

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppTheme.muted),
              const SizedBox(height: 10),
              Text(value, style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w700, color: AppTheme.textPrimary,
                  letterSpacing: -0.8, fontFeatures: AppTheme.tabular)),
              if (caption != null) ...[
                const SizedBox(height: 4),
                Text(caption!, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ],
            ]),
          ),
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: tone.fg, size: 20),
          ),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const EmptyState({super.key, required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(color: AppTheme.surfaceMuted, shape: BoxShape.circle),
            child: Icon(icon, color: AppTheme.textMuted, size: 26),
          ),
          const SizedBox(height: 14),
          Text(title, style: AppTheme.h3),
          const SizedBox(height: 4),
          Text(message, style: AppTheme.muted, textAlign: TextAlign.center),
        ]),
      );
}

/// Inline message box for forms (errors, success).
class InfoBanner extends StatelessWidget {
  final String text;
  final Tone tone;
  const InfoBanner(this.text, {super.key, this.tone = Tone.danger});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: tone.fg.withValues(alpha: 0.25)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(tone == Tone.success ? Icons.check_circle_outline : Icons.error_outline,
              size: 18, color: tone.fg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: tone.fg, height: 1.4))),
        ]),
      );
}

/// Column definition for [DataCard].
class Col {
  final String label;
  final int flex;
  final bool alignEnd;
  const Col(this.label, {this.flex = 1, this.alignEnd = false});
}

/// Card with a header row and simple flex-column rows. Lighter and more controllable
/// than Material's DataTable for a handful of columns.
class DataCard extends StatelessWidget {
  final List<Col> columns;
  final List<List<Widget>> rows;
  final Widget? empty;
  final Widget? header;
  const DataCard({super.key, required this.columns, required this.rows, this.empty, this.header});

  Widget _cell(Col c, Widget child) => Expanded(
        flex: c.flex,
        child: Align(alignment: c.alignEnd ? Alignment.centerRight : Alignment.centerLeft, child: child),
      );

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (header != null) Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 14), child: header),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted,
            border: Border(
              top: header == null ? BorderSide.none : BorderSide(color: AppTheme.border),
              bottom: BorderSide(color: AppTheme.border),
            ),
          ),
          child: Row(children: [
            for (final c in columns) _cell(c, Text(c.label.toUpperCase(), style: AppTheme.overline)),
          ]),
        ),
        if (rows.isEmpty && empty != null) empty!,
        for (var i = 0; i < rows.length; i++)
          Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              border: i == rows.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(children: [
              for (var j = 0; j < columns.length; j++) _cell(columns[j], rows[i][j]),
            ]),
          ),
      ]),
    );
  }
}

/// Avatar + name (+ secondary line) used in tables.
class PersonCell extends StatelessWidget {
  final String name;
  final String? secondary;
  const PersonCell(this.name, {super.key, this.secondary});

  @override
  Widget build(BuildContext context) => Row(children: [
        InitialsAvatar(name, size: 34),
        const SizedBox(width: 12),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            if (secondary != null)
              Text(secondary!, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ]),
        ),
      ]);
}

/// Dark translucent pill used over the camera feed.
class CameraPill extends StatelessWidget {
  final Widget? leading;
  final String text;
  final Color? color;
  const CameraPill(this.text, {super.key, this.leading, this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: (color ?? Colors.black).withValues(alpha: color == null ? 0.55 : 0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Flexible(child: Text(text, style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))),
        ]),
      );
}

/// "8h 05m"
String formatMinutes(int minutes) => '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';

/// Late 16m · Left early · Half day · Missed check-out, as compact badges.
class FlagBadges extends StatelessWidget {
  final List<String> flags;
  final int lateMinutes;
  final int earlyMinutes;
  /// Shown when there are no flags (e.g. an "On time" badge); null shows nothing.
  final Widget? whenClean;
  const FlagBadges({super.key, required this.flags, this.lateMinutes = 0, this.earlyMinutes = 0,
      this.whenClean});

  static (String, Tone) describe(String flag, int late, int early) => switch (flag) {
        'late'            => ('Late ${late}m', Tone.warning),
        'early_leave'     => ('Left early ${early}m', Tone.warning),
        'half_day'        => ('Half day', Tone.danger),
        'missed_checkout' => ('Missed check-out', Tone.danger),
        _                 => (flag, Tone.neutral),
      };

  @override
  Widget build(BuildContext context) {
    if (flags.isEmpty) return whenClean ?? const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final f in flags)
        Builder(builder: (_) {
          final (label, tone) = describe(f, lateMinutes, earlyMinutes);
          return StatusBadge(label, tone: tone);
        }),
    ]);
  }
}

/// How each day in the register / profile calendar is shown: colour + short code + label.
/// Codes and labels make sure status is never shown by colour alone.
class DayStatus {
  static (Color bg, Color fg, String code, String label) of(String status) => switch (status) {
        'present'  => (AppTheme.successSoft, AppTheme.success, 'P', 'Present'),
        'late'     => (AppTheme.warningSoft, AppTheme.warning, 'L', 'Late'),
        'half_day' => (AppTheme.dangerSoft, AppTheme.danger, '½', 'Half day'),
        'absent'   => (AppTheme.dangerSoft, AppTheme.danger, 'A', 'Absent'),
        'leave'    => (AppTheme.primarySoft, AppTheme.primary, 'LV', 'Leave'),
        'holiday'  => (AppTheme.neutralSoft, AppTheme.textSecondary, 'H', 'Holiday'),
        'off'      => (AppTheme.surfaceMuted, AppTheme.textMuted, '', 'Day off'),
        _          => (Colors.transparent, AppTheme.textMuted, '', 'Upcoming'),
      };

  static const legendOrder = ['present', 'late', 'half_day', 'absent', 'leave', 'holiday', 'off'];
}

class DayLegend extends StatelessWidget {
  const DayLegend({super.key});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 14, runSpacing: 6, children: [
        for (final s in DayStatus.legendOrder)
          Builder(builder: (_) {
            final (bg, fg, code, label) = DayStatus.of(s);
            return Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 22, height: 18, alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: fg.withValues(alpha: 0.25))),
                child: Text(code, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
              ),
              const SizedBox(width: 6),
              Text(label, style: AppTheme.muted),
            ]);
          }),
      ]);
}
