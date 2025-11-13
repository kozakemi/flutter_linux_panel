import 'dart:ui';
import 'package:flutter/material.dart';

class SpectrumPainter extends CustomPainter {
  final List<double> fft;
  final Color color;
  final int bins;

  SpectrumPainter({required this.fft, required this.color, this.bins = 128});

  @override
  void paint(Canvas canvas, Size size) {
    if (fft.isEmpty) return;
    final barCount = bins.clamp(1, fft.length);
    final barWidth = size.width / barCount;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    for (int i = 0; i < barCount; i++) {
      final start = (i * fft.length / barCount).floor();
      final end = (((i + 1) * fft.length / barCount).ceil()).clamp(start + 1, fft.length);
      double sum = 0.0;
      int count = 0;
      for (int j = start; j < end; j++) {
        final v = fft[j].isFinite ? fft[j] : 0.0;
        sum += v;
        count++;
      }
      final avg = count > 0 ? sum / count : 0.0;
      final amp = avg.clamp(0.0, 1.0) as double;
      final h = amp * size.height;
      final x = i * barWidth;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h, barWidth * 0.9, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SpectrumPainter oldDelegate) {
    return oldDelegate.fft != fft || oldDelegate.color != color;
  }
}
