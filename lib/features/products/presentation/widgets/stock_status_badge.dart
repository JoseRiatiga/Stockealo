import 'package:flutter/material.dart';
import '../../models/product.dart';

class StockStatusBadge extends StatelessWidget {
  final Product product;
  final bool compact;

  const StockStatusBadge({
    super.key,
    required this.product,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;
    IconData icon;

    if (product.isOutOfStock) {
      bgColor = const Color(0xFFFEE2E2); // Red 100
      textColor = const Color(0xFFDC2626); // Red 600
      label = compact ? '${product.stock}' : 'Agotado (0)';
      icon = Icons.cancel_outlined;
    } else if (product.isLowStock) {
      bgColor = const Color(0xFFFEF3C7); // Amber 100
      textColor = const Color(0xFFD97706); // Amber 600
      label = compact ? '${product.stock}' : 'Bajo stock (${product.stock})';
      icon = Icons.warning_amber_rounded;
    } else {
      bgColor = const Color(0xFFD1FAE5); // Emerald 100
      textColor = const Color(0xFF059669); // Emerald 600
      label = compact ? '${product.stock}' : 'Stock: ${product.stock}';
      icon = Icons.check_circle_outline;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }
}
