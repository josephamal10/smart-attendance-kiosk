import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera_windows/camera_windows.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';
import 'screens/kiosk_screen.dart';

// Global navigator key — used by ApiService for session expiry redirect
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Native camera plugin only on Windows (the web build is used for UI previews/screenshots)
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) CameraWindows.registerWith();
  runApp(const TechnerdzApp());
}

class TechnerdzApp extends StatelessWidget {
  const TechnerdzApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TECHNERDZ Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      navigatorKey: navigatorKey,
      // Wrap the Navigator itself so taps on *every* screen reset the idle timer
      // (wrapping only `home` missed every screen pushed on top of it).
      builder: (context, child) => IdleDetector(child: child!),
      home: const KioskScreen(),
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
  // sign them out and go back to the check-in screen.
  static const _timeout = Duration(minutes: 5);

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
        MaterialPageRoute(builder: (_) => const KioskScreen()),
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
