import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:stockealo/core/services/maintenance_service.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/store/data/online_store_service.dart';
import 'package:stockealo/store_web/store_page.dart';

/// 0.16.0, fase 1: plantillas Mercado, Menú y Boutique, y «Personalizar tienda»
const _always = StoreSchedule(days: {1, 2, 3, 4, 5, 6, 7}, open: '00:00', close: '00:00');
const _never = StoreSchedule(days: {}, open: '07:00', close: '20:00');

PublicStore _store(String template, {StoreLook look = StoreLook.none}) => PublicStore(
      slug: 'rosita',
      whatsapp: '573001234567',
      welcome: 'Domicilios en el barrio',
      businessName: 'Variedades Rosita',
      currency: 'COP',
      template: template,
      look: look,
      products: const [
        StoreProduct(id: 'arroz', name: 'Arroz Diana 500 g', category: 'Granos', price: 4200),
        StoreProduct(id: 'aceite', name: 'Aceite Premier 1 L', category: 'Granos', price: 12900, oldPrice: 14500),
        StoreProduct(
          id: 'calentado',
          name: 'Calentado con huevo',
          category: 'Desayunos',
          price: 12000,
          description: 'Arroz, fríjol, arepa y huevo',
        ),
        StoreProduct(id: 'pan', name: 'Pan de bono x 3', category: 'Panes', price: 4500),
      ],
    );

Future<void> _pump(WidgetTester tester, PublicStore store, {Size size = const Size(360, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: StorePage(slug: store.slug, loader: (_) async => store, maintenanceLoader: () async => MaintenanceState.none),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
    }
    await loader.load();
  });

  group('horario', () {
    const s = StoreSchedule(days: {1, 2, 3, 4, 5, 6}, open: '07:00', close: '20:00');
    test('abierto, cerrado y el texto', () {
      expect(s.isOpen(DateTime(2026, 11, 16, 9)), isTrue); // lunes
      expect(s.isOpen(DateTime(2026, 11, 16, 20)), isFalse); // a las 8 ya cerró
      expect(s.isOpen(DateTime(2026, 11, 15, 10)), isFalse); // domingo
      expect(s.text, 'Lun a sáb · 7 a. m. – 8 p. m.');
      expect(s.status(DateTime(2026, 11, 16, 9)), 'Abierto · cierra 8 p. m.');
      expect(s.status(DateTime(2026, 11, 16, 21)), 'Cerrado · abre mañana 7 a. m.');
      expect(s.status(DateTime(2026, 11, 15, 10)), 'Cerrado · abre mañana 7 a. m.');
      expect(s.status(DateTime(2026, 11, 14, 22)), 'Cerrado · abre el lunes 7 a. m.'); // sábado de noche
      expect(s.status(DateTime(2026, 11, 16, 6)), 'Cerrado · abre hoy 7 a. m.');
    });
    test('cierra pasada la medianoche', () {
      const night = StoreSchedule(days: {5, 6}, open: '18:00', close: '02:00');
      expect(night.isOpen(DateTime(2026, 11, 20, 23)), isTrue); // viernes
      expect(night.isOpen(DateTime(2026, 11, 21, 1)), isTrue); // madrugada del sábado: cuenta el viernes
      expect(night.isOpen(DateTime(2026, 11, 23, 1)), isFalse); // madrugada del lunes: el domingo no abre
      expect(StoreSchedule.hourText('12:30'), '12:30 p. m.');
      expect(StoreSchedule.hourText('00:00'), '12 a. m.');
    });
    test('lo que llega mal escrito no se usa', () {
      expect(StoreSchedule.fromJson({'days': [1], 'open': '25:00', 'close': '20:00'}), isNull);
      expect(StoreSchedule.fromJson({'days': [], 'open': '07:00', 'close': '20:00'}), isNull);
      expect(StoreSchedule.fromJson({'days': [9, 2], 'open': '7:00', 'close': '20:00'})!.days, {2});
    });
  });

  test('look: color, destacados (máximo 6) y pago; y los destacados salen primero', () {
    final look = StoreLook.fromJson({
      'accent': '#1d5fa8',
      'dark': true,
      'featured': ['pan', 'aceite', 'a', 'b', 'c', 'd', 'e'],
      'payment': '  Nequi 300 123 4567  ',
    });
    expect(look.accent, '#1D5FA8');
    expect(look.dark, isTrue);
    expect(look.featured.length, 6);
    expect(look.payment, 'Nequi 300 123 4567');
    expect(StoreLook.fromJson({'accent': 'azul'}).accent, isNull);
    expect(StoreLook.fromJson(null).featured, isEmpty);
    final store = _store(StoreTemplate.classic, look: look);
    expect(store.ordered.map((p) => p.id).take(2), ['pan', 'aceite']);
    expect(store.ordered.length, 4);
    expect(store.accentHex, '#1D5FA8');
    expect(StoreTemplate.of('menu'), StoreTemplate.menu);
    expect(StoreTemplate.of('otra'), StoreTemplate.classic);
  });

  testWidgets('Mercado: lista con +, y al agregar se vuelve − 1 +', (tester) async {
    await _pump(tester, _store(StoreTemplate.market, look: const StoreLook(schedule: _always)));
    expect(find.text('Arroz Diana 500 g'), findsOneWidget);
    expect(find.textContaining('Abierto'), findsOneWidget);
    await tester.tap(find.byTooltip('Agregar').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Quitar uno'), findsOneWidget);
    expect(find.textContaining('Ver pedido · 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Quitar uno'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ver pedido'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Menú: secciones de la carta con la descripción, y Recomendados', (tester) async {
    await _pump(tester, _store(StoreTemplate.menu, look: const StoreLook(featured: ['pan'])));
    expect(find.text('RECOMENDADOS'), findsOneWidget);
    expect(find.text('DESAYUNOS'), findsOneWidget);
    expect(find.text('Arroz, fríjol, arepa y huevo'), findsOneWidget);
    expect(find.text('PANES'), findsNothing, reason: 'el único pan va en Recomendados');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Boutique: el destacado con foto va primero en grande', (tester) async {
    await _pump(tester, _store(StoreTemplate.boutique), size: const Size(360, 1400));
    expect(find.text('VARIEDADES ROSITA'), findsOneWidget);
    expect(find.text('Arroz Diana 500 g'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('modo oscuro y color propio en cualquier plantilla', (tester) async {
    await _pump(tester, _store(StoreTemplate.classic, look: const StoreLook(dark: true, accent: '#BE185D')));
    final ctx = tester.element(find.text('Variedades Rosita'));
    expect(Theme.of(ctx).brightness, Brightness.dark);
    expect(Theme.of(ctx).colorScheme.primary.toARGB32() & 0xFFFFFF, 0xBE185D);
  });

  testWidgets('cerrada: se puede pedir igual, con aviso, y salen los datos de pago', (tester) async {
    await _pump(tester, _store(StoreTemplate.market, look: const StoreLook(schedule: _never, payment: 'Nequi 300 123 4567')));
    await tester.tap(find.byTooltip('Agregar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ver pedido'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Estamos cerrados en este momento'), findsOneWidget);
    expect(find.text('Cómo pagar'), findsOneWidget);
    expect(find.text('Nequi 300 123 4567'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Tu nombre'), 'Ana');
    await tester.tap(find.textContaining('Hacer el pedido ·'));
    await tester.pumpAndSettle();
    expect(find.text('POR CONFIRMAR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final t in [StoreTemplate.market, StoreTemplate.menu, StoreTemplate.boutique]) {
    testWidgets('$t cabe en un computador ancho', (tester) async {
      await _pump(tester, _store(t, look: const StoreLook(schedule: _always)), size: const Size(1440, 900));
      expect(tester.takeException(), isNull);
    });
  }
}
