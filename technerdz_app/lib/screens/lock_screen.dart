import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/branding.dart';
import '../widgets/ui.dart';
import 'admin_login_screen.dart';
import 'kiosk_screen.dart';

/// What the kiosk shows when nobody is using it: a big clock, the date and company notices.
/// Touch anywhere (or press a key) to open the camera and check in. The two corner icons open
/// "My dashboard" (by face) and admin sign-in. The camera is only on while someone is scanning.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with TickerProviderStateMixin {
  DateTime _now = DateTime.now();
  Timer? _clock;
  Timer? _refresh;
  Timer? _rotate;
  List<Map<String, dynamic>> _notices = [];
  int _notice = 0;
  bool _busy = false; // a screen opened from here is still closing
  final _focus = FocusNode();

  // Slow drifting glow in the background (also keeps pixels from burning in) and the tap hint pulse
  late final AnimationController _drift =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat(reverse: true);
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  static const _bgTop = Color(0xFF070B16);
  static const _bgBottom = Color(0xFF0F1A36);
  static const _glowBlue = Color(0xFF3B82F6);
  static const _glowViolet = Color(0xFF8B5CF6);

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
    _loadNotices();
    _refresh = Timer.periodic(const Duration(minutes: 5), (_) {
      _loadNotices();
      Branding.load();
    });
    _rotate = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_notices.length > 1) setState(() => _notice = (_notice + 1) % _notices.length);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _refresh?.cancel();
    _rotate?.cancel();
    _drift.dispose();
    _pulse.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadNotices() async {
    try {
      final n = await ApiService.kioskNotices();
      if (mounted) setState(() { _notices = n; _notice = 0; });
    } catch (_) {
      // Server unreachable: keep whatever we had; the camera screen explains connection problems
    }
  }

  Future<void> _open(Widget screen) async {
    if (_busy) return;
    _busy = true;
    await Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => screen,
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
    _busy = false;
    if (!mounted) return;
    _focus.requestFocus();
    _loadNotices();
  }

  void _checkIn() => _open(const KioskScreen());
  void _myDashboard() => _open(const KioskScreen(dashboardMode: true));
  void _admin() => _open(const AdminLoginScreen());

  String get _greeting => _now.hour < 12 ? 'Good morning' : _now.hour < 17 ? 'Good afternoon' : 'Good evening';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgTop,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent &&
              (e.logicalKey == LogicalKeyboardKey.space || e.logicalKey == LogicalKeyboardKey.enter)) {
            _checkIn();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _checkIn,
          child: LayoutBuilder(builder: (_, box) => Stack(children: [
            Positioned.fill(child: _background(box.biggest)),
            Positioned.fill(child: _content(box.biggest)),
          ])),
        ),
      ),
    );
  }

  // ── Background ───────────────────────────────────────────

  Widget _background(Size size) => AnimatedBuilder(
        animation: _drift,
        builder: (_, __) {
          final t = Curves.easeInOut.transform(_drift.value);
          final r = max(size.width, size.height) * 0.55;
          Widget glow(Color c, double alpha, Offset centre) => Positioned(
                left: centre.dx - r, top: centre.dy - r,
                child: Container(
                  width: r * 2, height: r * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [c.withValues(alpha: alpha), c.withValues(alpha: 0)]),
                  ),
                ),
              );
          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [_bgTop, _bgBottom]),
            ),
            child: Stack(children: [
              glow(_glowBlue, 0.26, Offset(size.width * (0.15 + 0.2 * t), size.height * (0.2 + 0.15 * t))),
              glow(_glowViolet, 0.18, Offset(size.width * (0.9 - 0.2 * t), size.height * (0.85 - 0.1 * t))),
            ]),
          );
        },
      );

  // ── Foreground ───────────────────────────────────────────

  Widget _content(Size size) {
    // Size the clock from the screen so it looks right on a laptop and on a big kiosk monitor
    final clock = min(size.width * 0.17, size.height * 0.30).clamp(72.0, 260.0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 32, 40, 28),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const BrandMark(size: 40, onDark: true, subtitle: 'Attendance'),
            const Spacer(),
            _CornerButton(icon: Icons.person_outline_rounded, label: 'My dashboard',
                tooltip: 'My dashboard — see your attendance, leave and hours', onTap: _myDashboard),
            const SizedBox(width: 14),
            _CornerButton(icon: Icons.admin_panel_settings_outlined, label: 'Admin',
                tooltip: 'Admin sign-in', onTap: _admin),
          ]),
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_greeting.toUpperCase(), style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6), fontSize: 15, fontWeight: FontWeight.w600,
                    letterSpacing: 4)),
                SizedBox(height: clock * 0.08),
                _bigClock(clock),
                SizedBox(height: clock * 0.1),
                Text(DateFormat('EEEE, d MMMM y').format(_now), style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: (clock * 0.13).clamp(16.0, 30.0),
                    fontWeight: FontWeight.w500)),
                SizedBox(height: clock * 0.28),
                _tapHint(),
              ]),
            ),
          ),
          if (_notices.isNotEmpty) ...[_noticeCard(), const SizedBox(height: 22)],
          Row(children: [
            Icon(Icons.lock_outline_rounded, size: 15, color: Colors.white.withValues(alpha: 0.45)),
            const SizedBox(width: 8),
            Text('Face check-in · your photo is only used to recognise you and is never stored',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45))),
          ]),
        ]),
      ),
    );
  }

  Widget _bigClock(double size) {
    final colonOn = _now.second.isEven; // a gently blinking colon shows the screen is alive
    final style = TextStyle(color: Colors.white, fontSize: size, fontWeight: FontWeight.w600, height: 1,
        letterSpacing: -size * 0.03, fontFeatures: AppTheme.tabular);
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(DateFormat('h').format(_now), style: style),
      AnimatedOpacity(
        opacity: colonOn ? 1 : 0.25,
        duration: const Duration(milliseconds: 300),
        child: Text(':', style: style),
      ),
      Text(DateFormat('mm').format(_now), style: style),
      SizedBox(width: size * 0.08),
      Padding(
        padding: EdgeInsets.only(bottom: size * 0.1),
        child: Text(DateFormat('a').format(_now), style: TextStyle(
            color: const Color(0xFF93C5FD), fontSize: size * 0.2, fontWeight: FontWeight.w600)),
      ),
    ]);
  }

  Widget _tapHint() => FadeTransition(
        opacity: Tween(begin: 0.55, end: 1.0).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.touch_app_outlined, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Text('Tap anywhere to check in or out',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _noticeCard() {
    final n = _notices[_notice.clamp(0, _notices.length - 1)];
    final pinned = n['pinned'] == true;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          child: Container(
            key: ValueKey(n['id']),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: pinned ? 0.12 : 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: _glowBlue.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(10)),
                child: Icon(pinned ? Icons.push_pin_rounded : Icons.campaign_outlined, color: const Color(0xFFBFDBFE), size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(n['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                if ((n['body'] as String? ?? '').isNotEmpty)
                  Text(n['body'], maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
              ])),
            ]),
          ),
        ),
        if (_notices.length > 1) ...[
          const SizedBox(height: 10),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < _notices.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _notice ? 18 : 6, height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: i == _notice ? 0.8 : 0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// A round glass button with a small caption, for the lock screen's top corner.
class _CornerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  const _CornerButton({required this.icon, required this.label, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.09),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12,
                    fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ),
      );
}
