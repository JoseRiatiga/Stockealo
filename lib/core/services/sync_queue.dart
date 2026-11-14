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
/// Cómo va la subida a la nube (para el aviso de arriba y Ajustes)
@immutable
class SyncStatus {
  /// Cambios esperando subir
  final int pending;

  /// Cambios que la nube rechazó muchas veces: no se borran, esperan «Reintentar»
  final int failed;

  /// El último intento falló por falta de conexión
  final bool offline;

  const SyncStatus({this.pending = 0, this.failed = 0, this.offline = false});

  @override
  bool operator ==(Object other) =>
      other is SyncStatus && other.pending == pending && other.failed == failed && other.offline == offline;

  @override
  int get hashCode => Object.hash(pending, failed, offline);
}

class SyncQueue {
  static final SyncQueue instance = SyncQueue(() => AppDatabase.instance.database);

  SyncQueue(this._database);

  final Future<Database> Function() _database;

  /// Tras este número de rechazos de la nube una operación queda «con error»: ya no
  /// bloquea las siguientes, pero NO se borra (0.13.4). Espera a «Reintentar».
  /// La falta de conexión no cuenta como intento.
  static const int maxAttempts = 20;

  /// Estado de la subida, para el aviso «Sin conexión» y Ajustes
  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus());

  /// El error es por falta de conexión (no un rechazo de la nube)
  static bool isNetworkError(Object e) {
    final text = e.toString();
    return const [
      'SocketException',
      'Failed host lookup',
      'ClientException',
      'XMLHttpRequest',
      'Connection refused',
      'Connection reset',
      'Network is unreachable',
      'TimeoutException',
      'Failed to fetch',
    ].any(text.contains);
  }

  Future<void>? _running;

  Future<void> enqueue(String operation, Map<String, dynamic> payload) async {
    final db = await _database();
    await db.insert('pending_sync', {
      'operation': operation,
      'payload': jsonEncode(payload),
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    await refreshStatus();
  }

  /// Cambios esperando subir (sin contar los que quedaron con error)
  Future<int> pendingCount() async {
    final db = await _database();
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM pending_sync WHERE attempts < ?', [maxAttempts])) ??
        0;
  }

  /// Cambios que la nube rechazó muchas veces y esperan «Reintentar»
  Future<int> failedCount() async {
    final db = await _database();
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM pending_sync WHERE attempts >= ?', [maxAttempts])) ??
        0;
  }

  /// Vuelve a intentar los que quedaron con error
  Future<void> retryFailed() async {
    final db = await _database();
    await db.update('pending_sync', {'attempts': 0}, where: 'attempts >= ?', whereArgs: [maxAttempts]);
    await refreshStatus();
  }

  /// Ids de lo que todavía no sube para una operación (por ejemplo, las ventas pendientes)
  Future<Set<String>> pendingIds(String operation) async {
    final db = await _database();
    final rows = await db.query('pending_sync', columns: ['payload'], where: 'operation = ?', whereArgs: [operation]);
    final ids = <String>{};
    for (final r in rows) {
      try {
        final id = (jsonDecode(r['payload'] as String) as Map)['id'];
        if (id is String) ids.add(id);
      } catch (_) {}
    }
    return ids;
  }

  /// Recalcula el estado; [offline] cambia el aviso de conexión si se indica
  Future<void> refreshStatus({bool? offline}) async {
    status.value = SyncStatus(
      pending: await pendingCount(),
      failed: await failedCount(),
      offline: offline ?? status.value.offline,
    );
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
    final offline = await _sendAll(send);
    await refreshStatus(offline: offline);
  }

  /// Devuelve true si se detuvo por falta de conexión
  Future<bool> _sendAll(SyncSender send) async {
    final db = await _database();
    final rows = await db.query('pending_sync', where: 'attempts < ?', whereArgs: [maxAttempts], orderBy: 'id ASC');
    for (final row in rows) {
      final id = row['id'] as int;
      final operation = row['operation'] as String;
      try {
        final payload = Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map);
        await send(operation, payload);
        await db.delete('pending_sync', where: 'id = ?', whereArgs: [id]);
      } catch (e) {
        // Sin conexión: no cuenta como intento; todo sigue esperando en orden
        if (isNetworkError(e)) {
          debugPrint('Sincronización: sin conexión, se reintenta luego ("$operation")');
          return true;
        }
        final attempts = (row['attempts'] as int) + 1;
        await db.update(
          'pending_sync',
          {'attempts': attempts, 'last_error': e.toString()},
          where: 'id = ?',
          whereArgs: [id],
        );
        if (attempts >= maxAttempts) {
          // Queda «con error» (no se borra) y deja pasar a las siguientes
          debugPrint('Sincronización: "$operation" quedó con error tras $attempts intentos: $e');
          continue;
        }
        debugPrint('Sincronización pendiente ("$operation", intento $attempts): $e');
        return false;
      }
    }
    return false;
  }
}
