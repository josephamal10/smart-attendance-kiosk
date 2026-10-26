import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../i18n/kiosk_text.dart';
import '../services/api_service.dart';
import '../services/demo.dart';
import '../services/voice.dart';
import '../theme/app_theme.dart';
import '../theme/branding.dart';
import '../widgets/demo_panel.dart';
import '../widgets/ui.dart';
import 'admin_login_screen.dart';
import 'kiosk_screen.dart';

/// What the kiosk shows when nobody is using it: a big clock, the date and company notices.
/// Touch anywhere (or press a key) to open the camera and check in. The two corner icons open
/// "My dashboard" (by face) and admin sign-in. The camera is only on while someone is scanning.
class LockScreen extends StatefulWidget {
  /// Off in the screenshot tool, whose fast-forwarded clock makes network timeouts fire early.
  static bool pollServer = true;
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with TickerProviderStateMixin {
  DateTime _now = DateTime.now();
  Timer? _clock;
  Timer? _refresh;
  Timer? _rotate;
  Timer? _retry;
  List<Map<String, dynamic>> _notices = [];
  int _notice = 0;
  bool _busy = false; // a screen opened from here is still closing
  bool? _online;      // null until the first check; false shows the "Offline" badge
  int _checks = 0;
  int _failures = 0;  // in a row; one slow reply shouldn't flash "Offline"
  List<Map<String, dynamic>> _celebrations = []; // today's birthdays and work anniversaries
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
    KioskText.lang.addListener(_onLanguage);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
    _loadNotices();
    _checkServer();
    // Every 15 s: is the server there (and what's the company called)? Notices every 5 min.
    if (LockScreen.pollServer) {
      _refresh = Timer.periodic(const Duration(seconds: 15), (_) {
        _checkServer();
        if (++_checks % 20 == 0) _loadNotices();
      });
    }
    _rotate = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_notices.length > 1) setState(() => _notice = (_notice + 1) % _notices.length);
    });
  }

  @override
  void dispose() {
    KioskText.lang.removeListener(_onLanguage);
    _clock?.cancel();
    _refresh?.cancel();
    _rotate?.cancel();
    _retry?.cancel();
    _drift.dispose();
    _pulse.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onLanguage() => setState(() {});

  Future<void> _checkServer() async {
    var ok = true;
    try {
      final info = await ApiService.kioskInfo();
      final name = (info['company_name'] as String? ?? '').trim();
      if (name.isNotEmpty) Branding.name.value = name;
      Voice.enabled = info['voice_greeting'] != false;
      Demo.update(info);
      final c = ((info['celebrations'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (mounted && c.toString() != _celebrations.toString()) setState(() => _celebrations = c);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      // Only call it offline after two failed checks in a row; re-check the first failure soon
      if (++_failures == 1 && LockScreen.pollServer) {
        _retry = Timer(const Duration(seconds: 3), () { if (mounted) _checkServer(); });
      }
      if (_failures < 2) return;
    } else {
      _failures = 0;
    }
    if (ok == _online) return;
    final cameBack = _online == false && ok;
    setState(() => _online = ok);
    if (cameBack) _loadNotices();
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
  void _myDashboard() {
    if (!Demo.enabled) {
      _open(const KioskScreen(dashboardMode: true));
      return;
    }
    // Demo: visitors have no registered face, so let them pick an employee instead
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Open a dashboard'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Demo: pick an employee. At the real kiosk this needs their face.', style: AppTheme.muted),
          const SizedBox(height: 12),
          for (final e in Demo.employees.take(6))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: InitialsAvatar(e['name'], size: 34),
              title: Text(e['name']),
              subtitle: Text(e['category'] ?? 'No team'),
              onTap: () { Navigator.pop(ctx); openDemoDashboard(context, e); },
            ),
          const Divider(),
          TextButton.icon(
            onPressed: () { Navigator.pop(ctx); _open(const KioskScreen(dashboardMode: true)); },
            icon: const Icon(Icons.face_outlined, size: 18),
            label: const Text('Scan my face instead'),
          ),
        ]),
      ),
    ));
  }
  void _admin() => _open(const AdminLoginScreen());

  String _date() {
    try {
      return DateFormat('EEEE, d MMMM y', KioskText.lang.value.locale).format(_now);
    } catch (_) {
      return DateFormat('EEEE, d MMMM y').format(_now); // locale data not loaded (tests)
    }
  }

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
            const BrandMark(size: 40, onDark: true, subtitle: 'Face check-in'),
            ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: Demo.info,
              builder: (_, info, __) => info == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(left: 14, top: 8),
                      child: Tooltip(
                        message: "Demo with made-up data. Tap 'My dashboard' to open any employee's "
                            'dashboard; the admin sign-in page lists the demo accounts.',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(999)),
                          child: const Text('DEMO', style: TextStyle(color: Color(0xFF1F2937), fontSize: 12,
                              fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                        ),
                      ),
                    ),
            ),
            // The offline badge sits in the middle and shrinks (long translations get "...")
            Expanded(
              child: _online == false
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Center(child: _offlineBadge()),
                    )
                  : const SizedBox.shrink(),
            ),
            _CornerButton(icon: Icons.person_outline_rounded, label: KioskText.t('my_dashboard'),
                tooltip: 'My dashboard — see your attendance, leave and hours', onTap: _myDashboard),
            const SizedBox(width: 14),
            _CornerButton(icon: Icons.admin_panel_settings_outlined, label: KioskText.t('admin'),
                tooltip: 'Admin sign-in', onTap: _admin),
          ]),
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(KioskText.greeting(_now).toUpperCase(), style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6), fontSize: 15, fontWeight: FontWeight.w600,
                    // wide letter spacing suits Latin capitals but breaks up Tamil and Hindi letters
                    letterSpacing: KioskText.lang.value == KioskLang.en ? 4 : 0.5)),
                SizedBox(height: clock * 0.08),
                _bigClock(clock),
                SizedBox(height: clock * 0.1),
                Text(_date(), style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: (clock * 0.13).clamp(16.0, 30.0),
                    fontWeight: FontWeight.w500)),
                SizedBox(height: clock * (_celebrations.isEmpty ? 0.28 : 0.18)),
                if (_celebrations.isNotEmpty) ...[_celebrationRow(), SizedBox(height: clock * 0.14)],
                _tapHint(),
              ]),
            ),
          ),
          if (_notices.isNotEmpty) ...[_noticeCard(), const SizedBox(height: 22)],
          Row(children: [
            Icon(Icons.lock_outline_rounded, size: 15, color: Colors.white.withValues(alpha: 0.45)),
            const SizedBox(width: 8),
            Expanded(child: Text(KioskText.t('privacy'), overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45)))),
            const SizedBox(width: 16),
            _languagePicker(),
          ]),
        ]),
      ),
    );
  }

  /// English · தமிழ் · हिन्दी — remembered on this PC.
  Widget _languagePicker() => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.translate_rounded, size: 16, color: Colors.white.withValues(alpha: 0.5)),
        const SizedBox(width: 6),
        for (final l in KioskLang.values)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Material(
              color: l == KioskText.lang.value ? Colors.white.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => KioskText.set(l),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(l.label, style: TextStyle(
                      color: Colors.white.withValues(alpha: l == KioskText.lang.value ? 1 : 0.6),
                      fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
      ]);

  /// "Happy birthday, Arun!" · "Mira — 3 years with us today!"
  Widget _celebrationRow() => Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final c in _celebrations.take(4))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(colors: [
                  const Color(0xFFF59E0B).withValues(alpha: 0.28),
                  const Color(0xFFEC4899).withValues(alpha: 0.22),
                ]),
                border: Border.all(color: const Color(0xFFFCD34D).withValues(alpha: 0.45)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(c['kind'] == 'birthday' ? Icons.cake_rounded : Icons.celebration_rounded,
                    color: const Color(0xFFFDE68A), size: 20),
                const SizedBox(width: 8),
                Text(
                  c['kind'] == 'birthday'
                      ? KioskText.t('birthday', {'name': c['name']})
                      : KioskText.t(c['years'] == 1 ? 'anniversary_one' : 'anniversary',
                          {'name': c['name'], 'years': c['years'] ?? 1}),
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
        ],
      );

  /// Shown while the server can't be reached, so nobody scans in vain.
  Widget _offlineBadge() => Tooltip(
        message: 'Check that the Attendance server window is open on this PC. '
            'This clears by itself when the server is back.',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(KioskText.t('offline'), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      );

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
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.touch_app_outlined, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Text(KioskText.t('tap_hint'),
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
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
