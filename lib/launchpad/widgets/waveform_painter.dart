import 'dart:ui';
import 'package:flutter/material.dart';

class WaveformPainter extends CustomPainter {
  final List<double> samples;
  final Color color;

  WaveformPainter({required this.samples, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final path = Path();
    final midY = size.height / 2;
    final len = samples.length;
    for (int i = 0; i < len; i++) {
      final x = i * size.width / (len - 1);
      // Clamp amplitude, scale to 80% of half-height to avoid clipping
      final amp = (samples[i]).clamp(-1.0, 1.0) as double;
      final y = midY - amp * (size.height * 0.4);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Draw a soft background fill under the line
    final fill = Path.from(path)
      ..lineTo(size.width, midY)
      ..lineTo(0, midY)
      ..close();
    final fillPaint = Paint()
      ..color = color.withOpacity(0.18)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fill, fillPaint);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.samples != samples || oldDelegate.color != color;
  }
}

