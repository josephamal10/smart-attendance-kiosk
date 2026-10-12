import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class FaceRegisterScreen extends StatefulWidget {
  final int?    employeeId;
  final String? employeeName;
  const FaceRegisterScreen({super.key, this.employeeId, this.employeeName});
  @override
  State<FaceRegisterScreen> createState() => _FaceRegisterScreenState();
}

class _FaceRegisterScreenState extends State<FaceRegisterScreen> {
  CameraController? _cam;

  final directions = ['straight', 'left', 'right'];
  int    _dirIndex  = 0;
  int    _total     = 0;
  bool   _capturing = false;
  bool   _done      = false;
  bool   _paused    = false;
  bool   _closing   = false;
  String _status    = 'Get ready — auto-capture starting...';
  String? _error;

  final Map<String, int> _counts = {'straight': 0, 'left': 0, 'right': 0};
  static const int _perDirection = 10;
  static const Duration _captureInterval = Duration(milliseconds: 300);
  static const Duration _pauseBetween    = Duration(seconds: 3);

  Timer? _captureTimer;
  int    _countdown = 0;
  Timer? _countdownTimer;
  final List<int> _savedImageIds = [];

  int    get _empId   => widget.employeeId   ?? ApiService.employeeId!;
  String get _empName => widget.employeeName ?? ApiService.name ?? 'Employee';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (!mounted || _closing) return;
    if (cameras.isEmpty) {
      setState(() => _error = 'No camera found on this device.');
      return;
    }
    _cam = CameraController(cameras.first, ResolutionPreset.medium);
    await _cam!.initialize();
    if (mounted) {
      setState(() {});
      _startCountdownThenCapture();
    }
  }

  void _startCountdownThenCapture() {
    if (_closing) return;
    setState(() {
      _countdown = 3;
      _status    = _directionPrompt(directions[_dirIndex]);
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_closing || !mounted) {
        t.cancel();
        return;
      }
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        t.cancel();
        setState(() => _countdown = 0);
        _startAutoCapture();
      }
    });
  }

  void _startAutoCapture() {
    if (_closing) return;
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(_captureInterval, (_) => _captureOnce());
  }

  Future<void> _captureOnce() async {
    if (_closing || _cam == null || _done || _paused) return;
    if (_capturing) return;

    setState(() {
      _capturing = true;
      _error = null;
    });

    try {
      final xFile = await _cam!.takePicture();
      final dir  = directions[_dirIndex];
      final file = File(xFile.path);

      final res = await ApiService.registerFace(_empId, dir, file);
      if (!mounted || _closing) return;
      if (res.containsKey('message')) {
        final imageId = res['image_id'];
        if (imageId is int) _savedImageIds.add(imageId);
        setState(() {
          _counts[dir] = (_counts[dir] ?? 0) + 1;
          _total++;
          });

          if (_counts[dir]! >= _perDirection) {
            if (_dirIndex < directions.length - 1) {
              _captureTimer?.cancel();
              setState(() {
                _paused   = true;
                _dirIndex++;
                _status   = '✓ Done! Now: ${_directionPrompt(directions[_dirIndex])}';
              });
              Future.delayed(_pauseBetween, () {
                if (!mounted || _closing) return;
                setState(() => _paused = false);
                _startAutoCapture();
              });
            } else {
              _captureTimer?.cancel();
              setState(() {
                _done   = true;
                _status = 'Face registration complete! ✓';
              });
            }
          } else {
            setState(() => _status = _directionPrompt(dir));
          }
        } else {
          setState(() =>
            _error = res['detail'] ?? 'No face detected, retrying...');
        }
    } on ApiException catch (e) {
      // e.g. "No face detected" / "More than one face" — the timer simply retries
      if (mounted && !_closing) setState(() => _error = e.message);
    } catch (e) {
      if (mounted && !_closing) {
        setState(() => _error = 'Capture error: $e');
      }
    } finally {
      if (mounted && !_closing) {
        setState(() => _capturing = false);
      }
    }
  }

  Future<void> _cancelAndClose() async {
    if (_closing) return;
    _closing = true;
    _captureTimer?.cancel();
    _countdownTimer?.cancel();

    final cam = _cam;
    _cam = null;
    if (mounted) {
      setState(() {
        _capturing = false;
        _paused = true;
        _status = 'Cancelling...';
      });
    }

    await cam?.dispose();

    if (!_done) {
      for (final imageId in _savedImageIds) {
        try {
          await ApiService.deleteFaceImage(imageId);
        } catch (_) {}
      }
    }

    if (mounted) Navigator.of(context).pop();
  }

  String _directionPrompt(String dir) {
    switch (dir) {
      case 'straight': return 'Look straight at the camera';
      case 'left':     return 'Turn your face slightly LEFT';
      case 'right':    return 'Turn your face slightly RIGHT';
      default:         return '';
    }
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _countdownTimer?.cancel();
    _cam?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          // ── Camera Feed ───────────────────────────────────
          Expanded(
            flex: 3,
            child: Stack(
              children: [
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
                      child: CircularProgressIndicator(color: AppTheme.accent)),
                  ),

                // Face oval
                if (!_done)
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
                                color: _capturing
                                  ? AppTheme.accent : Colors.white70,
                                width: _capturing ? 3 : 2.5,
                              ),
                              borderRadius: BorderRadius.circular(w / 2),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // Countdown overlay
                if (_countdown > 0)
                  Center(
                    child: Container(
                      width: 80, height: 80,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Colors.black54),
                      child: Center(
                        child: Text('$_countdown',
                          style: const TextStyle(
                            color: Colors.white, fontSize: 40,
                            fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),

                // Flash effect
                if (_capturing)
                  Container(color: Colors.white.withValues(alpha: 0.15)),

                // Status label
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
                      child: Text(_status,
                        style: const TextStyle(
                          color: Colors.white, fontSize: 14)),
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
                          color: AppTheme.error.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_error!,
                          style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                      ),
                    ),
                  ),

                // Auto-capture indicator
                if (!_done && _countdown == 0)
                  Positioned(
                    bottom: 32, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _capturing
                                  ? AppTheme.accent : AppTheme.success,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _paused
                                ? 'Switching direction...'
                                : 'Auto-capturing...',
                              style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Progress Panel ────────────────────────────────
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
                const Text('FACE REGISTRATION',
                  style: TextStyle(fontSize: 10, letterSpacing: 4,
                    color: AppTheme.accentGrey)),
                const SizedBox(height: 8),
                Text(_empName,
                  style: const TextStyle(fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                const Text('Auto-capture mode',
                  style: TextStyle(fontSize: 12, color: AppTheme.accentGrey)),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 24),

                ...directions.map((dir) {
                  final count    = _counts[dir] ?? 0;
                  final isActive = dir == directions[_dirIndex] && !_done;
                  final isDone   = count >= _perDirection;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              Icon(
                                isDone ? Icons.check_circle
                                  : isActive
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                size: 16,
                                color: isDone ? AppTheme.success
                                  : isActive ? AppTheme.accent
                                  : AppTheme.accentGrey,
                              ),
                              const SizedBox(width: 8),
                              Text(dir.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11, letterSpacing: 2,
                                  color: isActive
                                    ? AppTheme.textPrimary
                                    : AppTheme.accentGrey,
                                  fontWeight: isActive
                                    ? FontWeight.w600 : FontWeight.w400,
                                )),
                            ]),
                            Text('$count / $_perDirection',
                              style: TextStyle(fontSize: 12,
                                color: isDone
                                  ? AppTheme.success
                                  : AppTheme.accentGrey)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: count / _perDirection,
                            backgroundColor: AppTheme.border,
                            valueColor: AlwaysStoppedAnimation(
                              isDone ? AppTheme.success : AppTheme.accent),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const Divider(),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL CAPTURED',
                      style: TextStyle(fontSize: 10, letterSpacing: 2,
                        color: AppTheme.accentGrey)),
                    Text('$_total / 30',
                      style: const TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                  ],
                ),

                const Spacer(),

                if (_done) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.success),
                    ),
                    child: const Row(children: [
                      Icon(Icons.check_circle,
                        color: AppTheme.success, size: 20),
                      SizedBox(width: 12),
                      Expanded(child: Text('Registration complete!',
                        style: TextStyle(
                          color: AppTheme.success, fontSize: 13))),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentGrey,
                      side: const BorderSide(color: AppTheme.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _cancelAndClose,
                    child: Text(_done ? 'DONE' : 'DON\'T SAVE & CANCEL',
                      style: const TextStyle(
                        letterSpacing: 2, fontSize: 12)),
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
