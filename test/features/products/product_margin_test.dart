import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/products/models/product.dart';

Product _product({required double cost, required double price}) {
  final now = DateTime(2026, 10, 30);
  return Product(
    id: 'p1',
    businessId: 'b1',
    code: 'SKU-1',
    name: 'Lapicero',
    category: 'General',
    purchasePrice: cost,
    salePrice: price,
    stock: 1,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('profitMarginLabel', () {
    test('una ganancia lleva signo +', () {
      expect(_product(cost: 790, price: 1000).profitMarginLabel(), '+21%');
    });

    test('una pérdida lleva solo el signo -', () {
      final lapicero = _product(cost: 3780, price: 3000);
      expect(lapicero.profitMarginLabel(), '-26%');
      expect(lapicero.sellsBelowCost, isTrue);
    });

    test('sin ganancia ni pérdida no lleva signo', () {
      expect(_product(cost: 1000, price: 1000).profitMarginLabel(), '0%');
      expect(_product(cost: 1000, price: 1001).profitMarginLabel(), '0%');
    });

    test('respeta los decimales pedidos', () {
      expect(_product(cost: 3780, price: 3000).profitMarginLabel(decimals: 1), '-26.0%');
    });

    test('sin costo registrado no se considera pérdida', () {
      expect(_product(cost: 0, price: 1000).sellsBelowCost, isFalse);
    });
  });
}
