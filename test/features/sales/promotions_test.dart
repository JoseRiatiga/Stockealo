import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/sales/models/promotion.dart';
import 'package:stockealo/features/store/data/online_store_service.dart';

/// Promociones 0.13.4: % de descuento y lleva X, paga Y, con fechas.
void main() {
  final start = DateTime(2026, 11, 20);
  final end = DateTime(2026, 12, 1);
  final inside = DateTime(2026, 11, 25, 10);

  Promotion promo({
    String kind = Promotion.percent,
    double pct = 20,
    int buy = 2,
    int pay = 1,
    String scope = Promotion.scopeAll,
    String? category,
    List<String> ids = const [],
    bool active = true,
  }) =>
      Promotion(
        id: 'p-$kind-$pct-$buy$pay-$scope',
        businessId: 'b',
        name: kind == Promotion.percent ? 'Fin de mes' : '2×1 en gaseosas',
        kind: kind,
        percentOff: pct,
        buyQty: buy,
        payQty: pay,
        scope: scope,
        category: category,
        productIds: ids,
        startsAt: start,
        endsAt: end,
        isActive: active,
        createdAt: start,
        updatedAt: start,
      );

  test('% de descuento y lleva X, paga Y', () {
    expect(promo(pct: 20).discountFor(10000, 3), 6000);
    expect(promo(pct: 20).badge, '−20 %');
    final twoForOne = promo(kind: Promotion.buyXPayY);
    expect(twoForOne.badge, '2×1');
    expect(twoForOne.discountFor(3000, 1), 0, reason: 'con uno solo no hay regalo');
    expect(twoForOne.discountFor(3000, 2), 3000);
    expect(twoForOne.discountFor(3000, 5), 6000, reason: 'dos pares: dos de regalo');
    expect(promo(kind: Promotion.buyXPayY, buy: 3, pay: 2).discountFor(1000, 7), 2000);
  });

  test('solo vale dentro de las fechas, encendida y para sus productos', () {
    final p = promo(scope: Promotion.scopeCategory, category: 'Bebidas');
    expect(p.isLiveAt(inside), isTrue);
    expect(p.isLiveAt(DateTime(2026, 11, 19, 23)), isFalse);
    expect(p.isLiveAt(end), isFalse, reason: 'se apaga sola al terminar');
    expect(promo(active: false).isLiveAt(inside), isFalse);
    expect(p.appliesTo(productId: 'x', category: ' bebidas '), isTrue);
    expect(p.appliesTo(productId: 'x', category: 'Snacks'), isFalse);
    final marked = promo(scope: Promotion.scopeProducts, ids: ['a']);
    expect(marked.appliesTo(productId: 'a', category: ''), isTrue);
    expect(marked.appliesTo(productId: 'b', category: ''), isFalse);
  });

  test('se aplica la que más rebaja', () {
    final all = [promo(pct: 10), promo(kind: Promotion.buyXPayY)];
    final best = Promotion.best(all, productId: 'a', category: '', unitPrice: 2000, quantity: 2, at: inside);
    expect(best!.kind, Promotion.buyXPayY, reason: '2×1 rebaja 2.000; el 10 % rebaja 400');
    expect(Promotion.best(all, productId: 'a', category: '', unitPrice: 2000, quantity: 1, at: inside)!.percentOff, 10);
    expect(Promotion.best(all, productId: 'a', category: '', unitPrice: 2000, quantity: 2, at: end), isNull);
  });

  test('se guarda y se lee igual', () {
    final p = promo(scope: Promotion.scopeProducts, ids: ['a', 'b']);
    final back = Promotion.fromMap(p.toMap());
    expect(back.productIds, ['a', 'b']);
    expect(back.startsAt, start);
    expect(back.endsAt, end);
    expect(back.isActive, isTrue);
  });

  test('tienda: % rebaja el precio y tacha el de antes; 2×1 regala en el carrito', () {
    final pct = StoreProduct.fromJson({
      'id': 'a',
      'name': 'Camiseta',
      'price': 25000,
      'promo': {'name': 'Fin de mes', 'kind': 'PERCENT', 'percent_off': 20, 'ends_at': '2026-12-01T05:00:00Z'},
    });
    expect(pct.price, 20000);
    expect(pct.oldPrice, 25000);
    expect(pct.promo!.badge, '−20 %');
    final gift = StoreProduct.fromJson({
      'id': 'b',
      'name': 'Gaseosa',
      'price': 3000,
      'promo': {'name': '2×1', 'kind': 'BUY_X_PAY_Y', 'buy_qty': 2, 'pay_qty': 1},
    });
    expect(gift.price, 3000);
    expect(CartLine(gift, 3).subtotal, 6000, reason: 'lleva 3, paga 2');
    expect(StoreProduct.fromJson({'id': 'c', 'name': 'x', 'price': 1}).promo, isNull);
  });
}
