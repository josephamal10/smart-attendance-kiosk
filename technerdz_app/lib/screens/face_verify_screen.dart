import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/camera_stage.dart';
import '../widgets/ui.dart';
import 'lock_screen.dart';

class FaceVerifyScreen extends StatefulWidget {
  final String role;
  final int employeeId;
  const FaceVerifyScreen(
      {super.key, required this.role, required this.employeeId});
  @override
  State<FaceVerifyScreen> createState() => _FaceVerifyScreenState();
}

class _FaceVerifyScreenState extends State<FaceVerifyScreen>
    with TickerProviderStateMixin {
  CameraController? _cam;

  // Liveness state — the server decides when a blink happened and returns a
  // one-time token; verification is refused without it.
  bool _blinkDetected = false;
  bool _checkingBlink = false;
  Timer? _blinkTimer;
  String? _livenessToken;
  static const _blinkPrompt = "Please blink to confirm you're real";

  // Verify state
  bool _verifying  = false;
  bool _verified   = false;
  bool _closing    = false;
  String _status   = _blinkPrompt;
  String? _error;
  bool _noCamera = false;
  String? _action;
  DateTime? _actionTime;
  int _autoLogout  = 3;
  Timer? _logoutTimer;

  // Blink animation
  late AnimationController _blinkCtrl;
  late Animation<double>   _blinkAnim;

  @override
  void initState() {
    super.initState();
    _blinkCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
    _blinkAnim = Tween<double>(begin: 1.0, end: 0.85).animate(_blinkCtrl); // gentle pulse on the result card
    _initCamera();
  }

  Future<void> _initCamera() async {
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (_) {
      if (mounted) setState(() => _noCamera = true);
      return;
    }
    if (!mounted || _closing) return;
    if (cameras.isEmpty) {
      setState(() => _noCamera = true);
      return;
    }
    _cam = CameraController(cameras.first, ResolutionPreset.medium);
    try {
      await _cam!.initialize();
    } catch (_) {
      // e.g. camera in use by another app, or permission denied
      _cam = null;
      if (mounted) setState(() => _noCamera = true);
      return;
    }
    if (mounted) {
      setState(() {});
      _startBlinkDetection();
    }
  }

  // Stream frames to the backend until it reports a blink
  void _startBlinkDetection() {
    if (_closing) return;
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 150), (_) async {
      if (_closing || _blinkDetected || _checkingBlink || _cam == null ||
          !_cam!.value.isInitialized) {
        return;
      }
      _checkingBlink = true;
      try {
        final xFile = await _cam!.takePicture();
        final res   = await ApiService.sendLivenessFrame(File(xFile.path));
        if (!mounted || _closing) return;

        if (res['live'] == true && res['liveness_token'] != null) {
          _blinkTimer?.cancel();
          setState(() {
            _blinkDetected = true;
            _livenessToken = res['liveness_token'];
            _status        = 'Blink detected ✓ Now verifying face...';
          });
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted && !_closing) _verify();
        } else {
          // e.g. "No face detected" / "Only one person should be in frame"
          final msg = res['face_found'] == true ? _blinkPrompt : res['message'];
          if (msg != _status) setState(() => _status = msg ?? _blinkPrompt);
        }
      } on ApiException catch (e) {
        if (e.statusCode == 401) _blinkTimer?.cancel(); // signed out — stop polling
        if (mounted && !_closing) setState(() => _error = e.message);
      } catch (_) {
        // A dropped frame isn't worth showing; the next tick retries
      } finally {
        _checkingBlink = false;
      }
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _logoutTimer?.cancel();
    _blinkCtrl.dispose();
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _closeWithoutSaving() async {
    if (_closing) return;
    _closing = true;
    _blinkTimer?.cancel();
    _logoutTimer?.cancel();
    _blinkCtrl.stop();

    final cam = _cam;
    _cam = null;
    if (mounted) {
      setState(() {
        _verifying = false;
        _status = 'Cancelling...';
      });
    }

    await cam?.dispose();
    if (!mounted) return;

    ApiService.clearSession();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LockScreen()),
      (_) => false,
    );
  }

  void _startAutoLogout() {
    if (_closing) return;
    _blinkCtrl.repeat(reverse: true);
    _logoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_autoLogout <= 1) {
        t.cancel();
        if (!mounted) return;
        ApiService.clearSession();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LockScreen()),
          (_) => false,
        );
      } else {
        setState(() => _autoLogout--);
      }
    });
  }

  /// Go back to waiting for a blink, showing [error].
  void _retry(String error) {
    if (!mounted || _closing) return;
    setState(() {
      _error         = error;
      _status        = _blinkPrompt;
      _verifying     = false;
      _blinkDetected = false;
      _livenessToken = null;
    });
    _startBlinkDetection();
  }

  Future<void> _verify() async {
    final token = _livenessToken;
    if (_closing || _cam == null || _verifying || _verified || token == null) return;
    setState(() {
      _verifying = true;
      _error     = null;
      _status    = 'Verifying face...';
    });

    try {
      // The liveness token is single-use, so one photo per blink
      final xFile = await _cam!.takePicture();
      final res = await ApiService.verifyFace(File(xFile.path), token)
          .timeout(const Duration(seconds: 15));
      if (!mounted || _closing) return;

      if (res['verified'] != true) {
        _retry(res['message'] ?? 'Face not recognized.');
        return;
      }
      setState(() {
        _verified   = true;
        _action     = res['action'];
        _actionTime = DateTime.tryParse(res['time'] ?? '');
        _status     = res['message'] ?? 'Verified!';
        _autoLogout = 3;
      });
      _startAutoLogout();
    } on TimeoutException {
      _retry('Server timeout. Is the backend running?');
    } on ApiException catch (e) {
      _retry(e.message);
    } catch (e) {
      _retry('Verification failed: $e');
    }
  }

  String _formatTime(DateTime? t) {
    final now = t ?? DateTime.now();
    final h   = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final m   = now.minute.toString().padLeft(2, '0');
    final s   = now.second.toString().padLeft(2, '0');
    final ap  = now.hour < 12 ? 'AM' : 'PM';
    return '$h:$m:$s $ap';
  }

  Color get _actionColor => switch (_action) {
    'in'       => AppTheme.success,
    'out'      => AppTheme.primary,   // leaving isn't an error, so not red
    'too_soon' => AppTheme.warning,
    _          => AppTheme.textSecondary,
  };
  IconData get _actionIcon => switch (_action) {
    'in'       => Icons.login_rounded,
    'out'      => Icons.logout_rounded,
    'too_soon' => Icons.schedule_rounded,
    _          => Icons.task_alt_rounded,
  };
  String get _actionLabel => switch (_action) {
    'in'       => 'Checked in',
    'out'      => 'Checked out',
    'too_soon' => 'Already checked in',
    _          => 'All done for today',
  };

  @override
  Widget build(BuildContext context) {
    final name = ApiService.name ?? '';
    final step = _verified ? 3 : _blinkDetected || _verifying ? 2 : 1;

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Row(children: [
        Expanded(
          child: CameraStage(
            controller: _cam,
            unavailableMessage: _noCamera ? 'No camera found on this device' : null,
            showGuide: !_verified,
            guideColor: _blinkDetected ? AppTheme.success : Colors.white,
            top: _verified
                ? null
                : _verifying
                    ? const CameraPill('Verifying your face...',
                        leading: SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                    : CameraPill(_status,
                        leading: Icon(
                            _blinkDetected ? Icons.check_circle : Icons.visibility_outlined,
                            color: _blinkDetected ? AppTheme.success : Colors.white, size: 20)),
            center: _verified ? _resultCard(name) : null,
            bottom: _error != null && !_verified
                ? CameraPill(_error!, color: AppTheme.danger,
                    leading: const Icon(Icons.error_outline, color: Colors.white, size: 18))
                : null,
          ),
        ),
        SidePanel(children: [
          Text('IDENTITY CHECK', style: AppTheme.overline),
          const SizedBox(height: 16),
          Row(children: [
            InitialsAvatar(name, size: 44),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: AppTheme.h2, overflow: TextOverflow.ellipsis),
              Text(widget.role == 'admin' ? 'Administrator' : 'Employee', style: AppTheme.muted),
            ])),
          ]),
          const SizedBox(height: 32),
          StepRow(number: 1, title: 'Position your face',
              subtitle: 'Fit your face inside the oval', done: step > 1, active: step == 1),
          const SizedBox(height: 20),
          StepRow(number: 2, title: 'Blink once',
              subtitle: 'Proves a real person is in front of the camera', done: step > 2, active: step == 1),
          const SizedBox(height: 20),
          StepRow(number: 3, title: 'Face match',
              subtitle: 'Checked against your registered photos', done: _verified, active: step == 2),
          const Spacer(),
          const Row(children: [
            Icon(Icons.lock_outline, size: 16, color: AppTheme.textMuted),
            SizedBox(width: 8),
            Expanded(child: Text('Photos are used only to verify you and are not stored.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: OutlinedButton(
              onPressed: _verified ? null : _closeWithoutSaving,
              child: const Text('Cancel'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _resultCard(String name) {
    final c = _actionColor;
    return FadeTransition(
      opacity: _blinkAnim,
      child: Container(
        width: 380,
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 40, offset: Offset(0, 16))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(_actionIcon, color: c, size: 36),
          ),
          const SizedBox(height: 18),
          Text(_actionLabel, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c)),
          const SizedBox(height: 6),
          Text(_formatTime(_actionTime), style: const TextStyle(
              fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1.2,
              color: AppTheme.textPrimary, fontFeatures: AppTheme.tabular)),
          const SizedBox(height: 8),
          Text(_status, textAlign: TextAlign.center, style: AppTheme.muted),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          Text('Returning to the start screen in $_autoLogout s',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        ]),
      ),
    );
  }
}
