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
  double _displayAmplitude = 0;

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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        _displayAmplitude =
            (_displayAmplitude * 0.68) + (target.toDouble() * 0.32);
        return CustomPaint(
          painter: _WaveformPainter(
            phase: _controller.value,
            amplitude: _displayAmplitude,
            active: widget.isRecording,
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
    required this.active,
    required this.color,
  });

  final double phase;
  final double amplitude;
  final bool active;
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
      final wave = active
          ? math.sin((i / bars * math.pi * 4.5) + phase * math.pi * 2.8)
          : math.sin(i / bars * math.pi * 2);
      final envelope = math.sin(i / bars * math.pi).abs();
      final height =
          10 +
          (size.height * 0.74 * envelope * amplitude) +
          (wave.abs() * 58 * amplitude);
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
        oldDelegate.active != active ||
        oldDelegate.color != color;
  }
}
