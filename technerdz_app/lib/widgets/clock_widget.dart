import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

/// Live clock. `large` is the kiosk welcome screen; otherwise a compact one-liner.
class ClockWidget extends StatefulWidget {
  final bool large;
  final double scale; // shrinks the large clock to fit narrower spaces
  const ClockWidget({super.key, this.large = true, this.scale = 1.0});
  @override
  State<ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<ClockWidget> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.large) {
      return Text(DateFormat('h:mm a').format(_now),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary, fontFeatures: AppTheme.tabular));
    }

    final k = widget.scale;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(DateFormat('h:mm').format(_now),
              style: TextStyle(fontSize: 120 * k, fontWeight: FontWeight.w600,
                  height: 1, letterSpacing: -5 * k, color: AppTheme.textPrimary,
                  fontFeatures: AppTheme.tabular)),
          SizedBox(width: 14 * k),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(DateFormat('a').format(_now),
                style: TextStyle(fontSize: 26 * k, fontWeight: FontWeight.w600, color: AppTheme.primary)),
            Text(DateFormat('ss').format(_now),
                style: TextStyle(fontSize: 20 * k, fontWeight: FontWeight.w500,
                    color: AppTheme.textMuted, fontFeatures: AppTheme.tabular)),
          ]),
        ],
      ),
      SizedBox(height: 16 * k),
      Text(DateFormat('EEEE, d MMMM y').format(_now),
          style: TextStyle(fontSize: (20 * k).clamp(14, 20).toDouble(), fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary)),
    ]);
  }
}
