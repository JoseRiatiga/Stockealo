import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Medidor de rayitas en arco (240°): las rayitas hasta [progress] van en [color] y
/// el resto en el color de las líneas. Al aparecer se llena con una animación corta,
/// salvo que el celular tenga "reducir animaciones".
class SegmentedGauge extends StatelessWidget {
  /// De 0 a 1
  final double progress;
  final Color color;
  final double size;

  /// Cantidad de rayitas; menos en el medidor pequeño para que se distingan
  final int segments;

  /// Contenido en el centro (el número en el medidor grande)
  final Widget? child;

  const SegmentedGauge({
    super.key,
    required this.progress,
    required this.color,
    this.size = 56,
    this.segments = 18,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final target = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    final c = context.colors;
    final track = c.lineStrong;
    // En oscuro el verde de marca se pierde sobre la tarjeta: se aclara un poco
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Color.lerp(color, Colors.white, 0.3)! : color;
    final animate = !MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: size,
      height: size * 0.86,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: animate ? 0 : target, end: target),
        duration: animate ? const Duration(milliseconds: 700) : Duration.zero,
        curve: Curves.easeOutCubic,
        builder: (context, value, inner) => CustomPaint(
          painter: _GaugePainter(progress: value, color: ink, track: track, segments: segments),
          child: inner,
        ),
        child: child == null ? null : Padding(padding: EdgeInsets.only(top: size * 0.06), child: Center(child: child)),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  final int segments;

  _GaugePainter({required this.progress, required this.color, required this.track, required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    final center = Offset(side / 2, side / 2);
    final outer = side * 0.46;
    final length = side * (side > 80 ? 0.09 : 0.11);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = side > 80 ? 3.2 : 2.6;
    // Una rayita cuenta como llena si está dentro del avance (la primera se pinta con cualquier avance > 0)
    final filled = progress <= 0 ? 0 : math.max(1, (progress * segments).round());
    for (var i = 0; i < segments; i++) {
      final angle = (150 + 240 * i / (segments - 1)) * math.pi / 180;
      final direction = Offset(math.cos(angle), math.sin(angle));
      paint.color = i < filled ? color : track;
      canvas.drawLine(center + direction * (outer - length), center + direction * outer, paint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress || old.color != color || old.track != track || old.segments != segments;
}
