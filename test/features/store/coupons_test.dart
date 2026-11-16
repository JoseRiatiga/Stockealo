import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/core/utils/coupons.dart';
import 'package:stockealo/core/utils/currency_formatter.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/pro/data/pro_service.dart';
import 'package:stockealo/features/store/data/online_store_service.dart';
import 'package:stockealo/features/store/presentation/screens/store_coupons_screen.dart';

/// 0.16.0, fase 7: cupones Pro y de la tienda
void main() {
  String money(num v) => CurrencyFormatter.formatIn(v, 'COP');

  test('el descuento se calcula igual que en la nube', () {
    expect(CouponText.discountFor(percent: 10, total: 50000), 5000);
    expect(CouponText.discountFor(percent: 15, total: 33333), 5000, reason: 'se redondea');
    expect(CouponText.discountFor(amount: 8000, total: 5000), 5000, reason: 'nunca más que el total');
    expect(CouponText.discountFor(percent: 10, minTotal: 20000, total: 10000), 0, reason: 'no llega al mínimo');
    expect(CouponText.normalize(' bienvenida 10 '), 'BIENVENIDA10');
    expect(CouponText.validStoreCode('ok'), isFalse);
    expect(CouponText.validStoreCode('bienvenida-10'), isTrue);
  });

  test('cada motivo del servidor tiene su mensaje', () {
    expect(CouponText.error('P0001: coupon_min_total:20000', money: money), 'Este cupón es para compras desde \$20.000.');
    expect(CouponText.error('coupon_already_used'), 'Ya usaste este cupón.');
    expect(CouponText.error('coupon_expired'), 'Este cupón venció.');
    expect(CouponText.error('coupon_limit'), contains('1 cupón activo'));
    expect(CouponText.error('coupon_phone_required'), contains('teléfono'));
    expect(CouponText.error('otra cosa'), contains('Inténtalo'));
    // El pago con Wompi también los entiende
    expect(ProService.checkoutErrorMessage('coupon_wrong_plan'), 'Este cupón no sirve para ese plan.');
  });

  test('el estado y los usos del cupón', () {
    final k = Coupon.fromRow({
      'id': 'c1',
      'code': 'BIENVENIDA10',
      'percent': 10,
      'min_total': 20000,
      'max_uses': 50,
      'uses': 50,
      'active': true,
    });
    expect(k.usedUp, isTrue);
    expect(k.usable, isFalse);
    expect(k.stateLabel, 'Agotado');
    expect(k.usesLabel, 'Usado 50 de 50');
    expect(k.discountLabel(money), '10 %');
    final share = k.shareText(storeName: 'Variedades Rosita', storeUrl: 'https://stockealo.online/tienda/rosita', money: money);
    expect(share, contains('BIENVENIDA10'));
    expect(share, contains('desde \$20.000'));
    expect(share, contains('https://stockealo.online/tienda/rosita'));
    final old = Coupon(code: 'X1', amount: 3000, expiresAt: DateTime.now().subtract(const Duration(days: 1)));
    expect(old.stateLabel, 'Venció');
    expect(old.discountLabel(money), '\$3.000');
  });

  test('el pedido de WhatsApp lleva el cupón y el total con descuento', () {
    const arroz = StoreProduct(id: '1', name: 'Arroz', category: '', price: 25000);
    final text = OnlineStoreService.orderMessage(
      businessName: 'Doña Ana',
      lines: const [CartLine(arroz, 2)],
      currency: 'COP',
      couponCode: 'BIENVENIDA10',
      discount: 5000,
    );
    expect(text, contains('Subtotal: \$50.000'));
    expect(text, contains('Cupón BIENVENIDA10: −\$5.000'));
    expect(text, contains('Total: \$45.000'));
  });

  Future<void> pumpScreen(WidgetTester tester, List<Coupon> coupons) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final business = Business(id: 'b1', userId: 'u1', name: 'Variedades Rosita', createdAt: DateTime(2026));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: StoreCouponsScreen(business: business, storeUrl: 'https://stockealo.online/tienda/rosita', loader: () async => coupons),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('la lista de cupones en el celular', (tester) async {
    await pumpScreen(tester, [
      const Coupon(id: 'c1', code: 'BIENVENIDA10', percent: 10, minTotal: 20000, uses: 3),
      const Coupon(id: 'c2', code: 'ENVIOGRATIS', amount: 5000, active: false),
    ]);
    expect(find.text('BIENVENIDA10'), findsOneWidget);
    expect(find.text('Activo'), findsOneWidget);
    expect(find.text('Apagado'), findsOneWidget);
    expect(find.textContaining('10 % de descuento · desde \$20.000 · Usado 3 veces'), findsOneWidget);
    expect(find.text('Compartir cupón'), findsNWidgets(2));
    expect(find.textContaining('Sin Pro puedes tener 1 cupón activo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin cupones invita a crear uno', (tester) async {
    await pumpScreen(tester, const []);
    expect(find.text('Todavía no tienes cupones'), findsOneWidget);
    expect(find.text('Nuevo cupón'), findsOneWidget);
  });

  testWidgets('el formulario revisa el código y el descuento', (tester) async {
    Coupon? saved;
    tester.view.physicalSize = const Size(380, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => saved = await Navigator.push<Coupon>(
                context,
                MaterialPageRoute(builder: (_) => const Scaffold(body: SingleChildScrollView(child: CouponForm(currency: 'COP')))),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cupón'));
    await tester.pumpAndSettle();
    expect(find.textContaining('de 3 a 24'), findsOneWidget);
    expect(find.text('Escribe un porcentaje de 1 a 100.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Código'), 'bienvenida10');
    await tester.enterText(find.widgetWithText(TextField, 'Descuento'), '10');
    await tester.enterText(find.widgetWithText(TextField, 'Compra mínima (opcional)'), '20000');
    await tester.tap(find.text('Guardar cupón'));
    await tester.pumpAndSettle();
    expect(saved?.code, 'BIENVENIDA10');
    expect(saved?.percent, 10);
    expect(saved?.amount, isNull);
    expect(saved?.minTotal, 20000);
    expect(saved?.active, isTrue);
  });
}
