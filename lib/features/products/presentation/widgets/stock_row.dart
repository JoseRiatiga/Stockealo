import 'package:flutter/material.dart';

import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../models/product.dart';
import 'product_image_view.dart';

/// Un renglón de Stock (0.16.7, decisión E2): el producto, cuántas hay, el mínimo y
/// «Ajustar». En Stock importa la cantidad, no la foto grande del catálogo.
class StockRow extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  /// null = sin permiso para ajustar
  final VoidCallback? onAdjust;

  /// «Norte 14 · Sur 6»: lo que hay en las otras sedes (0.18.1)
  final String? elsewhere;

  const StockRow({super.key, required this.product, required this.onTap, this.onAdjust, this.elsewhere});

  /// Lo agotado primero, luego lo bajo y después lo demás, cada grupo por nombre
  static List<Product> sorted(List<Product> products) {
    int rank(Product p) => p.isOutOfStock ? 0 : (p.isLowStock ? 1 : 2);
    return [...products]
      ..sort((a, b) {
        final r = rank(a) - rank(b);
        return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = product;
    final (String? state, AppTone tone) = p.isOutOfStock
        ? ('Agotado', AppTone.danger)
        : (p.isLowStock ? ('Bajo', AppTone.warning) : (null, AppTone.neutral));
    final qtyColor = p.isOutOfStock ? c.danger : (p.isLowStock ? c.warning : c.ink);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control), side: BorderSide(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.tile),
                child: ProductImageView(imagePath: p.photoPath, width: 40, height: 40, iconSize: 18),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(context, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: AppSpace.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Mínimo ${p.minStock}', style: AppText.caption(context)),
                        if (state != null) StatusPill(state, tone: tone, compact: true),
                      ],
                    ),
                    if (elsewhere != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(elsewhere!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption(context)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${p.stock}', style: AppText.amount(context, size: AppText.sizeTitle, weight: FontWeight.w800, color: qtyColor)),
                  Text(p.stock == 1 ? 'unidad' : 'unidades', style: AppText.caption(context)),
                ],
              ),
              if (onAdjust != null) ...[
                const SizedBox(width: AppSpace.md),
                OutlinedButton(
                  onPressed: onAdjust,
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Ajustar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
