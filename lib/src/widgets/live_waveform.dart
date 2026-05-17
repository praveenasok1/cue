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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _WaveformPainter(
            phase: _controller.value,
            amplitude: widget.isRecording ? widget.amplitude : 0.08,
            color: widget.isRecording
                ? CueColors.primary
                : Theme.of(context).colorScheme.outline,
          ),
          child: const SizedBox(height: 180, width: double.infinity),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.phase,
    required this.amplitude,
    required this.color,
  });

  final double phase;
  final double amplitude;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final bars = 46;
    final gap = size.width / (bars * 1.8);
    final barWidth = gap * 0.7;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var i = 0; i < bars; i++) {
      final x = (i + 0.5) * size.width / bars;
      final wave = math.sin((i / bars * math.pi * 3.5) + phase * math.pi * 2);
      final envelope = math.sin(i / bars * math.pi).abs();
      final height =
          18 +
          (size.height * 0.62 * envelope * amplitude) +
          (wave.abs() * 46 * (amplitude + 0.12));
      final opacity = 0.22 + (envelope * 0.68);
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
        oldDelegate.color != color;
  }
}
