import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/backup/data/auto_backup_service.dart';
import 'package:stockealo/features/reports/data/guided_import.dart';

/// Importador guiado de Excel (0.12.0): archivos hechos a mano
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('lectura y detección', () {
    test('entiende precios escritos de cualquier forma', () {
      expect(GuidedImport.parseAmount('\$12.500'), 12500);
      expect(GuidedImport.parseAmount('12,500'), 12500);
      expect(GuidedImport.parseAmount('1.250.000'), 1250000);
      expect(GuidedImport.parseAmount('12.500,50'), 12500.5);
      expect(GuidedImport.parseAmount('12.5'), 12.5);
      expect(GuidedImport.parseAmount('2500'), 2500);
      expect(GuidedImport.parseAmount('gratis'), isNull);
    });

    test('reconoce títulos comunes como PVP, Unidades y Referencia', () {
      expect(GuidedImport.fieldOf('PVP'), ImportField.price);
      expect(GuidedImport.fieldOf('Unidades'), ImportField.stock);
      expect(GuidedImport.fieldOf('Referencia'), ImportField.code);
      expect(GuidedImport.fieldOf('Precio de compra'), ImportField.cost);
      expect(GuidedImport.fieldOf('Descripción del artículo'), ImportField.name);
      expect(GuidedImport.fieldOf('Observaciones'), isNull);
    });

    test('encuentra la fila de los títulos aunque arriba haya el nombre del negocio y la fecha', () {
      const t = ImportTable('Hoja1', [
        ['Tienda Doña Ana'],
        ['Inventario a 3 de noviembre'],
        [],
        ['Referencia', 'Producto', 'PVP', 'Unidades'],
        ['A1', 'Arroz', '\$2.800', '24'],
      ]);
      expect(GuidedImport.headerRowOf(t), 3);
      final mapping = GuidedImport.guessMapping(t.rows[3]);
      expect(mapping, {0: ImportField.code, 1: ImportField.name, 2: ImportField.price, 3: ImportField.stock});
      final rows = GuidedImport.buildRows(t, 3, mapping);
      expect(rows.single.name, 'Arroz');
      expect(rows.single.price, 2800);
      expect(rows.single.stock, 24);
      expect(rows.single.line, 5);
    });

    test('elige la hoja de productos aunque se llame «Hoja1» y haya otras', () {
      const tables = [
        ImportTable('Notas', [['Recordar pagar arriendo']]),
        ImportTable('Clientes', [['Nombre', 'Teléfono', 'Deuda'], ['Carlos', '300', '5000']]),
        ImportTable('Hoja1', [['Nombre', 'Precio', 'Stock'], ['Arroz', '2800', '24'], ['Azúcar', '3000', '10']]),
      ];
      expect(GuidedImport.productSheet(tables)?.name, 'Hoja1');
    });

    test('avisa de códigos repetidos, precios raros y filas sin nombre', () {
      const t = ImportTable('P', [
        ['Código', 'Nombre', 'Precio'],
        ['1', 'Arroz', '2800'],
        ['1', 'Arroz grande', '5000'],
        ['2', '', '1000'],
        ['3', 'Panela', 'consultar'],
      ]);
      final rows = GuidedImport.buildRows(t, 0, GuidedImport.guessMapping(t.rows[0]));
      expect(rows[1].issues.single, contains('Código repetido'));
      expect(rows[2].issues.single, contains('Sin nombre'));
      expect(rows[3].issues.single, contains('Precio no válido'));
      expect(rows[3].price, isNull);
    });

    test('lee CSV separado por coma o por punto y coma, con comillas', () {
      expect(GuidedImport.parseCsv('Nombre,Precio\n"Arroz, 500 g",2800\n'), [
        ['Nombre', 'Precio'],
        ['Arroz, 500 g', '2800'],
      ]);
      expect(GuidedImport.parseCsv('Nombre;Precio;Stock\r\nArroz;2.800;24\r\n'), [
        ['Nombre', 'Precio', 'Stock'],
        ['Arroz', '2.800', '24'],
      ]);
    });

    test('un .xls viejo pide guardarlo como .xlsx', () {
      expect(() => GuidedImport.read(Uint8List(0), 'inventario.xls'), throwsFormatException);
    });

    test('lee un .xlsx y la plantilla trae ejemplos', () {
      final tables = GuidedImport.read(Uint8List.fromList(GuidedImport.template()), 'plantilla.xlsx');
      final t = GuidedImport.productSheet(tables)!;
      final rows = GuidedImport.buildRows(t, GuidedImport.headerRowOf(t), GuidedImport.guessMapping(t.rows[0]));
      expect(rows.first.name, 'Arroz Diana 500 g');
      expect(rows.first.price, 2800);
      expect(rows.first.cost, 2100);
      expect(rows.first.minStock, 6);
      // Una hoja hecha en Excel con números de verdad
      final excel = Excel.createExcel();
      excel['Productos'].appendRow([TextCellValue('Nombre'), TextCellValue('Unidades')]);
      excel['Productos'].appendRow([TextCellValue('Sal'), const DoubleCellValue(12.0)]);
      final read = GuidedImport.read(Uint8List.fromList(excel.encode()!), 'x.xlsx');
      final sal = read.firstWhere((t) => t.name == 'Productos').rows[1];
      expect(sal, ['Sal', '12']);
    });
  });

  group('importar', () {
    late Directory dir;
    const account = 'guided-import-test';
    const businessId = 'biz-imp';
    final appDb = AppDatabase.instance;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('stockealo_import_');
      await databaseFactory.setDatabasesPath(dir.path);
      AutoBackupService.baseDirectory = () async => dir;
    });

    setUp(() async {
      await SupabaseService.instance.waitForPendingWrites();
      await appDb.useAccount(null);
      await appDb.close();
      for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
        await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
      }
      await appDb.useAccount(account);
      final db = await appDb.database;
      await db.insert('users', {'id': 'u1', 'email': 'ana@x.com', 'password': 'x', 'created_at': '2026-11-01'});
      await db.insert('businesses', {'id': businessId, 'user_id': 'u1', 'name': 'Ana', 'created_at': '2026-11-01'});
      await db.insert('products', {
        'id': 'p1', 'business_id': businessId, 'code': 'A1', 'name': 'Arroz', 'category': 'Granos', 'purchase_price': 2000,
        'sale_price': 2500, 'stock': 10, 'min_stock': 5, 'is_active': 1, 'created_at': '2026-11-01', 'updated_at': '2026-11-01',
      });
    });

    tearDownAll(() async {
      await SupabaseService.instance.waitForPendingWrites();
      await appDb.useAccount(null);
      await appDb.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    const file = ImportTable('P', [
      ['Referencia', 'Producto', 'PVP', 'Unidades'],
      ['A1', 'Arroz', '2.800', '5'],
      ['B2', 'Azúcar', '3.000', '12'],
      ['B2', 'Azúcar repetida', '3.000', '1'],
    ]);
    List<ImportRow> rows() => GuidedImport.buildRows(file, 0, GuidedImport.guessMapping(file.rows[0]));

    test('reemplazar: crea los nuevos, actualiza los existentes y omite los repetidos', () async {
      final out = await GuidedImport.apply(businessId: businessId, rows: rows(), updateExisting: true, stockMode: StockMode.replace);
      expect(out.created, 1);
      expect(out.updated, 1);
      expect(out.skipped, 1);
      final db = await appDb.database;
      final arroz = (await db.query('products', where: 'id = ?', whereArgs: ['p1'])).single;
      expect(arroz['stock'], 5);
      expect(arroz['sale_price'], 2800);
      expect(arroz['purchase_price'], 2000, reason: 'el costo no venía en el archivo: se conserva');
      expect((await db.query('products', where: 'name = ?', whereArgs: ['Azúcar'])).single['stock'], 12);
    });

    test('sumar stock y dejar igual los existentes', () async {
      await GuidedImport.apply(businessId: businessId, rows: rows(), updateExisting: true, stockMode: StockMode.add);
      final db = await appDb.database;
      expect((await db.query('products', where: 'id = ?', whereArgs: ['p1'])).single['stock'], 15);

      final out = await GuidedImport.apply(businessId: businessId, rows: rows(), updateExisting: false, stockMode: StockMode.add);
      expect(out.updated, 0);
      expect((await db.query('products', where: 'id = ?', whereArgs: ['p1'])).single['stock'], 15);
    });
  });
}
