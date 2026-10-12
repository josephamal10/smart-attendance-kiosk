import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
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
    _blinkAnim = Tween<double>(begin: 1.0, end: 0.0).animate(_blinkCtrl);
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (!mounted || _closing) return;
    if (cameras.isEmpty) {
      setState(() => _error = 'No camera found.');
      return;
    }
    _cam = CameraController(cameras.first, ResolutionPreset.medium);
    await _cam!.initialize();
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
    'in'  => AppTheme.success,
    'out' => AppTheme.error,
    _     => AppTheme.accentGrey,   // done / too_soon: nothing changed
  };
  IconData get _actionIcon => switch (_action) {
    'in'  => Icons.login,
    'out' => Icons.logout,
    _     => Icons.info_outline,
  };
  String get _actionLabel => switch (_action) {
    'in'       => 'CHECKED IN',
    'out'      => 'CHECKED OUT',
    'too_soon' => 'ALREADY IN',
    _          => 'ALL DONE TODAY',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          // ── Camera ───────────────────────────────────
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                // Camera preview
                if (_cam != null && _cam!.value.isInitialized)
                  SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _cam!.value.previewSize!.height,
                        height: _cam!.value.previewSize!.width,
                        child: CameraPreview(_cam!),
                      ),
                    ),
                  )
                else
                  Container(
                    color: AppTheme.surface,
                    child: const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.accent)),
                  ),

                // Face oval
                if (!_verified)
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        final w = constraints.maxWidth  * 0.55;
                        final h = constraints.maxHeight * 0.82;
                        return Center(
                          child: Container(
                            width: w, height: h,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _blinkDetected
                                  ? AppTheme.success : Colors.white70,
                                width: 2.5),
                              borderRadius: BorderRadius.circular(w / 2),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // Blink indicator
                if (!_verified && !_verifying)
                  Positioned(
                    top: 24, left: 0, right: 0,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _blinkDetected
                                    ? Icons.check_circle
                                    : Icons.remove_red_eye_outlined,
                                  color: _blinkDetected
                                    ? AppTheme.success : Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(_status,
                                  style: const TextStyle(
                                    color: Colors.white, fontSize: 14)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Verifying indicator
                if (_verifying)
                  Positioned(
                    top: 24, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2)),
                            SizedBox(width: 10),
                            Text('Verifying face...',
                              style: TextStyle(
                                color: Colors.white, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Check in/out blink overlay
                if (_verified)
                  FadeTransition(
                    opacity: _blinkAnim,
                    child: Container(
                      color: _actionColor.withValues(alpha: 0.15),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _actionColor, width: 2),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_actionIcon,
                                color: _actionColor, size: 64),
                              const SizedBox(height: 16),
                              Text(_actionLabel,
                                style: TextStyle(
                                  color: _actionColor, fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 4)),
                              const SizedBox(height: 12),
                              Text(_formatTime(_actionTime),
                                style: TextStyle(
                                  color: _actionColor, fontSize: 36,
                                  fontWeight: FontWeight.w300,
                                  letterSpacing: 2)),
                              const SizedBox(height: 8),
                              Text(_status,
                                style: const TextStyle(
                                  color: Colors.white70, fontSize: 14),
                                textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              Text('Returning in $_autoLogout...',
                                style: const TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Error
                if (_error != null)
                  Positioned(
                    bottom: 32, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_error!,
                          style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Info Panel ────────────────────────────────
          Container(
            width: 280,
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(left: BorderSide(color: AppTheme.border)),
            ),
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TECHNERDZ', style: TextStyle(
                  fontSize: 11, letterSpacing: 6,
                  color: AppTheme.accentGrey)),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 24),
                const Text('FACE VERIFICATION', style: TextStyle(
                  fontSize: 10, letterSpacing: 3,
                  color: AppTheme.accentGrey)),
                const SizedBox(height: 12),
                Text(ApiService.name ?? '', style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text(widget.role.toUpperCase(), style: const TextStyle(
                  fontSize: 10, letterSpacing: 3,
                  color: AppTheme.accentGrey)),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 24),

                _Instruction(
                  step: '1',
                  text: 'Position your face inside the oval',
                  done: _blinkDetected || _verified,
                ),
                const SizedBox(height: 16),
                _Instruction(
                  step: '2',
                  text: 'Blink naturally to confirm liveness',
                  done: _blinkDetected || _verified,
                ),
                const SizedBox(height: 16),
                _Instruction(
                  step: '3',
                  text: 'Face recognition runs automatically',
                  done: _verified,
                ),

                const Spacer(),
                const Divider(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentGrey,
                      side: const BorderSide(color: AppTheme.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _verified ? null : _closeWithoutSaving,
                    child: const Text('CANCEL',
                      style: TextStyle(letterSpacing: 2, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Instruction extends StatelessWidget {
  final String step, text;
  final bool done;
  const _Instruction(
      {required this.step, required this.text, required this.done});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 24, height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? AppTheme.success : AppTheme.border,
        ),
        child: Center(
          child: done
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : Text(step, style: const TextStyle(
                fontSize: 11, color: AppTheme.accentGrey,
                fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(text, style: const TextStyle(
          color: AppTheme.textSecondary, fontSize: 13, height: 1.6)),
      ),
    ],
  );
}
