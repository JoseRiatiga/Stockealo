import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:stockealo/core/services/maintenance_service.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/store/data/online_store_service.dart';
import 'package:stockealo/features/store/presentation/screens/store_stats_screen.dart';
import 'package:stockealo/store_web/store_page.dart';

/// 0.16.0, fase 4: estadísticas de la tienda
void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
    }
    await loader.load();
  });

  test('los números: totales, visitas que piden y lo pedido por producto', () {
    final s = StoreStats.fromJson({
      'days': [
        {'day': '2026-11-14', 'visits': 100, 'adds': 20, 'orders': 5, 'total': 250000},
        {'day': '2026-11-15', 'visits': '48', 'adds': 10, 'orders': 3, 'total': 90000.5},
      ],
      'top_ordered': [
        {'product_id': 'aceite', 'name': 'Aceite', 'qty': 14, 'total': 180600},
      ],
      'top_added': [
        {'product_id': 'aceite', 'name': 'Aceite', 'adds': 20},
        {'product_id': 'pan', 'name': 'Pan', 'adds': 8},
      ],
      'shared': 36,
      'qr': 21,
    });
    expect(s.visits, 148);
    expect(s.orders, 8);
    expect(s.adds, 30);
    expect(s.total, closeTo(340000.5, 0.01));
    expect(s.conversion, closeTo(8 / 148, 1e-9));
    expect(s.orderedOf('aceite'), 14);
    expect(s.orderedOf('pan'), 0);
    expect(s.fromQr, 21);
    expect(const StoreStats().conversion, isNull);
    const store = OnlineStoreConfig(slug: 'rosita', enabled: true, whatsapp: '57300');
    expect(store.qrUrl, 'https://stockealo.online/tienda/rosita?src=qr');
    expect(sourceFromUri(Uri.parse('https://stockealo.online/tienda/?t=rosita&src=qr')), 'qr');
  });

  testWidgets('la tienda cuenta la visita una vez, de dónde llegó y cada producto agregado una vez', (tester) async {
    const public = PublicStore(
      slug: 'rosita',
      whatsapp: '573001234567',
      businessName: 'Variedades Rosita',
      currency: 'COP',
      template: StoreTemplate.market,
      products: [
        StoreProduct(id: 'a', name: 'Arroz', category: 'Granos', price: 4200),
        StoreProduct(id: 'h', name: 'Huevos', category: 'Granos', price: 18900),
      ],
    );
    final events = <String>[];
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: StorePage(
        slug: 'rosita',
        source: 'qr',
        sharedProductId: 'h',
        loader: (_) async => public,
        maintenanceLoader: () async => MaintenanceState.none,
        tracker: (slug, kind, product) => events.add('$kind${product == null ? '' : ':$product'}'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(events, ['VISIT', 'QR', 'SHARED:h']);
    await tester.tap(find.byTooltip('Agregar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Agregar otro').first);
    await tester.pumpAndSettle();
    expect(events.where((e) => e.startsWith('ADD')).length, 1, reason: 'el mismo producto cuenta una vez por visita');
    // Sin «tracker» y con la tienda de prueba (loader), no cuenta nada en la nube
    expect(tester.takeException(), isNull);
  });

  testWidgets('la pantalla de estadísticas cabe en el celular', (tester) async {
    tester.view.physicalSize = const Size(360, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 11, 15);
    Future<StoreStats> loader(DateTime from, DateTime to) async => StoreStats(
          days: [
            for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1)))
              StoreStatsDay(day: d, visits: d.day * 3, adds: d.day, orders: d.day % 3, total: d.day * 10000.0),
          ],
          topOrdered: const [StoreStatsItem(productId: 'a', name: 'Aceite Premier 1 L con un nombre muy largo', quantity: 14, total: 180600)],
          topAdded: const [StoreStatsItem(productId: 'a', name: 'Aceite Premier 1 L', quantity: 20)],
          fromShared: 36,
          fromQr: 21,
        );
    final business = Business(id: 'b1', userId: 'u1', name: 'Variedades Rosita', createdAt: DateTime(2026));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: StoreStatsScreen(business: business, loader: loader, now: now)));
    await tester.pumpAndSettle();
    expect(find.text('Visitas'), findsOneWidget);
    expect(find.text('Lo más pedido'), findsOneWidget);
    expect(find.text('21 visitas'), findsOneWidget);
    expect(find.textContaining('que antes'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('30 días'));
    await tester.pumpAndSettle();
    expect(find.text('Últimos 30 días'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
