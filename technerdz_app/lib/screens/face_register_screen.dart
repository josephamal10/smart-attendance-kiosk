import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/camera_stage.dart';
import '../widgets/ui.dart';

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
  bool _noCamera = false;

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
      final imageId = res['image_id'];
      if (imageId is int) _savedImageIds.add(imageId);
      setState(() {
        _counts[dir] = (_counts[dir] ?? 0) + 1;
        _total++;
      });

      if (_counts[dir]! < _perDirection) {
        setState(() => _status = _directionPrompt(dir));
      } else if (_dirIndex < directions.length - 1) {
        // Pause so the person has time to turn their head
        _captureTimer?.cancel();
        setState(() {
          _paused   = true;
          _dirIndex++;
          _status   = 'Great. Next: ${_directionPrompt(directions[_dirIndex]).toLowerCase()}';
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
          _status = 'All done. Face registered.';
        });
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
      case 'left':     return 'Turn your head slightly to the left';
      case 'right':    return 'Turn your head slightly to the right';
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

  static const _dirIcons = {
    'straight': Icons.face_outlined,
    'left': Icons.turn_left,
    'right': Icons.turn_right,
  };

  @override
  Widget build(BuildContext context) {
    final dir = directions[_dirIndex];
    final progress = _total / (_perDirection * directions.length);

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Row(children: [
        Expanded(
          child: CameraStage(
            controller: _cam,
            unavailableMessage: _noCamera ? 'No camera found on this device' : null,
            showGuide: !_done,
            guideColor: _capturing ? AppTheme.primary : Colors.white,
            top: _done
                ? null
                : CameraPill(_status,
                    leading: Icon(_dirIcons[dir], color: Colors.white, size: 20)),
            center: _countdown > 0
                ? Container(
                    width: 104, height: 104,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                    child: Text('$_countdown', style: const TextStyle(
                        color: Colors.white, fontSize: 48, fontWeight: FontWeight.w700)),
                  )
                : _done
                    ? Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: AppTheme.surface, borderRadius: BorderRadius.circular(20)),
                        child: const Column(mainAxisSize: MainAxisSize.min, children: [
                          CircleAvatar(radius: 32, backgroundColor: AppTheme.successSoft,
                              child: Icon(Icons.check_rounded, color: AppTheme.success, size: 36)),
                          SizedBox(height: 16),
                          Text('Face registered',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                          SizedBox(height: 4),
                          Text('This person can now check in at the kiosk.',
                              style: TextStyle(color: AppTheme.textSecondary)),
                        ]),
                      )
                    : null,
            bottom: _error != null && !_done
                ? CameraPill(_error!, color: AppTheme.danger,
                    leading: const Icon(Icons.error_outline, color: Colors.white, size: 18))
                : null,
          ),
        ),
        SidePanel(children: [
          Text('FACE REGISTRATION', style: AppTheme.overline),
          const SizedBox(height: 16),
          Row(children: [
            InitialsAvatar(_empName, size: 44),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_empName, style: AppTheme.h2, overflow: TextOverflow.ellipsis),
              Text('30 photos · about 30 seconds', style: AppTheme.muted),
            ])),
          ]),
          const SizedBox(height: 28),
          Row(children: [
            Text('Progress', style: AppTheme.label),
            const Spacer(),
            Text('$_total / ${_perDirection * directions.length}',
                style: AppTheme.label.copyWith(fontFeatures: AppTheme.tabular)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress, minHeight: 8,
              color: _done ? AppTheme.success : AppTheme.primary,
            ),
          ),
          const SizedBox(height: 28),
          for (var i = 0; i < directions.length; i++) ...[
            StepRow(
              number: i + 1,
              title: switch (directions[i]) {
                'straight' => 'Look straight ahead',
                'left' => 'Turn slightly left',
                _ => 'Turn slightly right',
              },
              subtitle: '${_counts[directions[i]]} of $_perDirection photos',
              done: (_counts[directions[i]] ?? 0) >= _perDirection,
              active: i == _dirIndex && !_done,
            ),
            const SizedBox(height: 18),
          ],
          const Spacer(),
          if (!_done)
            const InfoBanner(
              'Keep only one face in the frame, with even light and no hat or sunglasses.',
              tone: Tone.primary),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: _done
                ? ElevatedButton(onPressed: _cancelAndClose, child: const Text('Done'))
                : OutlinedButton(onPressed: _cancelAndClose, child: const Text('Cancel without saving')),
          ),
        ]),
      ]),
    );
  }
}
