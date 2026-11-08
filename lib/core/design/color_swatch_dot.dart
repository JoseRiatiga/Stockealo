import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Muestra de color de una variante: un tono, dos tonos (círculo partido) o
/// multicolor (estampados). Recibe los valores tal como se guardan (#RRGGBB / 'multi').
class ColorSwatchDot extends StatelessWidget {
  final String? hex;
  final String? hex2;
  final double size;

  const ColorSwatchDot({super.key, required this.hex, this.hex2, this.size = 18});

  static Color? parse(String? hex) {
    final v = hex?.trim().replaceFirst('#', '');
    if (v == null || !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(v)) return null;
    return Color(int.parse('FF$v', radix: 16));
  }

  static bool isMulti(String? hex) => hex?.trim().toLowerCase() == 'multi';

  /// true si hay algo que dibujar
  static bool hasSwatch(String? hex) => isMulti(hex) || parse(hex) != null;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final first = parse(hex);
    final second = parse(hex2);
    Widget fill;
    if (isMulti(hex)) {
      fill = Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: [
            Color(0xFFE53935),
            Color(0xFFFDD835),
            Color(0xFF43A047),
            Color(0xFF1E88E5),
            Color(0xFF8E24AA),
            Color(0xFFE53935),
          ]),
        ),
      );
    } else if (first != null && second != null) {
      fill = CustomPaint(painter: _HalfPainter(first, second));
    } else {
      fill = Container(decoration: BoxDecoration(shape: BoxShape.circle, color: first ?? c.surfaceMuted));
    }
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.lineStrong)),
      child: ClipOval(child: fill),
    );
  }
}

class _HalfPainter extends CustomPainter {
  final Color left;
  final Color right;
  _HalfPainter(this.left, this.right);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawArc(rect, math.pi / 2, math.pi, true, Paint()..color = left);
    canvas.drawArc(rect, -math.pi / 2, math.pi, true, Paint()..color = right);
  }

  @override
  bool shouldRepaint(_HalfPainter old) => old.left != left || old.right != right;
}
