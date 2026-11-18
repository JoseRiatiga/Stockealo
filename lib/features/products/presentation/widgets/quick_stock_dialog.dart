import 'package:flutter/material.dart';
import '../../data/product_repository.dart';
import '../../models/product.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/status_pill.dart';
import 'lots_widgets.dart';
import '../../data/lots_repository.dart';

/// Ajuste rápido de stock de un producto, con motivo para el kardex.
class QuickStockDialog {
  static Future<void> show(BuildContext context, {required Product product, required VoidCallback onSaved}) async {
    final controller = TextEditingController(text: product.stock.toString());
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
icon: Icons.inventory_2_outlined,
tone: AppTone.accent,
title: 'Ajustar stock',
subtitle: product.name,
content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingresa el número total de unidades disponibles:',
              style: TextStyle(fontSize: AppText.sizeSmall, color: context.colors.inkFaint),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Unidades que hay',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
          ],
        ),
actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              if (val != null && val >= 0) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Actualizar'),
          ),
        ],
),
    );

    if (result == true) {
      final newStock = int.parse(controller.text.trim());
      await ProductRepository.instance.adjustStock(
        product.id,
        product.businessId,
        newStock,
        'Ajuste rápido',
      );
      // Lotes (0.16.0, fase 2b): las unidades nuevas con su fecha; si no la pone, quedan «sin fecha»
      final added = newStock - product.stock;
      if (added > 0 && product.tracksExpiry && !product.hasVariants && context.mounted) {
        final d = await LotDatePrompt.show(context, productName: product.name, quantity: added);
        if (d != null) {
          await LotsRepository.instance.addLot(
            businessId: product.businessId,
            productId: product.id,
            quantity: added,
            expiresOn: d.expiresOn,
            code: d.code,
            cost: product.purchasePrice,
            source: 'AJUSTE',
          );
        }
      }
      if (newStock < product.stock) await LotsRepository.instance.reconcile(product.businessId);
      onSaved();
    }
  }
}
