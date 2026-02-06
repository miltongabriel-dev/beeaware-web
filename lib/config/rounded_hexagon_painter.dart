// ignore_for_file: deprecated_member_use

import 'dart:math' as math;
import 'package:flutter/material.dart';

class RoundedHexagonPainter extends CustomPainter {
  final Color color;
  final double borderRadius;

  RoundedHexagonPainter({required this.color, this.borderRadius = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      // ignore: deprecated_member_use
      ..color = color.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    final path = Path();
    final w = size.width;
    final h = size.height;

    // Coordenadas proporcionais de um hexágono real
    path.moveTo(w * 0.5, h * 0.05); // Topo
    path.lineTo(w * 0.95, h * 0.28); // Superior Dir
    path.lineTo(w * 0.95, h * 0.72); // Inferior Dir
    path.lineTo(w * 0.5, h * 0.95); // Base
    path.lineTo(w * 0.05, h * 0.72); // Inferior Esq
    path.lineTo(w * 0.05, h * 0.28); // Superior Esq
    path.close();

    canvas.drawPath(path, paint);

    // Borda branca para destacar o formato
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
