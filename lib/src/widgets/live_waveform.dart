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
        painter: _MicLevelPainter(
          level: level,
          active: isRecording,
          mutedColor: Theme.of(context).colorScheme.outlineVariant,
        ),
        child: const SizedBox(height: 220, width: double.infinity),
      ),
    );
  }
}

class _MicLevelPainter extends CustomPainter {
  const _MicLevelPainter({
    required this.level,
    required this.active,
    required this.mutedColor,
  });

  final double level;
  final bool active;
  final Color mutedColor;

  @override
  void paint(Canvas canvas, Size size) {
    const labelWidth = 76.0;
    final meterWidth = (size.width - labelWidth).clamp(58.0, 92.0);
    final left = labelWidth + (size.width - labelWidth - meterWidth) / 2;
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, 8, meterWidth, size.height - 16),
      const Radius.circular(6),
    );

    final trackPaint = Paint()
      ..color = mutedColor.withValues(alpha: active ? 0.18 : 0.26);
    canvas.drawRRect(bar, trackPaint);

    final segments = <_MeterSegment>[
      _MeterSegment(0.88, 1.0, const Color(0xFFF04438), 'Peak'),
      _MeterSegment(0.56, 0.88, const Color(0xFFFFC247), 'Line'),
      _MeterSegment(0.34, 0.56, const Color(0xFF0EA5E9), 'Inst'),
      _MeterSegment(0.06, 0.34, const Color(0xFF58D83B), 'Mic'),
      _MeterSegment(0.0, 0.06, const Color(0xFFE6E6E6), ''),
    ];

    final fillTop = bar.bottom - (bar.height * level);
    canvas.save();
    canvas.clipRRect(bar);
    for (final segment in segments) {
      final top = bar.bottom - bar.height * segment.end;
      final bottom = bar.bottom - bar.height * segment.start;
      final rect = Rect.fromLTRB(bar.left, top, bar.right, bottom);
      final paint = Paint()
        ..color = active
            ? segment.color
            : mutedColor.withValues(alpha: segment.label.isEmpty ? 0.20 : 0.12);
      canvas.drawRect(rect, paint);

      if (active && segment.end > level) {
        final maskBottom = fillTop.clamp(top, bottom);
        if (maskBottom > top) {
          final mask = Rect.fromLTRB(bar.left, top, bar.right, maskBottom);
          canvas.drawRect(
            mask,
            Paint()..color = Colors.white.withValues(alpha: 0.64),
          );
        }
      }
    }
    canvas.restore();

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = mutedColor.withValues(alpha: 0.55);
    canvas.drawRRect(bar, border);

    final markerY = fillTop.clamp(bar.top, bar.bottom);
    final markerPaint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = active ? CueColors.primary : mutedColor;
    canvas.drawLine(
      Offset(bar.left - 8, markerY),
      Offset(bar.right + 8, markerY),
      markerPaint,
    );

    _drawLabels(canvas, bar, segments);
  }

  void _drawLabels(Canvas canvas, RRect bar, List<_MeterSegment> segments) {
    final labels = <(String, double)>[
      ('+24dBu', bar.top),
      ('+4dBu', bar.top + bar.height * 0.32),
      ('-20dBu', bar.top + bar.height * 0.56),
      ('-70dBu', bar.bottom),
    ];
    final labelStyle = TextStyle(
      color: Colors.black.withValues(alpha: 0.74),
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label.$1, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 70);
      painter.paint(canvas, Offset(0, label.$2 - painter.height / 2));
    }

    final zoneStyle = TextStyle(
      color: Colors.black.withValues(alpha: active ? 0.82 : 0.38),
      fontSize: 11,
      fontWeight: FontWeight.w800,
    );
    for (final segment in segments.where((s) => s.label.isNotEmpty)) {
      final centerY =
          bar.bottom - bar.height * ((segment.start + segment.end) / 2);
      final painter = TextPainter(
        text: TextSpan(text: segment.label, style: zoneStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: bar.width);
      painter.paint(
        canvas,
        Offset(
          bar.left + (bar.width - painter.width) / 2,
          centerY - painter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MicLevelPainter old) =>
      old.level != level ||
      old.active != active ||
      old.mutedColor != mutedColor;
}

class _MeterSegment {
  const _MeterSegment(this.start, this.end, this.color, this.label);

  final double start;
  final double end;
  final Color color;
  final String label;
}
