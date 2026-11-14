import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Carpeta propia por archivo de pruebas: flutter test ejecuta los archivos en paralelo
  late Directory dbDir;
  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_accounts_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });
  tearDownAll(() async {
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  final appDb = AppDatabase.instance;
  const legacy = 'stockealo_v2.db';

  Future<void> deleteFile(String name) async =>
      databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));

  Future<void> reset() async {
    await appDb.useAccount(null);
    await appDb.close();
    for (final f in [legacy, 'stockealo_a.db', 'stockealo_b.db']) {
      await deleteFile(f);
    }
  }

  setUp(reset);
  tearDownAll(reset);

  group('useAccount', () {
    test('la primera cuenta se queda con el archivo existente', () async {
      await appDb.useAccount('a', 'a@x.com');
      expect(appDb.openFile, legacy);

      await appDb.useAccount('b', 'b@x.com');
      expect(appDb.openFile, 'stockealo_b.db');

      await appDb.useAccount('a', 'a@x.com');
      expect(appDb.openFile, legacy);
    });

    test('cada cuenta solo ve sus propios datos', () async {
      await appDb.useAccount('a', 'a@x.com');
      await appDb.setSetting('marca', 'de A');

      await appDb.useAccount('b', 'b@x.com');
      expect(await appDb.getSetting('marca'), isNull);
      await appDb.setSetting('marca', 'de B');

      await appDb.useAccount('a', 'a@x.com');
      expect(await appDb.getSetting('marca'), 'de A');
    });

    test('sin sesión vuelve al archivo compartido', () async {
      await appDb.useAccount('a', 'a@x.com');
      await appDb.useAccount('b', 'b@x.com');
      await appDb.useAccount(null);
      expect(appDb.openFile, legacy);
    });

    test('una base nueva ya trae el esquema completo', () async {
      await appDb.useAccount('a', 'a@x.com');
      final db = await appDb.database;
      Future<Set<String>> columnsOf(String table) async =>
          (await db.rawQuery('PRAGMA table_info($table)')).map((c) => c['name'] as String).toSet();

      expect(
        await columnsOf('sales'),
        containsAll(['invoice_number', 'discount_amount', 'variant_id', 'variant_name', 'seller_name']),
      );
      expect(await columnsOf('quotation_items'), containsAll(['variant_id', 'variant_name']));
      expect(
        await columnsOf('businesses'),
        containsAll(['is_deleted', 'deleted_at', 'description', 'country', 'icon', 'color', 'logo_url', 'cash_register_enabled']),
      );
      expect(await columnsOf('app_settings'), isNotEmpty);
      expect(await db.getVersion(), 15);
      expect(await columnsOf('promotions'), containsAll(['name', 'kind', 'percent_off', 'buy_qty', 'pay_qty', 'scope', 'starts_at', 'ends_at']));
      expect(await columnsOf('sales'), containsAll(['promotion_id', 'promotion_name', 'promotion_discount']));
      expect(await columnsOf('services'), containsAll(['price', 'commission_pct', 'duration_min', 'prices', 'staff_ids']));
      expect(await columnsOf('staff_attendance'), containsAll(['staff_id', 'day', 'status', 'pauses']));
      expect(await columnsOf('staff'), containsAll(['name', 'commission_pct', 'member_email', 'schedule']));
      expect(await columnsOf('work_orders'), containsAll(['plate', 'status', 'lines', 'tip', 'sale_ids', 'vehicle_kind']));
      expect(await columnsOf('sales'), containsAll(['service_id', 'work_order_id', 'staff_ids']));
      expect(await columnsOf('businesses'), containsAll(['services_enabled', 'service_type', 'services_schedule']));
      expect(await columnsOf('suppliers'), containsAll(['name', 'phone', 'payment_terms', 'credit_days']));
      expect(await columnsOf('purchases'), containsAll(['supplier_id', 'items', 'due_date', 'is_paid']));
      expect(await columnsOf('products'), contains('supplier_id'));
      expect(
        await columnsOf('product_variants'),
        containsAll(['attribute2_name', 'attribute2_value', 'color_hex', 'color_hex2']),
      );
      expect(await columnsOf('activity_log'), containsAll(['actor_email', 'action', 'summary']));
      expect(await columnsOf('pending_sync'), isNotEmpty);
    });

    test('respeta al dueño que dejó la actualización a v3', () async {
      await appDb.setSetting('db_owner_email', 'a@x.com');
      await appDb.close();

      await appDb.useAccount('b', 'b@x.com');
      expect(appDb.openFile, 'stockealo_b.db');

      await appDb.useAccount('a', 'A@x.com');
      expect(appDb.openFile, legacy);
    });
  });
}
