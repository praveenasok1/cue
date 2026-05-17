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
    // Faster cycle (900 ms) so the waveform feels live and punchy.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Standby: gentle idle ripple. Active: driven by mic amplitude.
    final target = widget.isRecording ? widget.amplitude.clamp(0.0, 1.0) : 0.0;

    // TweenAnimationBuilder provides 80 ms ease-out for visual smoothing
    // without mutating state inside the build callback.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target.toDouble()),
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOut,
      builder: (context, smoothedAmplitude, _) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _WaveformPainter(
                phase: _controller.value,
                amplitude: smoothedAmplitude,
                active: widget.isRecording,
                color: widget.isRecording
                    ? CueColors.primary
                    : Theme.of(context).colorScheme.outlineVariant,
                accentColor: CueColors.primary.withValues(alpha: 0.28),
              ),
              child: const SizedBox(height: 180, width: double.infinity),
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
    required this.accentColor,
  });

  final double phase;
  final double amplitude;
  final bool active;
  final Color color;
  final Color accentColor;

  static const _bars = 50;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final slotWidth = size.width / _bars;
    final barWidth = (slotWidth * 0.58).clamp(2.0, 7.0);

    // Always-visible baseline pulse so users see the waveform is alive.
    // Scales from 0.04 (silence) up to 0 as amplitude grows (voice overrides).
    final baseline = active ? 0.04 * (1 - amplitude.clamp(0, 1)) : 0.0;

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var i = 0; i < _bars; i++) {
      final x = (i + 0.5) * slotWidth;

      // Smooth bell envelope — taller bars in the middle.
      final envelope = math.sin(i / _bars * math.pi);

      // Primary slow sine driven by animation phase.
      final primary = math.sin(
        (i / _bars * math.pi * 3.8) + phase * math.pi * 2,
      );

      // Fast jitter overlay: makes bars feel reactive to bursts.
      final jitter = active
          ? math.sin((phase * math.pi * 9.2) + i * 1.1) * 0.22 * amplitude
          : 0.0;

      // Effective amplitude = live mic level + idle baseline.
      final effective = (amplitude + baseline).clamp(0.0, 1.0);

      final barHeight =
          (
              // Minimum visible height even at silence, grows with input.
              6.0 +
                  size.height * 0.78 * envelope * effective +
                  primary.abs() * size.height * 0.28 * effective +
                  jitter.abs() * size.height)
              .clamp(6.0, size.height * 0.92);

      final opacity = active
          ? (0.28 + envelope * 0.68).clamp(0.0, 1.0)
          : (0.12 + envelope * 0.22).clamp(0.0, 1.0);

      paint.color = color.withValues(alpha: opacity);
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.phase != phase ||
      old.amplitude != amplitude ||
      old.active != active ||
      old.color != color;
}
