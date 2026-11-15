import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:stockealo/core/services/maintenance_service.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/products/presentation/widgets/story_catalog_modal.dart';
import 'package:stockealo/features/store/data/online_store_service.dart';
import 'package:stockealo/features/store/presentation/widgets/store_qr_sheet.dart';
import 'package:stockealo/store_web/store_page.dart';

/// 0.16.0, fase 3: vender por redes
void main() {
  final business = Business(id: 'b1', userId: 'u1', name: 'Variedades Rosita', icon: 'tienda', createdAt: DateTime(2026));
  final now = DateTime(2026, 11, 15);
  Product product(String id, String name, double price, {double? before}) => Product(
        id: id, businessId: 'b1', code: id, name: name, category: 'Granos', purchasePrice: 1000, salePrice: price,
        stock: 5, createdAt: now, updatedAt: now, comparePrice: before,
      );
  final products = [
    product('1', 'Aceite Premier 1 L', 12900, before: 14500),
    product('2', 'Arroz Diana 500 g', 4200),
    product('3', 'Huevos AA x30', 18900),
  ];
  const store = OnlineStoreConfig(
    slug: 'rosita',
    enabled: true,
    whatsapp: '573001234567',
    look: StoreLook(hashtags: ['#VariedadesRosita', '#Barrio']),
  );

  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
    }
    await loader.load();
  });

  test('hashtags: se limpian, no se repiten y el nombre del negocio va primero', () {
    expect(StoreLook.parseHashtags('#VariedadesRosita, domicilios  #domicilios ;#Mi-Barrio #'), ['#VariedadesRosita', '#domicilios', '#MiBarrio']);
    expect(StoreLook.nameHashtag('Variedades rosita'), '#VariedadesRosita');
    expect(StoreLook.cleanHashtag('##Pan Fresco'), '#PanFresco');
    expect(StoreLook.fromJson({'hashtags': ['#Uno', 'mal espacio', 3]}).hashtags, ['#Uno', '#malespacio']);
    final text = StoryCatalogModal.caption(
      business: business,
      products: [products.first],
      storeUrl: store.url,
      ownHashtags: store.look.hashtags,
      price: (p) => '\$${p.salePrice.round()}',
    );
    expect(text, contains('Aceite Premier 1 L a \$12900'));
    expect(text, contains('Pide aquí 👉 stockealo.online/tienda/rosita'));
    final tags = text.split('\n').last.split(' ');
    expect(tags.first, '#VariedadesRosita');
    expect(tags.where((t) => t.toLowerCase() == '#variedadesrosita').length, 1, reason: 'no se repite');
    expect(tags, containsAll(['#Barrio', '#TiendaDeBarrio']), reason: 'los propios y los de su tipo de negocio');
  });

  test('el link de un producto', () {
    expect(store.productUrl('abc'), 'https://stockealo.online/tienda/rosita?p=abc');
    expect(sharedProductFromUri(Uri.parse('https://stockealo.online/tienda/?t=rosita&p=abc')), 'abc');
    expect(slugFromUri(Uri.parse('https://stockealo.online/tienda/?t=rosita&p=abc')), 'rosita');
    expect(sharedProductFromUri(Uri.parse('https://stockealo.online/tienda/rosita')), isNull);
  });

  Future<void> pumpPhone(WidgetTester tester, Widget child, {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  testWidgets('Instagram: los 4 formatos caben, con QR, link y cinta de oferta', (tester) async {
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => StoryCatalogModal.show(context: context, business: business, products: products, store: store),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('OFERTA'), findsWidgets);
    expect(find.text('Pide en stockealo.online/tienda/rosita'), findsWidgets);
    for (final f in PostFormat.values) {
      await tester.tap(find.widgetWithText(ChoiceChip, f.label));
      await tester.pumpAndSettle();
      for (final d in f == PostFormat.carousel ? const [1] : const [1, 2, 4]) {
        if (f != PostFormat.carousel) {
          await tester.tap(find.descendant(of: find.byType(SegmentedButton<int>), matching: find.text('$d')));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull, reason: '${f.label} con $d');
      }
    }
    // El carrusel: un producto por imagen
    expect(find.text('Compartir 3'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'QR'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('el QR de la tienda cabe en el celular', (tester) async {
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => StoreQrSheet.show(context, business: business, store: store),
          child: const Text('abrir'),
        ),
      ),
      size: const Size(360, 800),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Escanea y pide aquí'), findsOneWidget);
    expect(find.text('Cartel para imprimir (PDF)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final pdf = await StoreQrSheet.posterPdf(businessName: business.name, url: store.url);
    expect(pdf.length, greaterThan(1000));
  });

  testWidgets('la tienda con un producto compartido: va primero y avisa', (tester) async {
    const public = PublicStore(
      slug: 'rosita',
      whatsapp: '573001234567',
      businessName: 'Variedades Rosita',
      currency: 'COP',
      template: StoreTemplate.market,
      products: [
        StoreProduct(id: 'a', name: 'Arroz', category: 'Granos', price: 4200),
        StoreProduct(id: 'h', name: 'Huevos AA x30', category: 'Granos', price: 18900),
      ],
    );
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: StorePage(slug: 'rosita', sharedProductId: 'h', loader: (_) async => public, maintenanceLoader: () async => MaintenanceState.none),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Te compartieron este producto: Huevos AA x30'), findsOneWidget);
    final huevos = tester.getTopLeft(find.text('Huevos AA x30').last).dy;
    final arroz = tester.getTopLeft(find.text('Arroz')).dy;
    expect(huevos, lessThan(arroz), reason: 'el compartido va de primero');
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Te compartieron'), findsNothing);
  });
}
