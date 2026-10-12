import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera_windows/camera_windows.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';
import 'screens/lock_screen.dart';

// Global navigator key — used by ApiService for session expiry redirect
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CameraWindows.registerWith();
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
      home: const IdleDetector(child: LockScreen()),
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
  static const _timeout = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _timer?.cancel();
    _timer = Timer(_timeout, _onIdle);
  }

  void _onIdle() {
    if (ApiService.isLoggedIn && ApiService.role != 'admin') {
      ApiService.clearSession();
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LockScreen()),
        (_) => false,
      );
    }
  }

  @override
  void dispose() {
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