import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

class SegmentedBarItem {
  final String label;
  final String valueText;
  final double percentage; // 0.0 a 1.0
  final Color color;

  const SegmentedBarItem({
    required this.label,
    required this.valueText,
    required this.percentage,
    required this.color,
  });
}

class SegmentedProgressCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<SegmentedBarItem> items;

  const SegmentedProgressCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
              color: c.ink,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11.5,
                color: c.inkMuted,
              ),
            ),
          ],
          const SizedBox(height: 18),

          // Barras segmentadas
          ...items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                      Text(
                        item.valueText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Barra dividida en segmentos
                  _buildSegmentedBar(item.percentage.clamp(0.0, 1.0), item.color, c),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSegmentedBar(double pct, Color color, StockealoColors c) {
    const totalSegments = 24;
    final activeSegments = (pct * totalSegments).round();

    return Row(
      children: List.generate(totalSegments, (index) {
        final isActive = index < activeSegments;
        return Expanded(
          child: Container(
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: isActive ? color : c.surfaceMuted,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }
}
