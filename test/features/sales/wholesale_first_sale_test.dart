import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/services/phone_alerts_service.dart';
import 'package:stockealo/features/products/models/price_tier.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/sales/data/sales_repository.dart';
import 'package:stockealo/features/sales/data/sell_cart.dart';
import 'package:stockealo/features/sales/models/cart_item.dart';
import 'package:stockealo/features/sales/models/payment_method.dart';
import 'package:stockealo/features/sales/models/promotion.dart';
import 'package:stockealo/features/store/data/online_store_service.dart';

void main() {
  final now = DateTime(2026, 11, 22);
  const tiers = [PriceTier(12, 1800), PriceTier(24, 1600)];

  Product gaseosa({List<PriceTier> priceTiers = tiers, int stock = 100}) => Product(
        id: 'gas', businessId: 'b', code: 'G1', name: 'Gaseosa', category: 'Bebidas',
        purchasePrice: 1200, salePrice: 2000, stock: stock, createdAt: now, updatedAt: now, priceTiers: priceTiers,
      );

  Promotion percent(int off) => Promotion(
        id: 'p', businessId: 'b', name: 'Semana', kind: Promotion.percent, percentOff: off.toDouble(),
        startsAt: DateTime(2020), endsAt: DateTime(2100), createdAt: now, updatedAt: now,
      );

  final cart = SellCart.instance;
  setUp(() {
    cart.reset();
    cart.setPromotions(const []);
    cart.setWholesale(true);
  });
  tearDown(() {
    cart.reset();
    cart.setWholesale(false);
  });

  test('escalones: se limpian, se ordenan y el precio baja con la cantidad (0.17.0)', () {
    final clean = PriceTier.clean(const [PriceTier(24, 1600), PriceTier(1, 100), PriceTier(12, 1800), PriceTier(36, 1700), PriceTier(48, 2500)],
        basePrice: 2000);
    expect(clean, const [PriceTier(12, 1800), PriceTier(24, 1600)]);
    expect(PriceTier.parse(PriceTier.encode(clean)), clean);
    expect(PriceTier.parse('no es json'), isEmpty);
    expect(PriceTier.parse([{'min': 6, 'price': 900}]), const [PriceTier(6, 900)]);
    final p = gaseosa();
    expect(p.unitPriceFor(11), 2000);
    expect(p.unitPriceFor(12), 1800);
    expect(p.unitPriceFor(30), 1600);
    expect(Product.fromMap(p.toMap()).priceTiers, tiers);
  });

  test('Vender aplica el precio por mayor al llegar a la cantidad y lo quita al bajar', () {
    cart.add(gaseosa());
    expect(cart.setQuantity(0, 12), isNull);
    expect(cart.lines.single.wholesale, isTrue);
    expect(cart.total, 12 * 1800);
    cart.setQuantity(0, 24);
    expect(cart.total, 24 * 1600);
    cart.setQuantity(0, 5);
    expect(cart.lines.single.wholesale, isFalse);
    expect(cart.total, 5 * 2000);
  });

  test('sin Pro no hay precio por mayor; un precio cotizado no se toca', () {
    cart.setWholesale(false);
    cart.add(gaseosa());
    cart.setQuantity(0, 12);
    expect(cart.total, 12 * 2000);
    cart.setWholesale(true);
    expect(cart.total, 12 * 1800);
    final quoted = CartItem(product: gaseosa(), quantity: 12, customUnitPrice: 1900);
    expect(quoted.autoPrice, isFalse);
  });

  test('con promoción se queda lo mejor para el cliente, sin sumar las dos', () {
    // 20 %: 2.000 → 1.600 es mejor que el escalón de 1.800
    cart.setPromotions([percent(20)]);
    cart.add(gaseosa());
    cart.setQuantity(0, 12);
    expect(cart.lines.single.wholesale, isFalse);
    expect(cart.total, closeTo(12 * 1600, 0.5));
    // 5 %: 1.900 → el escalón de 1.800 sale mejor y la promoción no se suma
    cart.setPromotions([percent(5)]);
    expect(cart.lines.single.wholesale, isTrue);
    expect(cart.lines.single.promotion, isNull);
    expect(cart.total, 12 * 1800);
  });

  test('la tienda muestra y cobra el precio por mayor', () {
    final p = StoreProduct.fromJson({
      'id': 'gas', 'name': 'Gaseosa', 'category': 'Bebidas', 'price': 2000,
      'price_tiers': [{'min': 12, 'price': 1800}],
    });
    expect(p.tiersText((v) => '\$${v.round()}'), 'Desde 12: \$1800 c/u');
    expect(CartLine(p, 11).subtotal, 22000);
    final line = CartLine(p, 12);
    expect(line.wholesale, isTrue);
    expect(line.unitPrice, 1800);
    expect(line.subtotal, 21600);
  });

  test('venta de práctica: el recibo sin guardar nada', () {
    cart.startFirstSale(gaseosa(), practice: true);
    expect(cart.practice, isTrue);
    final sales = SalesRepository.practiceSale(
      businessId: 'b',
      items: cart.lines,
      paymentMethod: PaymentMethod.cash,
      discountAmount: 500,
      now: now,
    );
    expect(sales.single.totalAmount, 1500);
    expect(sales.single.invoiceNumber, '#PRACTICA');
    cart.clear();
    expect(cart.practice, isFalse);
  });

  test('aviso de la primera venta: a los 2 días, una sola vez', () {
    final created = DateTime(2026, 11, 20, 15);
    // Recién creado: el 22 a las 10 a. m.
    expect(PhoneAlertsService.firstSaleWhen(createdAt: created, now: DateTime(2026, 11, 20, 16)), DateTime(2026, 11, 22, 10));
    // Abre la app el 25 por la tarde: al día siguiente a las 10
    expect(PhoneAlertsService.firstSaleWhen(createdAt: created, now: DateTime(2026, 11, 25, 15)), DateTime(2026, 11, 26, 10));
    // Ya se programó y ya pasó: no se vuelve a avisar
    expect(
      PhoneAlertsService.firstSaleWhen(createdAt: created, now: DateTime(2026, 11, 23), scheduled: DateTime(2026, 11, 22, 10)),
      isNull,
    );
  });
}
