import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

class ClockWidget extends StatefulWidget {
  const ClockWidget({super.key});
  @override
  State<ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<ClockWidget> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
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
    final time = DateFormat('HH:mm').format(_now);
    final secs = DateFormat('ss').format(_now);
    final date = DateFormat('MMMM d, yyyy').format(_now);
    final day  = DateFormat('EEEE').format(_now).toUpperCase();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Time
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(time, style: Theme.of(context).textTheme.displayLarge),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(' :$secs',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  color: AppTheme.accentGrey,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Day
        Text(day,
          style: const TextStyle(
            fontSize: 13,
            letterSpacing: 6,
            color: AppTheme.accentGrey,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 4),
        // Date
        Text(date,
          style: const TextStyle(
            fontSize: 16,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w300,
          ),
        ),
      ],
    );
  }
}