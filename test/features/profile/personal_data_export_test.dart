import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/profile/data/personal_data_export.dart';

/// 0.16.0, fase 5: «Descargar todos mis datos» (Ley 1581)
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'mydata-test';
  final appDb = AppDatabase.instance;

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_mydata_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('una hoja por cada cosa de mis negocios, sin la contraseña ni lo de otros', () async {
    await appDb.useAccount(account);
    final db = await appDb.database;
    await db.insert('users', {'id': 'u1', 'email': 'rosa@x.com', 'password': 'secreto-no-debe-salir', 'name': 'Rosa', 'created_at': '2026-10-01'});
    await db.insert('users', {'id': 'u2', 'email': 'otro@x.com', 'password': 'x', 'created_at': '2026-10-01'});
    await db.insert('businesses', Business(id: 'mio', userId: 'u1', name: 'Variedades Rosita', createdAt: DateTime(2026)).toMap());
    await db.insert('businesses', Business(id: 'ajeno', userId: 'u2', name: 'Negocio ajeno', createdAt: DateTime(2026)).toMap());
    for (final (id, biz) in [('p1', 'mio'), ('p2', 'mio'), ('p3', 'ajeno')]) {
      await db.insert('products', {
        'id': id, 'business_id': biz, 'code': id, 'name': 'Producto $id', 'category': 'Granos',
        'purchase_price': 1000, 'sale_price': 2000, 'stock': 3, 'min_stock': 1, 'created_at': '2026-10-01', 'updated_at': '2026-10-01',
      });
    }
    await db.insert('customers', {'id': 'c1', 'business_id': 'mio', 'name': 'Ana', 'debt_balance': 0, 'created_at': '2026-10-01'});

    final file = await PersonalDataExport.instance.build(userId: 'u1', userEmail: 'rosa@x.com');
    expect(file.name, startsWith('Mis_datos_Stockealo_'));
    expect(file.rows['Cuenta'], 1);
    expect(file.rows['Negocios'], 1, reason: 'solo el mío');
    expect(file.rows['Productos'], 2, reason: 'no el del negocio ajeno');
    expect(file.rows['Clientes'], 1);

    final book = Excel.decodeBytes(file.bytes);
    expect(book.tables.keys, containsAll(['Cuenta', 'Negocios', 'Productos', 'Clientes']));
    final text = book.tables.values.expand((t) => t.rows).expand((r) => r).map((c) => '${c?.value ?? ''}').join(' ');
    expect(text.contains('secreto-no-debe-salir'), isFalse, reason: 'la contraseña nunca sale');
    expect(text.contains('Negocio ajeno'), isFalse);
    expect(book.tables['Cuenta']!.rows.first.map((c) => '${c?.value}'), isNot(contains('password')));
  });
}
