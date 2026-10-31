import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/customers/models/customer.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/stocky/data/stocky_ai_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'stocky-ai-test';
  const businessId = 'biz-ai';
  final appDb = AppDatabase.instance;

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_ai_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    final db = await appDb.database;
    await db.insert('users', {
      'id': 'u1',
      'email': 'dueno@x.com',
      'password': authManagedPassword,
      'created_at': '2026-10-01',
    });
    await db.insert(
      'businesses',
      Business(id: businessId, userId: 'u1', name: 'Tienda', createdAt: DateTime(2026, 10, 1)).toMap(),
    );
    final now = DateTime(2026, 10, 30);
    for (final (id, stock) in [('a', 0), ('b', 2), ('c', 40)]) {
      await db.insert(
        'products',
        Product(
          id: id,
          businessId: businessId,
          code: 'SKU-$id',
          name: 'Producto $id',
          category: 'General',
          purchasePrice: 500,
          salePrice: 1000,
          stock: stock,
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );
    }
    await db.insert(
      'customers',
      Customer(
        id: 'c1',
        businessId: businessId,
        name: 'Marta Secreta',
        phone: '+573001112233',
        debtBalance: 15000,
        createdAt: now,
      ).toMap(),
    );
  });

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('el contexto lleva cifras del negocio y ningún dato de clientes', () async {
    final context = await StockyAiService.instance.buildContext(businessId);
    final text = jsonEncode(context);

    expect(text, isNot(contains('Marta')));
    expect(text, isNot(contains('3001112233')));

    final inventory = context['inventario'] as Map;
    expect(inventory['productos'], 3);
    expect(inventory['agotados'], 1);
    expect(inventory['stock_bajo'], 1);
    expect(context['agotados'], ['Producto a']);
    expect((context['fiados'] as Map)['clientes_con_deuda'], 1);
    // Cabe en el límite que acepta la función
    expect(text.length, lessThan(4000));
  });

  test('los mensajes de error explican qué pasó', () {
    expect(const StockyAiResult(error: 'daily_limit', limit: 10).errorMessage, contains('10 preguntas'));
    expect(const StockyAiResult(error: 'offline').errorMessage, contains('internet'));
    expect(const StockyAiResult(error: 'otro').errorMessage, contains('no está disponible'));
    expect(const StockyAiResult(answer: 'Hola').ok, isTrue);
  });
}
