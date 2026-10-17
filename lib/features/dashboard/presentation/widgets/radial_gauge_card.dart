import 'dart:math' as math;
import 'package:flutter/material.dart';

class RadialGaugeCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final double progress; // 0.0 a 1.0
  final List<Color> gradientColors;
  final IconData? icon;
  final VoidCallback? onTap;

  const RadialGaugeCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.progress,
    required this.gradientColors,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = gradientColors.first;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131127) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? primaryColor.withOpacity(0.25)
                : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(isDark ? 0.08 : 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Encabezado con título e ícono opcional
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
                if (icon != null)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 15, color: primaryColor),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Medidor radial segmentado
            SizedBox(
              width: 110,
              height: 110,
              child: CustomPaint(
                painter: _SegmentedGaugePainter(
                  progress: progress.clamp(0.0, 1.0),
                  colors: gradientColors,
                  isDark: isDark,
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Subtítulo / etiqueta inferior
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                subtitle,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedGaugePainter extends CustomPainter {
  final double progress;
  final List<Color> colors;
  final bool isDark;

  _SegmentedGaugePainter({
    required this.progress,
    required this.colors,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const totalTicks = 26;
    const startAngle = 135.0 * math.pi / 180.0;
    const sweepAngle = 270.0 * math.pi / 180.0;
    const tickLength = 8.0;

    final activeCount = (progress * totalTicks).round();

    for (int i = 0; i < totalTicks; i++) {
      final t = i / (totalTicks - 1);
      final angle = startAngle + t * sweepAngle;

      final p1 = Offset(
        center.dx + (radius - tickLength) * math.cos(angle),
        center.dy + (radius - tickLength) * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );

      final isActive = i < activeCount;

      Color tickColor;
      double strokeW = 2.4;

      if (isActive) {
        // Interpola entre los colores del gradiente
        final colorIndex = t * (colors.length - 1);
        final baseIndex = colorIndex.floor();
        final remainder = colorIndex - baseIndex;
        if (baseIndex >= colors.length - 1) {
          tickColor = colors.last;
        } else {
          tickColor = Color.lerp(colors[baseIndex], colors[baseIndex + 1], remainder)!;
        }
        strokeW = 3.0;
      } else {
        tickColor = isDark
            ? const Color(0xFF1E293B)
            : const Color(0xFFE2E8F0);
      }

      final paint = Paint()
        ..color = tickColor
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedGaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark ||
        oldDelegate.colors != colors;
  }
}
