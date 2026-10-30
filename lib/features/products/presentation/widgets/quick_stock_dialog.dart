import 'package:flutter/material.dart';
import '../../data/product_repository.dart';
import '../../models/product.dart';

/// Ajuste rápido de stock de un producto, con motivo para el kardex.
class QuickStockDialog {
  static Future<void> show(BuildContext context, {required Product product, required VoidCallback onSaved}) async {
    final controller = TextEditingController(text: product.stock.toString());
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.inventory_2_rounded, color: Color(0xFF10B981), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ajustar Stock', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
                  Text(
                    product.name,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa el número total de unidades disponibles:',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nuevo Stock',
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
              backgroundColor: const Color(0xFF059669),
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
        'Ajuste rápido desde catálogo',
      );
      onSaved();
    }
  }
}
