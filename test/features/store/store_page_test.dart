import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
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

/// Plantilla Moda: ofertas, tallas y colores
const _moda = PublicStore(
  slug: 'nova-moda',
  whatsapp: '573001234567',
  welcome: 'Pide por WhatsApp y recoge en la tienda.',
  businessName: 'Nova Moda',
  currency: 'COP',
  color: '#E0672A',
  template: StoreTemplate.fashion,
  heroTitle: 'Chaquetas y abrigos para el frío',
  products: [
    StoreProduct(
      id: 'a',
      name: 'Abrigo largo camel',
      category: 'Chaquetas y abrigos',
      price: 189000,
      variants: [StoreVariant(id: 'a-s', size: 'S'), StoreVariant(id: 'a-m', size: 'M')],
    ),
    StoreProduct(
      id: 'b',
      name: 'Chaqueta acolchada verde',
      category: 'Chaquetas y abrigos',
      price: 129000,
      oldPrice: 159000,
      variants: [StoreVariant(id: 'b-l', size: 'L', hex: '#3F4A36')],
    ),
    StoreProduct(id: 'c', name: 'Buzo con capota', category: 'Buzos', price: 79000),
  ],
);

Future<void> _pump(WidgetTester tester, PublicStore? store, {Size size = const Size(1080, 2400), double ratio = 3, GlobalKey? key}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    builder: key == null ? null : (context, child) => RepaintBoundary(key: key, child: child),
    home: StorePage(slug: 'dona-ana', loader: (_) async => store),
  ));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, GlobalKey key, String name) async {
  final out = Platform.environment['PREVIEW_OUT'];
  if (out == null) return;
  await tester.runAsync(() async {
    final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    for (final family in ['Inter', 'monospace']) {
      final loader = FontLoader(family);
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
      }
      await loader.load();
    }
  });

  testWidgets('Clásica: muestra la tienda, filtra por categoría y arma el pedido', (tester) async {
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
    final add = find.byTooltip('Agregar al pedido');
    await tester.tap(add.first); // arroz
    await tester.pumpAndSettle();
    await tester.tap(add.first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Ver pedido · 2'), findsOneWidget);

    // El café solo tiene 1 unidad: después de agregarlo, no deja más
    await tester.tap(add.last);
    await tester.pumpAndSettle();
    final cafeAdd = tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Agregar al pedido').last, matching: find.byType(IconButton)).first);
    expect(cafeAdd.onPressed, isNull);

    await tester.tap(find.textContaining('Ver pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Tu pedido'), findsOneWidget);
    // Sin nombre no deja pedir
    await tester.tap(find.text('Hacer el pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Escribe tu nombre para que la tienda sepa quién pide'), findsOneWidget);
    expect(find.text('POR CONFIRMAR'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Tu nombre'), 'Ana');
    await tester.tap(find.text('Hacer el pedido'));
    await tester.pumpAndSettle();
    // Sale el tiquete «Por confirmar» con el botón de WhatsApp
    expect(find.text('POR CONFIRMAR'), findsOneWidget);
    expect(find.text('Enviar pedido por WhatsApp'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('una tienda que no existe o está apagada lo dice', (tester) async {
    await _pump(tester, null);
    expect(find.text('Esta tienda no está disponible en este momento.'), findsOneWidget);
  });

  testWidgets('en un computador ancho el botón del pedido se ve (no queda en blanco)', (tester) async {
    await _pump(tester, _store, size: const Size(1920, 1080), ratio: 1);
    await tester.tap(find.byTooltip('Agregar al pedido').first);
    await tester.pumpAndSettle();
    final button = find.textContaining('Ver pedido · 1');
    expect(button, findsOneWidget);
    final size = tester.getSize(find.ancestor(of: button, matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(size.width, greaterThan(300)); // antes quedaba sin espacio
    expect(tester.takeException(), isNull);
  });

  testWidgets('Moda: portada, ofertas, filtro por talla y elegir la talla al agregar', (tester) async {
    final key = GlobalKey();
    await _pump(tester, _moda, size: const Size(1440, 1400), ratio: 1, key: key);
    expect(tester.takeException(), isNull);
    expect(find.text('NOVA MODA'), findsOneWidget);
    expect(find.text('Chaquetas y abrigos para el frío'), findsOneWidget);
    expect(find.text('OFERTA'), findsOneWidget);
    expect(find.textContaining('159.000'), findsOneWidget, reason: 'el precio de antes, tachado');
    await _save(tester, key, 'tienda_moda');

    // Filtro por talla M: solo el abrigo
    await tester.tap(find.widgetWithText(ChoiceChip, 'M'));
    await tester.pumpAndSettle();
    expect(find.text('Abrigo largo camel'), findsOneWidget);
    expect(find.text('Buzo con capota'), findsNothing);

    // Agregar pide la talla
    await tester.tap(find.byTooltip('Elegir talla o color').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('S').last);
    await tester.pumpAndSettle();
    expect(find.text('1 en tu pedido'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Moda en el celular', (tester) async {
    final key = GlobalKey();
    await _pump(tester, _moda, size: const Size(390, 1600), ratio: 1, key: key);
    expect(tester.takeException(), isNull);
    expect(find.text('Filtros'), findsOneWidget);
    await _save(tester, key, 'tienda_moda_celular');

    // El carrito es una página completa con el total y «Hacer el pedido» fijos abajo
    await tester.tap(find.byTooltip('Elegir talla o color').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('S').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ver pedido'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Tu pedido'), findsOneWidget);
    expect(find.text('Hacer el pedido'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _save(tester, key, 'tienda_carrito_celular');
  });
}
