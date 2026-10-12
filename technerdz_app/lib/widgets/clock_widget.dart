import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

/// Live clock. `large` is the kiosk welcome screen; otherwise a compact one-liner.
class ClockWidget extends StatefulWidget {
  final bool large;
  const ClockWidget({super.key, this.large = true});
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

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(DateFormat('h:mm').format(_now),
              style: const TextStyle(fontSize: 120, fontWeight: FontWeight.w600,
                  height: 1, letterSpacing: -5, color: AppTheme.textPrimary,
                  fontFeatures: AppTheme.tabular)),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(DateFormat('a').format(_now),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: AppTheme.primary)),
            Text(DateFormat('ss').format(_now),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500,
                    color: AppTheme.textMuted, fontFeatures: AppTheme.tabular)),
          ]),
        ],
      ),
      const SizedBox(height: 16),
      Text(DateFormat('EEEE, d MMMM y').format(_now),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: AppTheme.textSecondary)),
    ]);
  }
}
