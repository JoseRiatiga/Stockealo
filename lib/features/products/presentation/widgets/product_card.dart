import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../models/product.dart';
import 'barcode_modal.dart';
import 'product_image_view.dart';
import 'stock_status_badge.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAdjustStock;
  final VoidCallback? onSale;
  final EdgeInsetsGeometry? margin;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onAdjustStock,
    this.onSale,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: isDark ? const Color(0xFF131127) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: product.isOutOfStock
              ? const Color(0xFFEF4444)
              : (isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0)),
          width: product.isOutOfStock ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Foto del producto o icono placeholder
              ProductImageView(
                imagePath: product.photoPath,
                width: 72,
                height: 72,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: 14),

              // Información del producto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Categoría y Código
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1F1C3B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            product.category,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            product.code,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Nombre del producto
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Precios y Margen
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          CurrencyFormatter.format(product.salePrice),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF059669),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (product.purchasePrice > 0)
                          Text(
                            '+${product.profitMargin.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: product.profitMargin >= 30
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFD97706),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Acciones rápidas y Badge de Stock
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  StockStatusBadge(product: product, compact: true),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Botón para ver código de barras / QR
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.qr_code_2, size: 20, color: Color(0xFF64748B)),
                        tooltip: 'Ver Código',
                        onPressed: () => BarcodeModal.show(context, product),
                      ),
                      // Botón para venta directa / descuento de stock
                      if (onSale != null)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.shopping_bag_outlined, size: 21, color: Color(0xFF059669)),
                          tooltip: 'Registrar Venta',
                          onPressed: onSale,
                        ),
                      // Botón para ajuste rápido de stock
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_note, size: 22, color: Color(0xFF64748B)),
                        tooltip: 'Ajustar Stock',
                        onPressed: onAdjustStock,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
