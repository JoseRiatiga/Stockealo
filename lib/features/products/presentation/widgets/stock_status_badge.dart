import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
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
    final c = context.colors;
    Color bgColor;
    Color textColor;
    String label;
    IconData icon;

    if (product.isOutOfStock) {
      bgColor = c.dangerSoft;
      textColor = c.danger;
      label = compact ? '${product.stock}' : 'Agotado (0)';
      icon = Icons.cancel_outlined;
    } else if (product.isLowStock) {
      bgColor = c.warningSoft;
      textColor = c.warning;
      label = compact ? '${product.stock}' : 'Bajo stock (${product.stock})';
      icon = Icons.warning_amber_outlined;
    } else {
      bgColor = c.successSoft;
      textColor = c.success;
      label = compact ? '${product.stock}' : 'Stock: ${product.stock}';
      icon = Icons.check_circle_outline_outlined;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
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
