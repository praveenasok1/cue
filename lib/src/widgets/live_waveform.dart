import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LiveWaveform extends StatelessWidget {
  const LiveWaveform({
    required this.amplitude,
    required this.isRecording,
    super.key,
  });

  final double amplitude;
  final bool isRecording;

  @override
  Widget build(BuildContext context) {
    final target = isRecording ? amplitude.clamp(0.0, 1.0) : 0.0;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target.toDouble()),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, level, _) => CustomPaint(
        painter: _BarWaveformPainter(
          level: level,
          active: isRecording,
          backgroundColor: Theme.of(context).colorScheme.surface,
          barColor: CueColors.primary,
          idleColor: Theme.of(context).colorScheme.outlineVariant,
        ),
        child: const SizedBox(height: 128, width: double.infinity),
      ),
    );
  }
}

class _BarWaveformPainter extends CustomPainter {
  const _BarWaveformPainter({
    required this.level,
    required this.active,
    required this.backgroundColor,
    required this.barColor,
    required this.idleColor,
  });

  final double level;
  final bool active;
  final Color backgroundColor;
  final Color barColor;
  final Color idleColor;

  static const _pattern = <double>[
    0.76,
    0.88,
    0.90,
    0.78,
    0.58,
    0.42,
    0.30,
    0.47,
    0.62,
    0.66,
    0.58,
    0.50,
    0.46,
    0.63,
    0.75,
    0.83,
    0.86,
    0.78,
    0.48,
    0.72,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = backgroundColor;
    final bgRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(20),
    );
    canvas.drawRRect(bgRect, bgPaint);

    final count = _pattern.length;
    final gap = (size.width * 0.025).clamp(5.0, 10.0);
    final barWidth = ((size.width - gap * (count - 1)) / count).clamp(
      5.0,
      12.0,
    );
    final usedWidth = count * barWidth + (count - 1) * gap;
    final startX = (size.width - usedWidth) / 2;
    final centerY = size.height / 2;
    final minHeight = size.height * 0.18;
    final maxHeight = size.height * 0.86;
    final liveBoost = active ? (0.28 + level * 0.72) : 0.18;
    final paint = Paint()
      ..color = active
          ? barColor.withValues(alpha: 0.55 + level * 0.45)
          : idleColor.withValues(alpha: 0.35);

    for (var i = 0; i < count; i++) {
      final x = startX + i * (barWidth + gap);
      final patternHeight = minHeight + (maxHeight - minHeight) * _pattern[i];
      final height = (patternHeight * liveBoost).clamp(minHeight, maxHeight);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, centerY),
          width: barWidth,
          height: height,
        ),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarWaveformPainter old) =>
      old.level != level ||
      old.active != active ||
      old.backgroundColor != backgroundColor ||
      old.barColor != barColor ||
      old.idleColor != idleColor;
}
