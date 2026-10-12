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

  // Liveness state
  bool _blinkDetected = false;
  bool _checkingBlink = false;
  Timer? _blinkTimer;
  double _lastEar     = 0.0;
  static const double _earThreshold  = 0.15; // below = blink
  static const double _earOpenMin    = 0.35; // above = eyes open
  bool _eyesWereOpen  = false;

  // Verify state
  bool _verifying  = false;
  bool _verified   = false;
  bool _closing    = false;
  String _status   = 'Please blink to confirm you\'re real';
  String? _error;
  String? _action;
  int _autoLogout  = 3;
  Timer? _logoutTimer;
  static const int _verifyAttempts = 3;

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

  // Send frames every 200ms to backend to check EAR
  void _startBlinkDetection() {
    if (_closing) return;
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (_closing || _blinkDetected || _checkingBlink || _cam == null ||
          !_cam!.value.isInitialized) return;
      _checkingBlink = true;
      try {
        final xFile = await _cam!.takePicture();
        final res   = await ApiService.checkBlink(File(xFile.path));
        if (!mounted || _closing) return;

        final ear = (res['ear'] as num?)?.toDouble() ?? 0.0;
        setState(() => _lastEar = ear);

        if (res['success'] == true) {
          if (ear > _earOpenMin) {
            // Eyes are open
            _eyesWereOpen = true;
          } else if (_eyesWereOpen && ear < _earThreshold) {
            // Eyes were open and now closed → blink!
            _blinkTimer?.cancel();
            setState(() {
              _blinkDetected = true;
              _status        = 'Blink detected ✓ Now verifying face...';
            });
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted && !_closing) _verify();
          }
        }
      } catch (_) {} finally {
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

  Future<void> _verify() async {
    if (_closing || _cam == null || _verifying || _verified) return;
    setState(() {
      _verifying = true;
      _error     = null;
      _status    = 'Verifying face...';
    });

    try {
      Map<String, dynamic>? lastRes;

      for (var attempt = 1; attempt <= _verifyAttempts; attempt++) {
        if (!mounted || _closing || _cam == null) return;
        setState(() => _status = 'Verifying face... $attempt/$_verifyAttempts');

        final xFile = await _cam!.takePicture();
        final res = await ApiService.verifyFace(
          File(xFile.path),
          employeeId: widget.employeeId,
        )
            .timeout(const Duration(seconds: 15), onTimeout: () {
          return {
            'verified': false,
            'message': 'Server timeout. Is the backend running?'
          };
        });
        lastRes = res;
        if (!mounted || _closing) return;

        if (res['verified'] == true) {
          if (res['employee_id'] != widget.employeeId) {
            setState(() {
              _error          = 'Face does not match the selected account.';
              _status         = 'Please blink to confirm you\'re real';
              _verifying      = false;
              _blinkDetected  = false;
              _eyesWereOpen   = false;
            });
            _startBlinkDetection();
            return;
          }
          setState(() {
            _verified   = true;
            _action     = res['action'];
            _status     = res['message'] ?? 'Verified!';
            _autoLogout = 3;
          });
          _startAutoLogout();
          return;
        }

        await Future.delayed(const Duration(milliseconds: 350));
      }

      final msg = lastRes?['message'] ?? 'Face not recognized.';
      setState(() {
        _error         = msg.contains('No faces registered')
            ? 'No faces registered yet. Ask admin to register your face first.'
            : msg;
        _status        = 'Please blink to confirm you\'re real';
        _verifying     = false;
        _blinkDetected = false;
        _eyesWereOpen  = false;
      });
      if (!_closing) _startBlinkDetection();
    } catch (e) {
      if (!mounted || _closing) return;
      setState(() {
        _error         = 'Verification failed: ${e.toString()}';
        _status        = 'Please blink to confirm you\'re real';
        _verifying     = false;
        _blinkDetected = false;
        _eyesWereOpen  = false;
      });
      if (!_closing) _startBlinkDetection();
    }
  }

  String _formatNow() {
    final now = DateTime.now();
    final h   = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final m   = now.minute.toString().padLeft(2, '0');
    final s   = now.second.toString().padLeft(2, '0');
    final ap  = now.hour < 12 ? 'AM' : 'PM';
    return '$h:$m:$s $ap';
  }

  Color get _actionColor =>
      _action == 'in' ? AppTheme.success : AppTheme.error;
  IconData get _actionIcon =>
      _action == 'in' ? Icons.login : Icons.logout;
  String get _actionLabel =>
      _action == 'in' ? 'CHECKED IN' : 'CHECKED OUT';

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

                // Blink indicator (eye icon + EAR bar)
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
                      color: _actionColor.withOpacity(0.15),
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
                              Text(_formatNow(),
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

                // Debug EAR display
                if (!_verified)
                  Positioned(
                    bottom: 32, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'EAR: ${_lastEar.toStringAsFixed(3)}  |  Eyes open: $_eyesWereOpen',
                          style: const TextStyle(
                            color: Colors.white70, fontSize: 11,
                            fontFamily: 'monospace'),
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
                          color: AppTheme.error.withOpacity(0.85),
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
