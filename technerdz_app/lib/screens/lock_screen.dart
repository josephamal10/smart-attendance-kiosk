import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/clock_widget.dart';
import '../widgets/ui.dart';
import 'login_screen.dart';

/// Kiosk welcome screen: big clock, one obvious action.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  late final Animation<double> _fadeIn = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _goToLogin() {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, a, __) => const LoginScreen(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 300),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: KeyboardListener(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (e) {
          if (e is KeyDownEvent) _goToLogin();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _goToLogin,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0xFFEEF3FF)],
              ),
            ),
            child: FadeTransition(
              opacity: _fadeIn,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
                child: Column(children: [
                  // Top bar
                  const Row(children: [
                    BrandMark(subtitle: 'Attendance kiosk'),
                    Spacer(),
                    StatusBadge('Ready', tone: Tone.success),
                  ]),
                  const Spacer(flex: 3),
                  const ClockWidget(),
                  const SizedBox(height: 56),
                  // Call to action
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3),
                            blurRadius: 24, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.touch_app_outlined, color: Colors.white, size: 22),
                      SizedBox(width: 10),
                      Text('Tap anywhere to check in or out',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const Spacer(flex: 4),
                  // Footer: what protects this kiosk
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _Feature(Icons.face_outlined, 'Face recognition'),
                    SizedBox(width: 28),
                    _Feature(Icons.visibility_outlined, 'Blink liveness'),
                    SizedBox(width: 28),
                    _Feature(Icons.shield_outlined, 'Anti-spoofing'),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Feature(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: AppTheme.textMuted),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
      ]);
}
