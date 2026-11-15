import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/products/data/pricing.dart';

/// 0.15.0: precio sugerido por margen
void main() {
  test('el precio deja el margen pedido sobre lo que se cobra, redondeado a 100', () {
    // Costo 6.000 con 40 %: 10.000 (ganancia 4.000 = 40 % de 10.000)
    expect(Pricing.priceForMargin(6000, 40), 10000);
    // Costo 3.000 con 30 %: 4.285,7 → 4.300
    expect(Pricing.priceForMargin(3000, 30), 4300);
    final p = Pricing.priceForMargin(3000, 30);
    expect((p - 3000) / p * 100, greaterThanOrEqualTo(30));
    // Sin costo o margen imposible: queda el costo
    expect(Pricing.priceForMargin(0, 30), 0);
    expect(Pricing.priceForMargin(5000, 100), 5000);
    expect(Pricing.priceForMargin(3000, 30, roundTo: 1), closeTo(4285.71, 0.01));
  });
}
