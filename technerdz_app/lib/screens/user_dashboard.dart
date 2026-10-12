import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/employee.dart';
import '../widgets/clock_widget.dart';
import 'lock_screen.dart';
import 'face_register_screen.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});
  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  AttendanceLog? _log;
  bool _loading     = true;
  bool _faceRegistered = false;

  // Idle timeout
  Timer? _idleTimer;
  static const _idleLimit = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _loadLog();
    _checkFaceStatus();
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleLimit, _goToLockScreen);
  }

  void _goToLockScreen() {
    if (!mounted) return;
    ApiService.clearSession();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LockScreen()),
      (_) => false,
    );
  }

  Future<void> _loadLog() async {
    setState(() => _loading = true);
    try {
      final log = await ApiService.getTodayLog(ApiService.employeeId!);
      setState(() => _log = log);
    } catch (_) {
      setState(() => _log = null);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _checkFaceStatus() async {
    try {
      final res = await ApiService.getFaceCount(ApiService.employeeId!);
      setState(() => _faceRegistered = (res['total'] ?? 0) > 0);
    } catch (_) {}
  }

  void _logout() {
    _idleTimer?.cancel();
    ApiService.clearSession();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LockScreen()),
      (_) => false,
    );
  }

  String _fmt(DateTime? dt) =>
      dt != null ? DateFormat('hh:mm:ss a').format(dt) : '--:--:--';

  void _openFaceRegister() {
    _idleTimer?.cancel();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FaceRegisterScreen()),
    ).then((_) {
      _checkFaceStatus();
      _resetIdleTimer();
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Reset idle timer on any pointer (mouse/touch) event
      onPointerDown: (_) => _resetIdleTimer(),
      onPointerMove: (_) => _resetIdleTimer(),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (_) => _resetIdleTimer(),
        child: Scaffold(
          backgroundColor: AppTheme.background,
          body: Row(
            children: [
              // ── Sidebar ──────────────────────────────────
              Container(
                width: 220,
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(right: BorderSide(color: AppTheme.border)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    const Text('TECHNERDZ',
                      style: TextStyle(fontSize: 11, letterSpacing: 6,
                        color: AppTheme.accentGrey, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 16),
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AppTheme.card,
                      child: Text(
                        (ApiService.name ?? 'U')[0].toUpperCase(),
                        style: const TextStyle(fontSize: 28,
                          color: AppTheme.textPrimary, fontWeight: FontWeight.w300),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(ApiService.name ?? '',
                      style: const TextStyle(fontSize: 15,
                        color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    const Text('EMPLOYEE',
                      style: TextStyle(fontSize: 10, letterSpacing: 3,
                        color: AppTheme.accentGrey),
                    ),
                    const SizedBox(height: 16),

                    // Face status badge
                    if (_faceRegistered)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.success.withOpacity(0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, color: AppTheme.success, size: 12),
                            SizedBox(width: 4),
                            Text('Face Registered',
                              style: TextStyle(color: AppTheme.success,
                                fontSize: 10, letterSpacing: 1)),
                          ],
                        ),
                      ),

                    const SizedBox(height: 32),
                    const Divider(),
                    const Spacer(),

                    // Face register / update button
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _faceRegistered
                              ? AppTheme.accent : AppTheme.accentGrey,
                          side: BorderSide(
                            color: _faceRegistered
                                ? AppTheme.accent : AppTheme.border),
                          minimumSize: const Size(double.infinity, 44),
                        ),
                        icon: Icon(_faceRegistered ? Icons.update : Icons.face,
                          size: 16),
                        label: Text(
                          _faceRegistered ? 'Update Face' : 'Register Face',
                          style: const TextStyle(fontSize: 12, letterSpacing: 1)),
                        onPressed: _openFaceRegister,
                      ),
                    ),

                    // Logout
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          side: const BorderSide(color: AppTheme.error),
                          minimumSize: const Size(double.infinity, 44),
                        ),
                        icon: const Icon(Icons.logout, size: 16),
                        label: const Text('Sign Out',
                          style: TextStyle(fontSize: 12, letterSpacing: 1)),
                        onPressed: _logout,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Main Content ─────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Good ${_greeting()}, ${ApiService.name?.split(' ').first ?? ''}!',
                                style: const TextStyle(fontSize: 28,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              Text(DateFormat('EEEE, MMMM d yyyy').format(DateTime.now()),
                                style: const TextStyle(
                                  color: AppTheme.accentGrey, fontSize: 14),
                              ),
                            ],
                          ),
                          const ClockWidget(),
                        ],
                      ),

                      const SizedBox(height: 48),

                      if (_loading)
                        const Center(child: CircularProgressIndicator(
                          color: AppTheme.accent))
                      else ...[
                        Row(
                          children: [
                            _AttendanceCard(
                              label: 'CHECK IN',
                              time: _fmt(_log?.inTime),
                              icon: Icons.login,
                              active: _log?.inTime != null,
                            ),
                            const SizedBox(width: 24),
                            _AttendanceCard(
                              label: 'CHECK OUT',
                              time: _fmt(_log?.outTime),
                              icon: Icons.logout,
                              active: _log?.outTime != null,
                            ),
                            const SizedBox(width: 24),
                            _StatusCard(log: _log),
                          ],
                        ),

                        const SizedBox(height: 48),

                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppTheme.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                color: AppTheme.accentGrey, size: 20),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  _log == null
                                    ? 'You have not checked in today. Please go to the webcam terminal to mark your attendance.'
                                    : _log!.outTime == null
                                      ? 'You are currently checked in. Remember to check out at the end of your shift.'
                                      : 'Your attendance for today is complete. See you tomorrow!',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 14, height: 1.6),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        TextButton.icon(
                          onPressed: () { _resetIdleTimer(); _loadLog(); },
                          icon: const Icon(Icons.refresh, size: 16,
                            color: AppTheme.accentGrey),
                          label: const Text('Refresh',
                            style: TextStyle(color: AppTheme.accentGrey,
                              fontSize: 13)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Morning';
    if (h < 17) return 'Afternoon';
    return 'Evening';
  }
}

// ── Attendance Card ───────────────────────────────────────
class _AttendanceCard extends StatelessWidget {
  final String label, time;
  final IconData icon;
  final bool active;
  const _AttendanceCard({
    required this.label, required this.time,
    required this.icon,  required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? AppTheme.accent : AppTheme.border,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16,
                  color: active ? AppTheme.accent : AppTheme.accentGrey),
                const SizedBox(width: 8),
                Text(label,
                  style: TextStyle(
                    fontSize: 10, letterSpacing: 2,
                    color: active ? AppTheme.accent : AppTheme.accentGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(time,
              style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.w300,
                color: active ? AppTheme.textPrimary : AppTheme.accentGrey,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status Card ───────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final AttendanceLog? log;
  const _StatusCard({this.log});

  @override
  Widget build(BuildContext context) {
    String status  = 'NOT MARKED';
    Color  color   = AppTheme.accentGrey;
    IconData icon  = Icons.radio_button_unchecked;

    if (log != null) {
      if (log!.outTime != null) {
        status = 'COMPLETE'; color = AppTheme.success;
        icon   = Icons.check_circle_outline;
      } else if (log!.inTime != null) {
        status = 'CHECKED IN'; color = Colors.amber;
        icon   = Icons.timelapse;
      }
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.assignment_turned_in_outlined,
                size: 16, color: AppTheme.accentGrey),
              const SizedBox(width: 8),
              const Text('STATUS',
                style: TextStyle(fontSize: 10, letterSpacing: 2,
                  color: AppTheme.accentGrey, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(status, style: TextStyle(fontSize: 18,
                fontWeight: FontWeight.w500, color: color, letterSpacing: 1)),
            ]),
          ],
        ),
      ),
    );
  }
}
