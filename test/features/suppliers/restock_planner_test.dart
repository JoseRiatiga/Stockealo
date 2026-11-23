import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/products/presentation/widgets/restock_order_modal.dart';
import 'package:stockealo/features/suppliers/data/restock_planner.dart';
import 'package:stockealo/features/suppliers/models/supplier.dart';

void main() {
  // Un sábado
  final now = DateTime(2026, 11, 21, 10);

  Product cafe({int stock = 3, int min = 5, DateTime? created}) => Product(
        id: 'cafe',
        businessId: 'b',
        code: 'C1',
        name: 'Café',
        category: 'Granos',
        purchasePrice: 8000,
        salePrice: 12000,
        stock: stock,
        minStock: min,
        createdAt: created ?? DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  test('los días que tiene que alcanzar: hasta la visita y una semana más (0.17.0)', () {
    Supplier with_(String day) => Supplier(id: 's', businessId: 'b', name: 'Proveedor', visitDay: day, createdAt: now, updatedAt: now);
    // Sábado → el lunes faltan 2 días
    expect(RestockPlanner.horizon(with_('Lunes'), now), 9);
    // Pasa hoy: hasta la próxima semana
    expect(RestockPlanner.horizon(with_('Sábado'), now), 7);
    expect(RestockPlanner.horizon(null, now), RestockPlanner.defaultHorizon);
  });

  test('con ventas sugiere lo que se venderá y explica por qué', () {
    // 12 vendidos en 30 días = 0,4 por día; 14 días → 6; hay 3 → pedir 3 (mínimo 5 → objetivo 6)
    final item = RestockOrderItem.suggested(cafe(), sold: {'cafe': 12}, horizon: 14, now: now);
    expect(item.orderQty, 3);
    expect(item.why, 'Vendes 3 por semana; te alcanza para 7 días');
    // Vende mucho más: pide más que el doble del mínimo
    final fast = RestockOrderItem.suggested(cafe(), sold: {'cafe': 90}, horizon: 14, now: now);
    expect(fast.orderQty, 42 - 3);
  });

  test('sin ventas se queda la regla del doble del mínimo', () {
    final item = RestockOrderItem.suggested(cafe(), now: now);
    expect(item.orderQty, 7);
    expect(item.why, isNull);
  });

  test('un producto nuevo cuenta solo los días que lleva', () {
    expect(RestockPlanner.perDay(10, createdAt: now.subtract(const Duration(days: 5)), now: now), 2);
    expect(RestockPlanner.perDay(10, createdAt: DateTime(2025, 1, 1), now: now), closeTo(10 / 30, 0.0001));
  });

  test('pide aunque no esté en el mínimo si no alcanza hasta la visita', () {
    final p = cafe(stock: 8, min: 2);
    expect(RestockOrderItem.needsRestock(p, now: now), isFalse);
    expect(RestockOrderItem.needsRestock(p, sold: {'cafe': 60}, horizon: 9, now: now), isTrue);
  });

  test('textos: agotado, menos de un día y ventas al mes', () {
    expect(RestockPlanner.why(2, 0), 'Vendes 14 por semana; está agotado');
    expect(RestockPlanner.why(3, 2), 'Vendes 21 por semana; te alcanza para menos de un día');
    expect(RestockPlanner.why(0.1, 1), 'Vendes 3 al mes; te alcanza para 10 días');
  });
}
