import 'package:flutter/material.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/color_swatch_dot.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/models/product.dart';
import '../../../products/models/product_variant.dart';

/// Elegir la talla, el color o la presentación de un producto antes de venderlo.
/// Con talla y color, un renglón por talla con sus colores.
class VariantPicker {
  VariantPicker._();

  /// La variante elegida, o null si se cerró. Si el producto no tiene variantes, null.
  static Future<ProductVariant?> pick(BuildContext context, Product product) async {
    var variants = product.variants;
    if (variants.isEmpty) variants = await ProductRepository.instance.getVariantsForProduct(product.id);
    if (variants.isEmpty || !context.mounted) return null;

    final attribute = variants.first.attributeName.toLowerCase();
    final twoAttributes = variants.any((v) => v.hasSecondAttribute) && variants.any((v) => v.attributeValue.trim().isNotEmpty);
    final groups = <String, List<ProductVariant>>{};
    for (final v in variants) {
      groups.putIfAbsent(v.attributeValue.trim(), () => []).add(v);
    }

    return AppSheet.show<ProductVariant>(
      context: context,
      title: product.name,
      subtitle: twoAttributes ? 'Elige $attribute y color' : 'Elige la $attribute',
      builder: (ctx) {
        Widget chip(ProductVariant v, String text) => _VariantChip(variant: v, text: text, onTap: () => Navigator.pop(ctx, v));
        if (!twoAttributes) {
          return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [for (final v in variants) chip(v, v.label)]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final g in groups.entries) ...[
              SectionLabel('${variants.first.attributeName} ${g.key}'.toUpperCase(), padding: const EdgeInsets.only(bottom: AppSpace.sm)),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [for (final v in g.value) chip(v, v.attribute2Value ?? v.label)],
              ),
              const SizedBox(height: AppSpace.lg),
            ],
          ],
        );
      },
    );
  }
}

class _VariantChip extends StatelessWidget {
  final ProductVariant variant;
  final String text;
  final VoidCallback onTap;

  const _VariantChip({required this.variant, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final available = variant.stock > 0;
    final radius = BorderRadius.circular(AppRadius.control);
    return Semantics(
      button: true,
      enabled: available,
      label: '$text, ${available ? '${variant.stock} disponibles' : 'agotada'}',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: available ? c.lineStrong : c.line)),
        child: InkWell(
          borderRadius: radius,
          onTap: available ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md + 2, vertical: AppSpace.sm + 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (ColorSwatchDot.hasSwatch(variant.colorHex)) ...[
                      ColorSwatchDot(hex: variant.colorHex, hex2: variant.colorHex2, size: 16),
                      const SizedBox(width: 6),
                    ],
                    Text(text, style: AppText.bodyLarge(context, weight: FontWeight.w700, color: available ? c.ink : c.inkFaint)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  available ? '${variant.stock} disp.' : 'Agotada',
                  style: AppText.caption(context, weight: FontWeight.w600, color: available ? c.inkMuted : c.danger),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
