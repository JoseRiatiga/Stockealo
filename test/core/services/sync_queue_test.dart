import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/services/sync_queue.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late SyncQueue queue;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE pending_sync (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    queue = SyncQueue(() async => db);
  });

  tearDown(() => db.close());

  test('envía en orden y vacía la cola', () async {
    await queue.enqueue('upsert_sale', {'id': 's1'});
    await queue.enqueue('update_stock', {'id': 'p1', 'stock': 4});

    final sent = <String>[];
    final left = await queue.flush((op, payload) async => sent.add('$op:${payload['id']}'));

    expect(sent, ['upsert_sale:s1', 'update_stock:p1']);
    expect(left, 0);
  });

  test('si una operación falla se detiene, la conserva y no salta a las siguientes', () async {
    await queue.enqueue('upsert_sale', {'id': 's1'});
    await queue.enqueue('delete_sale', {'id': 's1'});

    final sent = <String>[];
    final left = await queue.flush((op, payload) async {
      if (op == 'upsert_sale') throw Exception('sin conexión');
      sent.add(op);
    });

    expect(sent, isEmpty);
    expect(left, 2);
    final first = (await db.query('pending_sync', orderBy: 'id')).first;
    expect(first['attempts'], 1);
    expect(first['last_error'], contains('sin conexión'));
  });

  test('reintenta lo que quedó pendiente en el siguiente envío', () async {
    await queue.enqueue('upsert_sale', {'id': 's1'});
    await queue.flush((op, payload) async => throw Exception('sin conexión'));

    final sent = <String>[];
    final left = await queue.flush((op, payload) async => sent.add(op));

    expect(sent, ['upsert_sale']);
    expect(left, 0);
  });

  test('descarta una operación tras el máximo de intentos para no bloquear la cola', () async {
    await queue.enqueue('upsert_sale', {'id': 'mala'});
    await queue.enqueue('upsert_sale', {'id': 'buena'});
    await db.update('pending_sync', {'attempts': SyncQueue.maxAttempts - 1}, where: 'id = 1');

    final sent = <String>[];
    final left = await queue.flush((op, payload) async {
      if (payload['id'] == 'mala') throw Exception('rechazada');
      sent.add(payload['id'] as String);
    });

    expect(sent, ['buena']);
    expect(left, 0);
  });

  test('dos envíos simultáneos no mandan la misma operación dos veces', () async {
    await queue.enqueue('upsert_sale', {'id': 's1'});
    final gate = Completer<void>();
    var calls = 0;
    Future<void> send(String op, Map<String, dynamic> p) async {
      calls++;
      await gate.future;
    }

    final first = queue.flush(send);
    final second = queue.flush(send);
    gate.complete();
    await Future.wait([first, second]);

    expect(calls, 1);
  });
}
