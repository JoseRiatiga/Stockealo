import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/home/navigation/app_places.dart';
import 'package:stockealo/features/home/presentation/widgets/app_header_bar.dart';
import 'package:stockealo/features/home/presentation/widgets/app_menu.dart';

/// El marco de la app (menú y encabezado) en el computador y en el celular, en
/// claro y en oscuro. Con PREVIEW_OUT=<carpeta> guarda una imagen de cada uno.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
  }
  await loader.load();
}

final _business = Business(id: 'b1', userId: 'u1', name: 'Tienda Olinda', color: '#BE185D', icon: 'mascotas', createdAt: DateTime(2026));

AppMenu _menu({bool inDrawer = false, String role = 'OWNER', bool services = true}) => AppMenu(
      selectedId: AppPlace.productos,
      onSelect: (_) {},
      business: _business,
      userName: 'Olinda Pérez',
      userRole: role,
      services: services,
      onSelectBusiness: () {},
      onLogout: () {},
      inDrawer: inDrawer,
    );

Future<void> _save(WidgetTester tester, GlobalKey key, String name) async {
  final out = Platform.environment['PREVIEW_OUT'];
  if (out == null) return;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('computador: menú que sigue el día y encabezado (${brightness.name})', (tester) async {
      await tester.runAsync(_loadInter);
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(brightness),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            body: Row(
              children: [
                _menu(),
                Expanded(
                  child: Column(
                    children: [
                      AppHeaderBar(
                        title: 'Productos',
                        subtitle: 'Catálogo, precios, tallas y colores',
                        business: _business,
                        alertCount: 3,
                        onSearchTap: () {},
                        onNotificationsTap: () {},
                        onNewSale: () {},
                      ),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // El menú sigue el día, agrupado
      for (final label in ['Inicio', 'Vender', 'Ventas', 'Caja', 'Servicios', 'Stock', 'Clientes y proveedores', 'Tienda en línea', 'Reportes', 'Ajustes']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('DÍA A DÍA'), findsOneWidget);
      expect(find.text('Nueva venta'), findsOneWidget);
      expect(find.text('Tienda Olinda'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _save(tester, key, 'computador_${brightness.name}');
    });

    testWidgets('celular: encabezado compacto y menú ☰ (${brightness.name})', (tester) async {
      await tester.runAsync(_loadInter);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final key = GlobalKey();
      final scaffold = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(brightness),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            key: scaffold,
            drawer: Drawer(width: 304, child: _menu(inDrawer: true)),
            body: Column(
              children: [
                AppHeaderBar(
                  title: 'Productos',
                  subtitle: 'Catálogo, precios, tallas y colores',
                  compact: true,
                  business: _business,
                  alertCount: 2,
                  onMenuTap: () => scaffold.currentState!.openDrawer(),
                  onSearchTap: () {},
                  onNotificationsTap: () {},
                  onNewSale: () {},
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Nueva venta'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _save(tester, key, 'celular_${brightness.name}');

      await tester.tap(find.byTooltip('Abrir el menú'));
      await tester.pumpAndSettle();
      expect(find.text('Clientes y proveedores'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _save(tester, key, 'celular_menu_${brightness.name}');
    });
  }

  testWidgets('el cajero no ve Tienda ni Reportes, y sin el plan no ve Servicios', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: Row(children: [_menu(role: 'CASHIER', services: false)]))));
    await tester.pumpAndSettle();
    expect(find.text('Vender'), findsOneWidget);
    expect(find.text('Clientes y proveedores'), findsOneWidget);
    expect(find.text('Tienda en línea'), findsNothing);
    expect(find.text('Reportes'), findsNothing);
    expect(find.text('Servicios'), findsNothing);
  });
}
