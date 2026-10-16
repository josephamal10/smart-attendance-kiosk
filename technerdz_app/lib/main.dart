import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera_windows/camera_windows.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';
import 'theme/appearance.dart';
import 'theme/branding.dart';
import 'screens/admin_login_screen.dart';
import 'screens/lock_screen.dart';

// Global navigator key — used by ApiService for session expiry redirect
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Where the app starts and returns to: the clock lock screen on the kiosk PC, admin sign-in in a
/// browser (the web build is the admin dashboard for HR's own computers — no camera there).
Widget homeScreen() => kIsWeb ? const AdminLoginScreen() : const LockScreen();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Appearance.load();
  unawaited(Branding.load()); // company name for the lock screen; doesn't block start-up
  // Native camera plugin only on Windows (the web build is used for UI previews/screenshots)
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) CameraWindows.registerWith();
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatefulWidget {
  const AttendanceApp({super.key});

  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  @override
  void initState() {
    super.initState();
    Appearance.dark.addListener(_onModeChanged);
  }

  @override
  void dispose() {
    Appearance.dark.removeListener(_onModeChanged);
    super.dispose();
  }

  void _onModeChanged() {
    setState(() {});
    // Repaint every screen (including ones under the current page) in the new colours
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Appearance.rebuildAll(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NanoNino Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      navigatorKey: navigatorKey,
      // Wrap the Navigator itself so taps on *every* screen reset the idle timer
      // (wrapping only `home` missed every screen pushed on top of it).
      builder: (context, child) => IdleDetector(child: child!),
      home: homeScreen(),
    );
  }
}

class IdleDetector extends StatefulWidget {
  final Widget child;
  const IdleDetector({super.key, required this.child});

  @override
  State<IdleDetector> createState() => _IdleDetectorState();
}

class _IdleDetectorState extends State<IdleDetector> {
  Timer? _timer;
  // The kiosk is a shared machine: if an admin walks away from the dashboard,
  // sign them out and go back to the check-in screen. A personal browser can wait longer.
  static const _timeout = kIsWeb ? Duration(minutes: 30) : Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _reset();
  }

  bool _onKey(KeyEvent _) {
    _reset();
    return false; // don't swallow the key
  }

  void _reset() {
    _timer?.cancel();
    _timer = Timer(_timeout, _onIdle);
  }

  void _onIdle() {
    if (ApiService.isLoggedIn) {
      ApiService.clearSession();
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => homeScreen()),
        (_) => false,
      );
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _reset(),
      onPointerMove: (_) => _reset(),
      onPointerUp:   (_) => _reset(),
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}
