import 'package:flutter/material.dart';

class SplineAreaChart extends StatelessWidget {
  final List<Map<String, dynamic>> data; // [{'label': 'Lun', 'value': 120.0}, ...]
  final String title;
  final String? subtitle;
  final Color primaryColor;
  final Color secondaryColor;
  final double height;

  const SplineAreaChart({
    super.key,
    required this.data,
    required this.title,
    this.subtitle,
    this.primaryColor = const Color(0xFF06B6D4), // Cyan brillante
    this.secondaryColor = const Color(0xFFEC4899), // Magenta acento
    this.height = 180.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131127) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? const Color(0xFF262046) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Tiempo Real',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _SplineChartPainter(
                data: data,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                isDark: isDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplineChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isDark;

  _SplineChartPainter({
    required this.data,
    required this.primaryColor,
    required this.secondaryColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const bottomPadding = 26.0;
    const topPadding = 12.0;
    final chartHeight = size.height - bottomPadding - topPadding;
    final chartWidth = size.width;

    // Calcular valor máximo
    double maxValue = 1.0;
    for (final item in data) {
      final v = (item['value'] as num?)?.toDouble() ?? 0.0;
      if (v > maxValue) maxValue = v;
    }

    // 1. Líneas de referencia horizontales suaves (Grid)
    final gridPaint = Paint()
      ..color = (isDark ? const Color(0xFF332F53) : const Color(0xFFE2E8F0)).withOpacity(0.6)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 3; i++) {
      final y = topPadding + (chartHeight / 3) * i;
      canvas.drawLine(Offset(0, y), Offset(chartWidth, y), gridPaint);
    }

    // 2. Calcular puntos de coordenadas
    final points = <Offset>[];
    final stepX = data.length > 1 ? chartWidth / (data.length - 1) : chartWidth / 2;

    for (int i = 0; i < data.length; i++) {
      final v = (data[i]['value'] as num?)?.toDouble() ?? 0.0;
      final normY = (v / maxValue).clamp(0.05, 1.0);
      final x = i * stepX;
      final y = topPadding + chartHeight * (1.0 - normY);
      points.add(Offset(x, y));
    }

    // 3. Construir la curva Spline suave (Cubic Bezier)
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;

      // Puntos de control para Catmull-Rom a Bezier
      final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
      final cp1y = p1.dy + (p2.dy - p0.dy) / 6.0;
      final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
      final cp2y = p2.dy - (p3.dx - p1.dx) / 6.0;

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }

    // 4. Relleno con degradado bajo la curva
    final fillPath = Path.from(path);
    fillPath.lineTo(chartWidth, topPadding + chartHeight);
    fillPath.lineTo(0, topPadding + chartHeight);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withOpacity(isDark ? 0.35 : 0.25),
          primaryColor.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, topPadding, chartWidth, chartHeight));

    canvas.drawPath(fillPath, fillPaint);

    // 5. Línea de trazo brillante de la curva
    final strokePaint = Paint()
      ..shader = LinearGradient(
        colors: [primaryColor, secondaryColor],
      ).createShader(Rect.fromLTWH(0, 0, chartWidth, chartHeight))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, strokePaint);

    // 6. Puntos destacados con halo
    for (int i = 0; i < points.length; i++) {
      final p = points[i];

      // Halo exterior
      canvas.drawCircle(
        p,
        6,
        Paint()..color = primaryColor.withOpacity(0.25),
      );
      // Punto interior blanco con borde
      canvas.drawCircle(
        p,
        3.5,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        p,
        3.5,
        Paint()
          ..color = primaryColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Etiqueta del eje X
      final label = data[i]['label'] as String? ?? '';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(p.dx - textPainter.width / 2, size.height - bottomPadding + 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplineChartPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.isDark != isDark;
  }
}
