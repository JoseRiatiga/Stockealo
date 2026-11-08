import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/store/data/online_store_service.dart';
import 'package:stockealo/store_web/store_page.dart';

const _store = PublicStore(
  slug: 'dona-ana',
  whatsapp: '573001234567',
  welcome: 'Domicilios gratis en el barrio',
  businessName: 'Doña Ana',
  currency: 'COP',
  products: [
    StoreProduct(id: '1', name: 'Arroz', category: 'Granos', price: 5000),
    StoreProduct(id: '2', name: 'Café', category: 'Bebidas', price: 12000, stock: 1),
  ],
);

Future<void> _pump(WidgetTester tester, PublicStore? store, {Size size = const Size(1080, 2400), double ratio = 3}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: StorePage(slug: 'dona-ana', loader: (_) async => store),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('muestra la tienda, filtra por categoría y arma el pedido', (tester) async {
    await _pump(tester, _store);
    expect(find.text('Doña Ana'), findsOneWidget);
    expect(find.text('Domicilios gratis en el barrio'), findsOneWidget);
    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Café'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Bebidas'));
    await tester.pumpAndSettle();
    expect(find.text('Arroz'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Todo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Agregar uno').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Ver pedido · 2'), findsOneWidget);

    // El café solo tiene 1 unidad: no deja agregar más
    await tester.tap(find.text('Agregar').first);
    await tester.pumpAndSettle();
    final cafePlus = tester.widgetList<IconButton>(find.widgetWithIcon(IconButton, Icons.add_rounded)).last;
    expect(cafePlus.onPressed, isNull);

    await tester.tap(find.textContaining('Ver pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Tu pedido'), findsOneWidget);
    expect(find.text('Enviar pedido por WhatsApp'), findsOneWidget);
  });

  testWidgets('una tienda que no existe o está apagada lo dice', (tester) async {
    await _pump(tester, null);
    expect(find.text('Esta tienda no está disponible en este momento.'), findsOneWidget);
  });

  testWidgets('en un computador ancho el botón del pedido se ve (no queda en blanco)', (tester) async {
    await _pump(tester, _store, size: const Size(1920, 1080), ratio: 1);
    await tester.tap(find.text('Agregar').first);
    await tester.pumpAndSettle();
    final button = find.textContaining('Ver pedido · 1');
    expect(button, findsOneWidget);
    final size = tester.getSize(find.ancestor(of: button, matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(size.width, greaterThan(300)); // antes quedaba sin espacio
    expect(tester.takeException(), isNull);
  });
}
