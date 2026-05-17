import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LiveWaveform extends StatefulWidget {
  const LiveWaveform({
    required this.amplitude,
    required this.isRecording,
    super.key,
  });

  final double amplitude;
  final bool isRecording;

  @override
  State<LiveWaveform> createState() => _LiveWaveformState();
}

class _LiveWaveformState extends State<LiveWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.isRecording
        ? (widget.amplitude * 0.60).clamp(0.0, 0.95)
        : 0.0;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target.toDouble()),
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      builder: (context, smoothedAmplitude, _) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _LineWaveformPainter(
                phase: _controller.value,
                amplitude: smoothedAmplitude,
                active: widget.isRecording,
                color: widget.isRecording
                    ? CueColors.primary
                    : Theme.of(context).colorScheme.outlineVariant,
                glowColor: CueColors.primary.withValues(alpha: 0.22),
              ),
              child: const SizedBox(height: 180, width: double.infinity),
            );
          },
        );
      },
    );
  }
}

class _LineWaveformPainter extends CustomPainter {
  const _LineWaveformPainter({
    required this.phase,
    required this.amplitude,
    required this.active,
    required this.color,
    required this.glowColor,
  });

  final double phase;
  final double amplitude;
  final bool active;
  final Color color;
  final Color glowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final baselinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
      ..color = color.withValues(alpha: active ? 0.32 : 0.22);

    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      baselinePaint,
    );

    final wavePath = Path();
    final glowPath = Path();
    final points = (size.width / 4).floor().clamp(48, 220);
    final dynamicHeight = active
        ? (6 + amplitude * size.height * 0.34).clamp(6.0, size.height * 0.42)
        : 1.2;
    final phaseRad = phase * math.pi * 2;

    for (var i = 0; i <= points; i++) {
      final t = i / points;
      final x = t * size.width;
      final envelope = math.sin(t * math.pi);
      final primary = math.sin((t * math.pi * 4.2) + phaseRad);
      final detail = math.sin((t * math.pi * 10.3) - phaseRad * 1.35);
      final wave = ((primary * 0.74) + (detail * 0.26)) * envelope;
      final y = centerY + wave * dynamicHeight;

      if (i == 0) {
        wavePath.moveTo(x, y);
        glowPath.moveTo(x, y);
      } else {
        wavePath.lineTo(x, y);
        glowPath.lineTo(x, y);
      }
    }

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = active ? 6 : 3
      ..color = glowColor.withValues(alpha: active ? 0.45 : 0.14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = active ? 3.2 : 2.2
      ..color = color.withValues(alpha: active ? 0.98 : 0.40);

    canvas.drawPath(glowPath, glowPaint);
    canvas.drawPath(wavePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _LineWaveformPainter old) =>
      old.phase != phase ||
      old.amplitude != amplitude ||
      old.active != active ||
      old.color != color ||
      old.glowColor != glowColor;
}
