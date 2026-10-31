import 'package:flutter/material.dart';
import '../../../../core/design/app_card.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../models/product.dart';
import 'barcode_modal.dart';
import 'product_image_view.dart';

/// Cómo se muestran los productos en Inventario
enum ProductLayout { list, grid }

/// Tarjeta de producto de V1. Toda la tarjeta abre el detalle; las acciones (vender,
/// ajustar stock, ver código) están en el menú ⋯ o manteniendo presionado.
class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onAdjustStock;
  final VoidCallback? onSale;
  final bool showMargin;
  final bool canAdjustStock;
  final ProductLayout layout;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onAdjustStock,
    this.onSale,
    this.showMargin = true,
    this.canAdjustStock = true,
    this.layout = ProductLayout.list,
  });

  Future<void> _showActions(BuildContext context) async {
    final c = context.colors;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.sm, 0, AppSpace.sm, AppSpace.md),
                child: Text(product.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
              ),
              if (onSale != null && !product.isOutOfStock)
                ListTile(
                  leading: const Icon(Icons.shopping_bag_outlined),
                  title: const Text('Vender'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onSale!();
                  },
                ),
              if (canAdjustStock && onAdjustStock != null)
                ListTile(
                  leading: const Icon(Icons.inventory_outlined),
                  title: const Text('Ajustar stock'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onAdjustStock!();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.qr_code_2_rounded),
                title: const Text('Ver código'),
                onTap: () {
                  Navigator.pop(ctx);
                  BarcodeModal.show(context, product);
                },
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Ver detalle'),
                onTap: () {
                  Navigator.pop(ctx);
                  onTap();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return layout == ProductLayout.grid ? _buildGrid(context) : _buildList(context);
  }

  Widget _moreButton(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.more_horiz_rounded, color: context.colors.inkMuted),
      tooltip: 'Acciones de ${product.name}',
      visualDensity: VisualDensity.compact,
      onPressed: () => _showActions(context),
    );
  }

  Widget _buildList(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.xs, AppSpace.md),
      onTap: onTap,
      onLongPress: () => _showActions(context),
      child: Row(
        children: [
          ProductImageView(
            imagePath: product.photoPath,
            width: 56,
            height: 56,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.25, color: c.ink),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StockPill(product: product),
                    Text(product.category, style: TextStyle(fontSize: 12, color: c.inkMuted)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(CurrencyFormatter.format(product.salePrice), style: AppText.amount(context)),
              if (showMargin && product.purchasePrice > 0) MarginLabel(product: product),
            ],
          ),
          _moreButton(context),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      onLongPress: () => _showActions(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.25,
            child: ProductImageView(imagePath: product.photoPath, borderRadius: BorderRadius.zero),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.25, color: c.ink),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(CurrencyFormatter.format(product.salePrice), style: AppText.amount(context)),
                          const SizedBox(height: 4),
                          StockPill(product: product),
                        ],
                      ),
                    ),
                    _moreButton(context),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta de stock: "12 en stock", "Quedan 2" o "Agotado"
class StockPill extends StatelessWidget {
  final Product product;

  const StockPill({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (String label, Color fg, Color bg) = product.isOutOfStock
        ? ('Agotado', c.danger, c.dangerSoft)
        : product.isLowStock
            ? ('Quedan ${product.stock}', c.warning, c.warningSoft)
            : ('${product.stock} en stock', c.inkMuted, c.surfaceMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

/// Margen con signo y color: verde si gana bien, ámbar si gana poco, rojo si pierde
class MarginLabel extends StatelessWidget {
  final Product product;

  const MarginLabel({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = product.sellsBelowCost ? c.danger : (product.profitMargin >= 30 ? c.success : c.warning);
    return Text(
      product.profitMarginLabel(),
      style: AppText.amount(context, size: 12, weight: FontWeight.w600, color: color),
    );
  }
}
