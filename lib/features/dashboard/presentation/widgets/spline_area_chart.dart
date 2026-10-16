import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';

class SplineAreaChart extends StatefulWidget {
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
    this.primaryColor = const Color(0xFF8B5CF6), // Violeta brillante Obsidian
    this.secondaryColor = const Color(0xFF10B981), // Esmeralda acento
    this.height = 180.0,
  });

  @override
  State<SplineAreaChart> createState() => _SplineAreaChartState();
}

class _SplineAreaChartState extends State<SplineAreaChart> {
  int? _hoveredIndex;

  void _updateHover(Offset localPosition, double width) {
    if (widget.data.isEmpty) return;
    if (widget.data.length == 1) {
      if (_hoveredIndex != 0) setState(() => _hoveredIndex = 0);
      return;
    }
    final stepX = width / (widget.data.length - 1);
    final rawIndex = (localPosition.dx / stepX).round();
    final clamped = rawIndex.clamp(0, widget.data.length - 1);
    if (_hoveredIndex != clamped) {
      setState(() => _hoveredIndex = clamped);
    }
  }

  void _clearHover() {
    if (_hoveredIndex != null) {
      setState(() => _hoveredIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final hoveredItem = (_hoveredIndex != null && _hoveredIndex! < widget.data.length)
        ? widget.data[_hoveredIndex!]
        : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131126) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.03),
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
                    widget.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (hoveredItem != null) ...[
                    Row(
                      children: [
                        Text(
                          '${hoveredItem['label']}: ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format((hoveredItem['value'] as num?)?.toDouble() ?? 0.0),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF10B981) : const Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  ] else if (widget.subtitle != null) ...[
                    Text(
                      widget.subtitle!,
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
                  color: widget.primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.primaryColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: widget.primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Tiempo Real',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: widget.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: widget.height,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return MouseRegion(
                  onHover: (event) => _updateHover(event.localPosition, constraints.maxWidth),
                  onExit: (_) => _clearHover(),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onPanUpdate: (details) => _updateHover(details.localPosition, constraints.maxWidth),
                    onPanEnd: (_) => _clearHover(),
                    onTapDown: (details) => _updateHover(details.localPosition, constraints.maxWidth),
                    onTapUp: (_) => _clearHover(),
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, widget.height),
                      painter: _SplineChartPainter(
                        data: widget.data,
                        primaryColor: widget.primaryColor,
                        secondaryColor: widget.secondaryColor,
                        isDark: isDark,
                        hoveredIndex: _hoveredIndex,
                      ),
                    ),
                  ),
                );
              },
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
  final int? hoveredIndex;

  _SplineChartPainter({
    required this.data,
    required this.primaryColor,
    required this.secondaryColor,
    required this.isDark,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const bottomPadding = 26.0;
    const topPadding = 16.0;
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
      ..color = (isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0)).withOpacity(0.6)
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
          primaryColor.withOpacity(isDark ? 0.35 : 0.22),
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

    // 6. Línea vertical de crosshair si hay hover
    if (hoveredIndex != null && hoveredIndex! < points.length) {
      final hp = points[hoveredIndex!];
      final crosshairPaint = Paint()
        ..color = primaryColor.withOpacity(0.5)
        ..strokeWidth = 1.5;

      // Línea punteada o continua vertical
      double startY = topPadding;
      while (startY < topPadding + chartHeight) {
        canvas.drawLine(
          Offset(hp.dx, startY),
          Offset(hp.dx, startY + 4),
          crosshairPaint,
        );
        startY += 8;
      }
    }

    // 7. Puntos destacados con halo y etiquetas
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final isHovered = hoveredIndex == i;

      // Halo exterior
      canvas.drawCircle(
        p,
        isHovered ? 9 : 5.5,
        Paint()..color = (isHovered ? primaryColor : primaryColor).withOpacity(isHovered ? 0.35 : 0.2),
      );
      // Punto interior blanco con borde
      canvas.drawCircle(
        p,
        isHovered ? 4.5 : 3.2,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        p,
        isHovered ? 4.5 : 3.2,
        Paint()
          ..color = primaryColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHovered ? 2.2 : 1.5,
      );

      // Etiqueta del eje X
      final label = data[i]['label'] as String? ?? '';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isHovered ? FontWeight.bold : FontWeight.w600,
            color: isHovered
                ? (isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED))
                : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(p.dx - textPainter.width / 2, size.height - bottomPadding + 8),
      );
    }

    // 8. Tooltip flotante animado sobre el punto seleccionado
    if (hoveredIndex != null && hoveredIndex! < points.length) {
      final hp = points[hoveredIndex!];
      final val = (data[hoveredIndex!]['value'] as num?)?.toDouble() ?? 0.0;
      final valText = CurrencyFormatter.format(val);

      final tooltipPainter = TextPainter(
        text: TextSpan(
          text: valText,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final tooltipWidth = tooltipPainter.width + 16;
      final tooltipHeight = tooltipPainter.height + 8;
      double tooltipX = hp.dx - tooltipWidth / 2;
      double tooltipY = hp.dy - tooltipHeight - 10;

      // Ajuste si se sale de los bordes
      if (tooltipX < 4) tooltipX = 4;
      if (tooltipX + tooltipWidth > chartWidth - 4) {
        tooltipX = chartWidth - tooltipWidth - 4;
      }
      if (tooltipY < 2) tooltipY = hp.dy + 12;

      final tooltipRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tooltipX, tooltipY, tooltipWidth, tooltipHeight),
        const Radius.circular(8),
      );

      final bgPaint = Paint()
        ..color = isDark ? const Color(0xFF18152F) : const Color(0xFF0F172A)
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      canvas.drawRRect(tooltipRect, bgPaint);
      canvas.drawRRect(tooltipRect, borderPaint);

      tooltipPainter.paint(
        canvas,
        Offset(tooltipX + 8, tooltipY + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplineChartPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.isDark != isDark ||
        oldDelegate.hoveredIndex != hoveredIndex;
  }
}
