import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Full-bleed camera feed with a face guide and overlay slots. Shared by the
/// registration and verification screens so both look and behave the same.
class CameraStage extends StatelessWidget {
  final CameraController? controller;
  final Color guideColor;
  final bool showGuide;
  final Widget? top;
  final Widget? bottom;
  final Widget? center;
  final String? unavailableMessage;

  const CameraStage({
    super.key,
    required this.controller,
    this.guideColor = Colors.white,
    this.showGuide = true,
    this.top,
    this.bottom,
    this.center,
    this.unavailableMessage,
  });

  @override
  Widget build(BuildContext context) {
    final cam = controller;
    final ready = cam != null && cam.value.isInitialized;

    return Container(
      color: AppTheme.ink,
      child: Stack(fit: StackFit.expand, children: [
        if (ready)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              // previewSize is reported landscape; swap so portrait-sized boxes fill correctly
              width: cam.value.previewSize!.height,
              height: cam.value.previewSize!.width,
              child: CameraPreview(cam),
            ),
          )
        else
          Center(
            child: unavailableMessage == null
                ? const Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 28, height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                    SizedBox(height: 14),
                    Text('Starting camera...', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ])
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 40),
                    const SizedBox(height: 12),
                    Text(unavailableMessage!, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                  ]),
          ),

        // Darken everything outside the oval so the eye goes to the face
        if (showGuide && ready)
          LayoutBuilder(builder: (_, c) {
            final h = c.maxHeight * 0.72;
            final w = h * 0.74;
            return CustomPaint(painter: _GuidePainter(Size(w, h), guideColor));
          }),

        if (top != null) Positioned(top: 28, left: 24, right: 24, child: Center(child: top)),
        if (bottom != null) Positioned(bottom: 32, left: 24, right: 24, child: Center(child: bottom)),
        if (center != null) Center(child: center),
      ]),
    );
  }
}

class _GuidePainter extends CustomPainter {
  final Size oval;
  final Color color;
  _GuidePainter(this.oval, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: oval.width, height: oval.height);
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(rect);
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawOval(rect, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color);
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.oval != oval || old.color != color;
}

/// The white panel on the right of the camera screens.
class SidePanel extends StatelessWidget {
  final List<Widget> children;
  const SidePanel({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        width: 380,
        color: AppTheme.surface,
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// One numbered step in a side panel checklist.
class StepRow extends StatelessWidget {
  final int number;
  final String title;
  final String? subtitle;
  final bool done;
  final bool active;
  final Widget? trailing;
  const StepRow({super.key, required this.number, required this.title, this.subtitle,
      this.done = false, this.active = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    final Color bubble = done ? AppTheme.success : active ? AppTheme.primary : AppTheme.border;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 28, height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: done || active ? bubble : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: bubble, width: 1.5),
        ),
        child: done
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : Text('$number', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppTheme.textMuted)),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: done || active ? AppTheme.textPrimary : AppTheme.textMuted)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4)),
            ],
          ]),
        ),
      ),
      if (trailing != null) Padding(padding: const EdgeInsets.only(top: 4), child: trailing),
    ]);
  }
}
