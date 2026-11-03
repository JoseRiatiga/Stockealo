import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/flag_colors.dart';
import '../utils/countries.dart';

/// Bandera de un país dibujada a color (proporción 3:2, esquinas redondeadas)
class CountryFlag extends StatelessWidget {
  final String code;

  /// Ancho; el alto es 2/3
  final double width;

  const CountryFlag({super.key, required this.code, this.width = 24});

  @override
  Widget build(BuildContext context) {
    final name = kCountries.where((c) => c.code == code).map((c) => c.name).firstOrNull;
    return Semantics(
      label: name == null ? null : 'Bandera de $name',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.12),
        child: CustomPaint(
          size: Size(width, width * 2 / 3),
          foregroundPainter: _BorderPainter(),
          painter: _FlagPainter(code),
        ),
      ),
    );
  }
}

/// Bandera y texto juntos, para listas y selectores de país
class CountryLabel extends StatelessWidget {
  final Country country;
  final String text;
  final TextStyle? style;

  const CountryLabel({super.key, required this.country, required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CountryFlag(code: country.code, width: 22),
        const SizedBox(width: AppSpace.sm),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: style)),
      ],
    );
  }
}

class _BorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = FlagColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FlagPainter extends CustomPainter {
  final String code;

  _FlagPainter(this.code);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    void rect(double l, double t, double r, double b, Color color) =>
        canvas.drawRect(Rect.fromLTRB(l, t, r, b), Paint()..color = color);
    void star(Offset center, double radius, Color color) {
      final path = Path();
      for (var i = 0; i < 10; i++) {
        final r = i.isEven ? radius : radius * 0.4;
        final a = -math.pi / 2 + i * math.pi / 5;
        final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path..close(), Paint()..color = color);
    }

    switch (code) {
      case 'CO':
      case 'EC':
        // Amarillo la mitad de arriba, azul y rojo un cuarto cada uno
        rect(0, 0, w, h / 2, FlagColors.colombiaYellow);
        rect(0, h / 2, w, h * 3 / 4, FlagColors.colombiaBlue);
        rect(0, h * 3 / 4, w, h, FlagColors.colombiaRed);
        if (code == 'EC') {
          canvas.drawCircle(Offset(w / 2, h / 2), h * 0.16, Paint()..color = FlagColors.mexicoEagle);
        }
      case 'MX':
        rect(0, 0, w / 3, h, FlagColors.mexicoGreen);
        rect(w / 3, 0, w * 2 / 3, h, FlagColors.white);
        rect(w * 2 / 3, 0, w, h, FlagColors.mexicoRed);
        canvas.drawCircle(Offset(w / 2, h / 2), h * 0.14, Paint()..color = FlagColors.mexicoEagle);
      case 'PE':
        rect(0, 0, w / 3, h, FlagColors.peruRed);
        rect(w / 3, 0, w * 2 / 3, h, FlagColors.white);
        rect(w * 2 / 3, 0, w, h, FlagColors.peruRed);
      case 'AR':
        rect(0, 0, w, h / 3, FlagColors.argentinaBlue);
        rect(0, h / 3, w, h * 2 / 3, FlagColors.white);
        rect(0, h * 2 / 3, w, h, FlagColors.argentinaBlue);
        canvas.drawCircle(Offset(w / 2, h / 2), h * 0.11, Paint()..color = FlagColors.argentinaSun);
      case 'CL':
        rect(0, 0, w, h / 2, FlagColors.white);
        rect(0, h / 2, w, h, FlagColors.chileRed);
        rect(0, 0, w / 3, h / 2, FlagColors.chileBlue);
        star(Offset(w / 6, h / 4), h * 0.14, FlagColors.white);
      case 'US':
        for (var i = 0; i < 13; i++) {
          rect(0, h * i / 13, w, h * (i + 1) / 13, i.isEven ? FlagColors.usaRed : FlagColors.white);
        }
        rect(0, 0, w * 0.4, h * 7 / 13, FlagColors.usaBlue);
      case 'ES':
        rect(0, 0, w, h / 4, FlagColors.spainRed);
        rect(0, h / 4, w, h * 3 / 4, FlagColors.spainYellow);
        rect(0, h * 3 / 4, w, h, FlagColors.spainRed);
      default:
        rect(0, 0, w, h, FlagColors.border);
    }
  }

  @override
  bool shouldRepaint(covariant _FlagPainter oldDelegate) => oldDelegate.code != code;
}
