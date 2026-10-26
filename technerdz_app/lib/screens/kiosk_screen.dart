import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../i18n/kiosk_text.dart';
import '../services/api_service.dart';
import '../services/voice.dart';
import '../theme/app_theme.dart';
import '../widgets/camera_stage.dart';
import '../widgets/clock_widget.dart';
import '../widgets/ui.dart';
import 'my_attendance_screen.dart';

/// The camera screen, opened from the lock screen with a tap. Look at the camera and blink;
/// the server recognises you and records IN / OUT. No names, no passwords.
/// Goes back to the lock screen by itself once the scan is done or nobody is in front of it.
class KioskScreen extends StatefulWidget {
  /// Shows this check-in result without a camera (widget tests and the screenshot tool).
  final Map<String, dynamic>? demoResult;
  /// Opened with the lock screen's "My dashboard" icon: the scan opens that person's own
  /// dashboard and does not check them in or out.
  final bool dashboardMode;
  const KioskScreen({super.key, this.demoResult, this.dashboardMode = false});
  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

enum _Phase { starting, waiting, blink, identifying, result }

class _KioskScreenState extends State<KioskScreen> {
  CameraController? _cam;
  bool _noCamera = false;
  bool _running = false;  // scan loop active
  bool _busy = false;     // a frame is being processed
  bool _paused = false;   // someone is using My attendance: don't scan
  late final bool _dashboardMode = widget.dashboardMode;
  Timer? _idleTimer;      // back to the lock screen when nobody is in front of the camera
  bool _leaving = false;

  _Phase _phase = _Phase.starting;
  String _sessionId = _newSessionId();
  String? _error;
  Map<String, dynamic>? _result;
  Timer? _resultTimer;
  int _resultCountdown = 0;

  static const _resultSeconds = 8; // long enough to tap "My dashboard"
  static const _idleTimeout = Duration(seconds: 30);

  static String _newSessionId() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    if (widget.demoResult != null) {
      _phase = _Phase.result;
      _result = widget.demoResult;
      _resultCountdown = _resultSeconds;
      return;
    }
    _startCamera();
    _bumpIdle();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _running = false;
    _resultTimer?.cancel();
    _cam?.dispose();
    super.dispose();
  }

  // ── Camera lifecycle ─────────────────────────────────────

  /// Build with --dart-define=NO_CAMERA=true for UI previews/screenshots without a webcam.
  static const _previewNoCamera = bool.fromEnvironment('NO_CAMERA');

  /// Someone is (still) here: restart the countdown back to the lock screen.
  void _bumpIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () {
      if (mounted && !_paused && _phase != _Phase.result) _leave();
    });
  }

  /// Back to the lock screen, releasing the camera first so the next scan can open it.
  Future<void> _leave() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _idleTimer?.cancel();
    await _stopCamera();
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      _leaving = false; // opened as the home screen (tests): just start over
      _reset();
      _startCamera();
    }
  }

  Future<void> _startCamera() async {
    setState(() { _noCamera = false; _phase = _Phase.starting; });
    try {
      if (_previewNoCamera) throw Exception('camera disabled for preview');
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('no camera');
      final cam = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
      await cam.initialize();
      if (!mounted) { await cam.dispose(); return; }
      setState(() { _cam = cam; _phase = _Phase.waiting; });
      _running = true;
      _loop();
    } catch (_) {
      if (mounted) setState(() => _noCamera = true);
    }
  }

  Future<void> _stopCamera() async {
    _running = false;
    _resultTimer?.cancel();
    while (_busy) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    final cam = _cam;
    if (mounted) setState(() => _cam = null);
    await cam?.dispose();
  }

  // ── Scan loop ────────────────────────────────────────────

  /// Self-scheduling loop: quick polling while a face is in view, slower when nobody's there.
  Future<void> _loop() async {
    while (_running && mounted) {
      var delay = const Duration(milliseconds: 600);
      if (_phase != _Phase.result && !_paused && !_busy && _cam != null) {
        _busy = true;
        try {
          delay = await _tick();
        } finally {
          _busy = false;
        }
      }
      await Future.delayed(delay);
    }
  }

  Future<Duration> _tick() async {
    try {
      final frame = File((await _cam!.takePicture()).path);
      final res = await ApiService.kioskLiveness(frame, _sessionId);
      if (!mounted || !_running) return Duration.zero;

      if (res['face_found'] == true) _bumpIdle();
      if (res['face_found'] != true) {
        // Nobody (or more than one person) in front of the camera
        final msg = res['message'] as String?;
        setState(() {
          _phase = _Phase.waiting;
          _error = msg != null && msg.contains('one person') ? msg : null;
        });
        return const Duration(milliseconds: 500);
      }
      if (res['live'] != true) {
        setState(() { _phase = _Phase.blink; _error = null; });
        return const Duration(milliseconds: 120);
      }

      // Blinked: take a fresh photo and identify
      setState(() => _phase = _Phase.identifying);
      final photo = File((await _cam!.takePicture()).path);
      final openDashboard = _dashboardMode;
      final out = await (openDashboard
              ? ApiService.kioskIdentify(photo, _sessionId, res['liveness_token'])
              : ApiService.kioskCheckIn(photo, _sessionId, res['liveness_token']))
          .timeout(const Duration(seconds: 15));
      if (!mounted || !_running) return Duration.zero;
      _sessionId = _newSessionId();
      if (out['recognized'] == true && openDashboard) {
        Voice.say(KioskScreenSpeech.of({...out, 'action': 'dashboard'}, DateTime.now()));
        _openMyAttendance(out);
      } else if (out['recognized'] == true) {
        _showResult(out);
      } else {
        setState(() { _phase = _Phase.waiting; _error = out['message']; });
      }
      return const Duration(milliseconds: 800);
    } on ApiException catch (e) {
      if (mounted) setState(() { _phase = _Phase.waiting; _error = e.message; });
      _sessionId = _newSessionId();
      return const Duration(seconds: 1);
    } on TimeoutException {
      if (mounted) setState(() { _phase = _Phase.waiting; _error = 'The server is taking too long. Please try again.'; });
      return const Duration(seconds: 1);
    } on SocketException {
      if (mounted) setState(() { _phase = _Phase.waiting; _error = "Can't reach the attendance server."; });
      return const Duration(seconds: 3);
    } catch (_) {
      return const Duration(milliseconds: 500); // a dropped frame; just try again
    }
  }

  void _showResult(Map<String, dynamic> res) {
    Voice.say(KioskScreenSpeech.of(res, DateTime.now()));
    _resultTimer?.cancel();
    setState(() {
      _result = res;
      _phase = _Phase.result;
      _error = null;
      _resultCountdown = _resultSeconds;
    });
    _resultTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_resultCountdown <= 1) {
        t.cancel();
        _leave();
      } else {
        setState(() => _resultCountdown--);
      }
    });
  }

  /// Open this person's own page. Scanning pauses so nobody else gets checked in meanwhile.
  Future<void> _openMyAttendance(Map<String, dynamic> r) async {
    final token = r['self_token'] as String?;
    if (token == null) return;
    _resultTimer?.cancel();
    setState(() => _paused = true);
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MyAttendanceScreen(token: token, name: r['name'] ?? '', category: r['category'])));
    if (!mounted) return;
    _paused = false;
    _leave(); // their dashboard closed: back to the lock screen for the next person
  }

  void _reset() {
    _resultTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _result = null;
      _error = null;
      _phase = _cam == null ? _Phase.starting : _Phase.waiting;
      _sessionId = _newSessionId();
    });
  }

  // ── UI ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Row(children: [
        Expanded(
          child: CameraStage(
            controller: _cam,
            unavailableMessage: _noCamera ? KioskText.t('no_camera') : null,
            showGuide: _phase != _Phase.result,
            guideColor: switch (_phase) {
              _Phase.blink => AppTheme.primary,
              _Phase.identifying => AppTheme.success,
              _ => Colors.white,
            },
            top: _phase == _Phase.result || _cam == null ? null : _instructionPill(),
            center: _phase == _Phase.result && _result != null ? _resultCard(_result!) : null,
            bottom: _error != null && _phase != _Phase.result
                ? CameraPill(_error!, color: AppTheme.danger,
                    leading: const Icon(Icons.error_outline, color: Colors.white, size: 18))
                : _noCamera
                    ? OutlinedButton.icon(
                        onPressed: () { _bumpIdle(); _startCamera(); },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(KioskText.t('try_again')),
                      )
                    : null,
          ),
        ),
        _panel(),
      ]),
    );
  }

  Widget _instructionPill() => switch (_phase) {
        _Phase.identifying => CameraPill(KioskText.t('pill_identifying'),
            leading: const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
        _Phase.blink => CameraPill(KioskText.t('pill_blink'),
            leading: const Icon(Icons.visibility_outlined, color: Colors.white, size: 20)),
        _ when _dashboardMode => CameraPill(KioskText.t('pill_dashboard'),
            color: AppTheme.primary,
            leading: const Icon(Icons.dashboard_outlined, color: Colors.white, size: 20)),
        _ => CameraPill(KioskText.t('pill_check_in'),
            leading: const Icon(Icons.face_outlined, color: Colors.white, size: 20)),
      };

  Widget _panel() {
    final step = switch (_phase) {
      _Phase.blink => 2,
      _Phase.identifying => 3,
      _Phase.result => 4,
      _ => 1,
    };
    return SidePanel(children: [
      Row(children: [
        const Expanded(
          child: Align(alignment: Alignment.centerLeft,
              child: FittedBox(fit: BoxFit.scaleDown, child: BrandMark(size: 34, subtitle: 'Face check-in'))),
        ),
        Tooltip(
          message: 'Back to the home screen',
          child: OutlinedButton.icon(
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text(KioskText.t('back')),
          ),
        ),
      ]),
      const SizedBox(height: 40),
      const Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(fit: BoxFit.scaleDown, child: ClockWidget(scale: 0.62)),
      ),
      const SizedBox(height: 36),
      const Divider(),
      const SizedBox(height: 28),
      if (_dashboardMode) ...[
        InfoBanner(KioskText.t('dash_banner'), tone: Tone.primary),
        const SizedBox(height: 20),
      ],
      Text(KioskText.t(_dashboardMode ? 'how_dashboard' : 'how_check_in'), style: AppTheme.overline),
      const SizedBox(height: 18),
      StepRow(number: 1, title: KioskText.t('step1'),
          subtitle: KioskText.t('step1_sub'), done: step > 1, active: step == 1),
      const SizedBox(height: 18),
      StepRow(number: 2, title: KioskText.t('step2'),
          subtitle: KioskText.t('step2_sub'), done: step > 2, active: step == 2),
      const SizedBox(height: 18),
      StepRow(number: 3, title: KioskText.t('step3'),
          subtitle: KioskText.t(_dashboardMode ? 'step3_sub_dash' : 'step3_sub'),
          done: step > 3, active: step == 3),
      const Spacer(),
      Row(children: [
        Icon(Icons.lock_outline, size: 15, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Expanded(child: Text(KioskText.t('privacy_short'),
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
      ]),
    ]);
  }

  /// One line about today: "On time", "Late by 12 min", "Worked 8h 05m"...
  (String, Tone, IconData) _summary(Map<String, dynamic> r) {
    final flags = ((r['flags'] as List?) ?? const []).cast<String>();
    final worked = r['worked_minutes'] as int?;
    switch (r['action']) {
      case 'in':
        return flags.contains('late')
            ? (KioskText.t('late_by', {'n': r['late_minutes']}), Tone.warning, Icons.schedule)
            : (KioskText.t('on_time'), Tone.success, Icons.check_circle_outline);
      case 'out':
      case 'done':
        final w = worked == null ? KioskText.t('day_complete') : KioskText.t('worked', {'x': formatMinutes(worked)});
        return flags.contains('early_leave')
            ? ('$w · ${KioskText.t('left_early', {'n': r['early_minutes']})}', Tone.warning, Icons.timelapse)
            : (w, Tone.primary, Icons.timelapse);
      default:
        return (KioskText.t('earlier'), Tone.neutral, Icons.info_outline);
    }
  }

  Widget _resultCard(Map<String, dynamic> r) {
    final action = r['action'] as String?;
    final (Color c, IconData icon, String label) = switch (action) {
      'in'       => (AppTheme.success, Icons.login_rounded, KioskText.t('checked_in')),
      'out'      => (AppTheme.primary, Icons.logout_rounded, KioskText.t('checked_out')),
      'too_soon' => (AppTheme.warning, Icons.schedule_rounded, KioskText.t('already_in')),
      _          => (AppTheme.textSecondary, Icons.task_alt_rounded, KioskText.t('all_done')),
    };
    final time = DateTime.tryParse(r['time'] ?? '') ?? DateTime.now();
    final name = r['name'] as String? ?? '';
    final category = r['category'] as String?;
    final (summary, summaryTone, summaryIcon) = _summary(r);

    return Container(
      width: 420,
      padding: const EdgeInsets.fromLTRB(32, 30, 32, 22),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 40, offset: Offset(0, 16))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        InitialsAvatar(name, size: 64),
        const SizedBox(height: 14),
        Text('${KioskText.greeting(time)}, ${name.split(' ').first}!', textAlign: TextAlign.center, style: AppTheme.h2),
        const SizedBox(height: 6),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: AppTheme.muted)),
          if (category != null) ...[
            const SizedBox(width: 8),
            StatusBadge(category, tone: Tone.neutral, dot: false),
          ],
        ]),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c)),
            const SizedBox(width: 12),
            Text(DateFormat('h:mm a').format(time), style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary,
                fontFeatures: AppTheme.tabular)),
          ])),
        ),
        const SizedBox(height: 12),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(summaryIcon, size: 18, color: summaryTone.fg),
          const SizedBox(width: 6),
          Flexible(child: Text(summary, style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: summaryTone.fg))),
        ]),
        const SizedBox(height: 6),
        Text(KioskText.t(switch (action) {
              'in' => 'msg_in', 'out' => 'msg_out', 'too_soon' => 'msg_too_soon', _ => 'msg_done' }),
            textAlign: TextAlign.center, style: AppTheme.muted),
        const SizedBox(height: 18),
        if (r['self_token'] != null)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openMyAttendance(r),
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(KioskText.t('my_dashboard')),
            ),
          ),
        const SizedBox(height: 12),
        Text(KioskText.t('back_in', {'n': _resultCountdown}),
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      ]),
    );
  }
}

class KioskScreenSpeech {
  /// What the kiosk says out loud (Windows only has English voices built in, so English).
  static String of(Map<String, dynamic> r, DateTime now) {
    final first = (r['name'] as String? ?? '').split(' ').first;
    final hello = now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';
    final late = ((r['flags'] as List?) ?? const []).contains('late');
    return switch (r['action']) {
      'in' => late ? "$hello, $first. You're checked in, ${r['late_minutes']} minutes late." : "$hello, $first. You're checked in.",
      'out' => 'Goodbye, $first. See you tomorrow.',
      'too_soon' => "Hi $first, you're already checked in.",
      'done' => "Hi $first, you're all done for today.",
      _ => 'Opening your dashboard, $first.',
    };
  }
}
