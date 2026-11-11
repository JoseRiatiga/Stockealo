import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/design/quick_access_row.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/home/data/app_functions.dart';
import 'package:stockealo/features/home/presentation/widgets/global_search_dialog.dart';

/// «Nada duplicado» (0.12.0): cada función tiene un solo lugar y el buscador lleva a él
void main() {
  sqfliteFfiInit();

  test('el buscador encuentra funciones por palabras, también sin tildes', () {
    final caja = findFunctions('caja', role: 'CASHIER', services: false);
    expect(caja.map((f) => f.where), contains('Caja'));
    expect(findFunctions('cotización', role: 'CASHIER', services: false).single.title, 'Cotizaciones');
    expect(findFunctions('proveedor', role: 'OWNER', services: false).single.where, 'Clientes y proveedores › Proveedores');
    expect(findFunctions('modo oscuro', role: 'CASHIER', services: false).single.title, 'Apariencia');
  });

  test('el cajero no ve funciones de dueño y Servicios solo aparece con Pro Servicios', () {
    expect(findFunctions('ganancia', role: 'CASHIER', services: false), isEmpty);
    expect(findFunctions('ganancia', role: 'ADMIN', services: false).single.where, 'Reportes › Ganancias');
    expect(findFunctions('lavado', role: 'OWNER', services: false), isEmpty);
    expect(findFunctions('lavado', role: 'OWNER', services: true).single.tab, 5);
  });

  test('ninguna función se repite: cada título tiene un solo lugar', () {
    final titles = kAppFunctions.map((f) => f.title).toList();
    expect(titles.toSet().length, titles.length);
  });

  test('la cuadrícula de accesos cambia de columnas según el ancho', () {
    expect(QuickAccessRow.columnsFor(320), 2);
    expect(QuickAccessRow.columnsFor(360), 3);
    expect(QuickAccessRow.columnsFor(900), 4);
  });

  testWidgets('los accesos se ven todos sin deslizar a 360 px', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: QuickAccessRow(items: [
            for (final label in ['Catálogo', 'Tienda en línea', 'Proveedores y entradas', 'Importar desde Excel'])
              QuickAccessItem(icon: Icons.star_outline_outlined, label: label, onTap: () {}),
          ]),
        ),
      ),
    ));
    for (final label in ['Catálogo', 'Tienda en línea', 'Proveedores y entradas', 'Importar desde Excel']) {
      expect(find.text(label), findsOneWidget);
      final box = tester.getRect(find.text(label));
      expect(box.right, lessThanOrEqualTo(360), reason: '$label se sale de la pantalla');
    }
    expect(find.byType(ListView), findsNothing, reason: 'ya no es una fila que se desliza');
    expect(tester.takeException(), isNull);
  });

  test('«Dónde quedó cada cosa» solo se marca al actualizar desde una versión anterior', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE businesses (id TEXT PRIMARY KEY, name TEXT)');
    await db.execute('CREATE TABLE sales (id TEXT PRIMARY KEY, product_id TEXT, total REAL)');
    await AppDatabase.upgradeSchema(db, 10, 11);
    await AppDatabase.upgradeSchema(db, 11, 12);
    final row = await db.query('app_settings', where: 'key = ?', whereArgs: ['where_moved_pending']);
    expect(row.single['value'], '1');
  });

  group('accesos rápidos de Inicio (0.12.1)', () {
    test('cada función tiene un identificador único', () {
      final ids = kAppFunctions.map((f) => f.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('sin personalizar, Inicio trae los accesos de siempre', () {
      final list = resolveShortcuts(const [], role: 'OWNER', services: false);
      expect(list.map((f) => f.id), kDefaultShortcutIds);
    });

    test('los nombres de antes de la 0.12.0 se respetan, sin repetir', () {
      final list = resolveShortcuts(const ['sell', 'catalog_pdf', 'new_sale', 'inventory'], role: 'OWNER', services: false);
      expect(list.map((f) => f.id), ['new_sale', 'catalog']);
    });

    test('el cajero no ve accesos de dueño ni Servicios sin el plan', () {
      final list = resolveShortcuts(const ['profits', 'services', 'new_sale'], role: 'CASHIER', services: false);
      expect(list.map((f) => f.id), ['new_sale']);
      final withPlan = resolveShortcuts(const ['services'], role: 'CASHIER', services: true);
      expect(withPlan.map((f) => f.id), ['services']);
    });

    test('no pasan del máximo', () {
      final all = kAppFunctions.map((f) => f.id).toList();
      expect(resolveShortcuts(all, role: 'OWNER', services: true).length, kMaxShortcuts);
    });
  });

  group('buscador en diseño V1 (0.12.1)', () {
    for (final size in const [Size(360, 800), Size(1200, 800)]) {
      for (final b in Brightness.values) {
        testWidgets('se ve sin errores a ${size.width.toInt()} px en ${b.name}', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.build(b),
            home: const Scaffold(body: GlobalSearchDialog(userRole: 'OWNER')),
          ));
          await tester.pump();
          expect(find.text('Dónde está cada cosa'), findsOneWidget);
          expect(find.text('Busca un producto o una función'), findsOneWidget);
          expect(find.text('Cerrar'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

