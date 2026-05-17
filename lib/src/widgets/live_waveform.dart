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
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.isRecording ? widget.amplitude.clamp(0, 1) : 0.06;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target.toDouble()),
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      builder: (context, amplitude, _) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _WaveformPainter(
                phase: _controller.value,
                amplitude: amplitude,
                active: widget.isRecording,
                color: widget.isRecording
                    ? CueColors.primary
                    : Theme.of(context).colorScheme.outline,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
              child: const SizedBox(height: 190, width: double.infinity),
            );
          },
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.phase,
    required this.amplitude,
    required this.active,
    required this.color,
    required this.backgroundColor,
  });

  final double phase;
  final double amplitude;
  final bool active;
  final Color color;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final bars = 52;
    final gap = size.width / (bars * 1.58);
    final barWidth = gap * 0.82;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    final centerLinePaint = Paint()
      ..color = backgroundColor.withValues(alpha: 0.72)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    canvas.drawLine(
      Offset(size.width * 0.04, centerY),
      Offset(size.width * 0.96, centerY),
      centerLinePaint,
    );

    for (var i = 0; i < bars; i++) {
      final x = (i + 0.5) * size.width / bars;
      final wave = active
          ? math.sin((i / bars * math.pi * 4.5) + phase * math.pi * 2.8)
          : math.sin(i / bars * math.pi * 2);
      final envelope = math.sin(i / bars * math.pi).abs();
      final jitter = active
          ? math.sin((phase * math.pi * 7) + i * 0.83).abs() * 0.18
          : 0;
      final height =
          8 +
          (size.height * 0.82 * envelope * amplitude) +
          (wave.abs() * size.height * 0.34 * amplitude) +
          (jitter * size.height * amplitude);
      final opacity = active
          ? 0.26 + (envelope * 0.70)
          : 0.18 + envelope * 0.28;
      paint.color = color.withValues(alpha: opacity.clamp(0, 1).toDouble());
      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.active != active ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
