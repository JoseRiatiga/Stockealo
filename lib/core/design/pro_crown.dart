import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Corona dorada que marca lo que es de Stockealo Pro: plana, sin borde
class ProCrown extends StatelessWidget {
  final double size;

  const ProCrown({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Stockealo Pro',
      child: CustomPaint(size: Size.square(size), painter: _CrownPainter()),
    );
  }
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final gold = Paint()..color = AppPalette.proGold;
    // Cuerpo: tres puntas sobre una franja, centrado en el cuadro
    final crown = Path()
      ..moveTo(w * 0.12, h * 0.34)
      ..lineTo(w * 0.33, h * 0.52)
      ..lineTo(w * 0.50, h * 0.26)
      ..lineTo(w * 0.67, h * 0.52)
      ..lineTo(w * 0.88, h * 0.34)
      ..lineTo(w * 0.80, h * 0.68)
      ..lineTo(w * 0.20, h * 0.68)
      ..close();
    canvas.drawPath(crown, gold);
    // Base separada por una línea fina
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.20, h * 0.73, w * 0.80, h * 0.82, Radius.circular(w * 0.03)),
      gold,
    );
    // Bolitas en las puntas
    canvas.drawCircle(Offset(w * 0.12, h * 0.30), w * 0.065, gold);
    canvas.drawCircle(Offset(w * 0.50, h * 0.21), w * 0.065, gold);
    canvas.drawCircle(Offset(w * 0.88, h * 0.30), w * 0.065, gold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
