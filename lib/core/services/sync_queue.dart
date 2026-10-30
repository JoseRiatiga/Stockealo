import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

/// Envía una operación pendiente a la nube. Debe lanzar una excepción si falla.
typedef SyncSender = Future<void> Function(String operation, Map<String, dynamic> payload);

/// Cola local de escrituras hacia Supabase.
///
/// Cada cambio se guarda en `pending_sync` antes de intentar enviarlo, así no se
/// pierde si no hay conexión. Se envían en orden de llegada y el envío se detiene
/// en el primer fallo para no aplicar cambios desordenados (por ejemplo, borrar
/// algo antes de crearlo).
class SyncQueue {
  static final SyncQueue instance = SyncQueue(() => AppDatabase.instance.database);

  SyncQueue(this._database);

  final Future<Database> Function() _database;

  /// Tras este número de intentos fallidos una operación se descarta para no
  /// bloquear las siguientes. El dato sigue en el teléfono y vuelve a subir con
  /// la sincronización manual.
  static const int maxAttempts = 20;

  Future<void>? _running;

  Future<void> enqueue(String operation, Map<String, dynamic> payload) async {
    final db = await _database();
    await db.insert('pending_sync', {
      'operation': operation,
      'payload': jsonEncode(payload),
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> pendingCount() async {
    final db = await _database();
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM pending_sync')) ?? 0;
  }

  /// Envía las operaciones pendientes. Si ya hay un envío en curso, espera a que
  /// termine y no lanza otro en paralelo. Devuelve cuántas quedaron pendientes.
  Future<int> flush(SyncSender send) async {
    while (_running != null) {
      await _running;
    }
    final run = _flush(send);
    _running = run;
    try {
      await run;
    } finally {
      _running = null;
    }
    return pendingCount();
  }

  Future<void> _flush(SyncSender send) async {
    final db = await _database();
    final rows = await db.query('pending_sync', orderBy: 'id ASC');
    for (final row in rows) {
      final id = row['id'] as int;
      final operation = row['operation'] as String;
      try {
        final payload = Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map);
        await send(operation, payload);
        await db.delete('pending_sync', where: 'id = ?', whereArgs: [id]);
      } catch (e) {
        final attempts = (row['attempts'] as int) + 1;
        if (attempts >= maxAttempts) {
          debugPrint('Sincronización: se descarta "$operation" tras $attempts intentos: $e');
          await db.delete('pending_sync', where: 'id = ?', whereArgs: [id]);
          continue;
        }
        await db.update(
          'pending_sync',
          {'attempts': attempts, 'last_error': e.toString()},
          where: 'id = ?',
          whereArgs: [id],
        );
        debugPrint('Sincronización pendiente ("$operation", intento $attempts): $e');
        return;
      }
    }
  }
}
