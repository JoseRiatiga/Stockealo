import '../../business/data/transfer_repository.dart';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

/// «Descargar todos mis datos» (0.16.0, fase 5; Ley 1581 de 2012): un Excel con una
/// hoja por cada cosa que la app guarda de tus negocios en este equipo. Revisa todas
/// las tablas que tienen negocio, así no se olvida ninguna nueva. Deja por fuera lo
/// interno (la cola de subida, los ajustes) y lo sensible (contraseñas, claves).
class PersonalDataExport {
  static final PersonalDataExport instance = PersonalDataExport._();
  PersonalDataExport._();

  /// Nombres de las hojas (máximo 31 letras, como pide Excel)
  static const labels = {
    'businesses': 'Negocios',
    'business_members': 'Equipo',
    'business_roles': 'Roles',
    'products': 'Productos',
    'product_variants': 'Tallas y colores',
    'categories': 'Categorías',
    'customers': 'Clientes',
    'customer_payments': 'Abonos de clientes',
    'sales': 'Ventas',
    'quotations': 'Cotizaciones',
    'cash_sessions': 'Turnos de caja',
    'cash_movements': 'Movimientos de caja',
    'stock_movements': 'Movimientos de stock',
    'suppliers': 'Proveedores',
    'purchases': 'Entradas de mercancía',
    'supplier_orders': 'Pedidos a proveedores',
    'promotions': 'Promociones',
    'services': 'Servicios',
    'work_orders': 'Órdenes de servicio',
    'appointments': 'Citas',
    'staff': 'Personal de servicios',
    'commissions': 'Comisiones',
    'sales_goals': 'Metas de ventas',
    'product_lots': 'Lotes',
    'lot_exchanges': 'Cambios con proveedores',
    // Sedes (0.18.0)
    'branches': 'Sedes',
    'branch_stock': 'Stock por sede',
    'activity_log': 'Actividad',
  };

  /// Lo que nunca sale en el archivo
  static const _skipTables = {'pending_sync', 'app_settings', 'sqlite_sequence', 'android_metadata', 'app_scope'};
  static const _skipColumns = {'password', 'password_hash', 'token', 'access_token', 'refresh_token', 'pin', 'secret'};

  /// Arma el libro (sin compartirlo; también para las pruebas)
  @visibleForTesting
  Future<({String name, List<int> bytes, Map<String, int> rows})> build({required String userId, required String userEmail}) async {
    final db = await AppDatabase.instance.database;
    final businessIds = await _businessesOf(db, userId: userId, email: userEmail);
    final excel = Excel.createExcel();
    final first = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(first, 'Cuenta');
    final counts = <String, int>{};

    // La cuenta: sin la contraseña
    final account = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    _write(excel['Cuenta'], account, counts, 'Cuenta');

    if (businessIds.isNotEmpty) {
      final marks = List.filled(businessIds.length, '?').join(',');
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name");
      final ordered = [
        for (final t in labels.keys) if (tables.any((r) => r['name'] == t)) t,
        for (final r in tables)
          if (!labels.containsKey(r['name']) && !_skipTables.contains(r['name']) && r['name'] != 'users') r['name'] as String,
      ];
      for (final table in ordered) {
        final cols = (await db.rawQuery('PRAGMA table_info($table)')).map((c) => c['name'] as String).toList();
        final key = table == 'businesses' ? 'id' : (cols.contains('business_id') ? 'business_id' : null);
        if (key == null) continue;
        final rows = await db.rawQuery('SELECT * FROM $table WHERE $key IN ($marks)', businessIds);
        if (rows.isEmpty) continue;
        final sheet = (labels[table] ?? table).substring(0, (labels[table] ?? table).length.clamp(0, 31));
        _write(excel[sheet], rows, counts, sheet);
      }
      // Traslados entre sedes (0.18.5): viven en la nube; sin conexión no se incluyen
      final transfers = <Map<String, Object?>>[];
      for (final id in businessIds) {
        try {
          for (final t in await TransferRepository.instance.list(id)) {
            for (final l in t.lines) {
              transfers.add({
                'business_id': id,
                'id': t.id,
                'from_branch_id': t.fromBranchId,
                'to_branch_id': t.toBranchId,
                'status': t.status,
                'sent_at': t.sentAt.toIso8601String(),
                'sent_by': t.sentByName ?? t.sentByEmail,
                'received_by': t.receivedByName,
                'product': l.label,
                'sent': l.sent,
                'received': l.received,
              });
            }
          }
        } catch (_) {}
      }
      if (transfers.isNotEmpty) _write(excel['Traslados'], transfers, counts, 'Traslados');
    }
    final bytes = excel.encode();
    if (bytes == null) throw Exception('No se pudo generar el archivo de Excel.');
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    return (name: 'Mis_datos_Stockealo_$stamp.xlsx', bytes: bytes, rows: counts);
  }

  /// Negocios de la persona: los suyos y aquellos donde trabaja
  Future<List<String>> _businessesOf(Database db, {required String userId, required String email}) async {
    final rows = await db.rawQuery(
      '''SELECT id FROM businesses WHERE user_id = ?
         UNION SELECT business_id FROM business_members WHERE user_id = ? OR LOWER(email) = LOWER(?)''',
      [userId, userId, email],
    );
    return [for (final r in rows) if (r.values.first != null) '${r.values.first}'];
  }

  void _write(Sheet sheet, List<Map<String, Object?>> rows, Map<String, int> counts, String name) {
    if (rows.isEmpty) {
      sheet.appendRow([TextCellValue('Sin datos')]);
      counts[name] = 0;
      return;
    }
    final cols = [for (final c in rows.first.keys) if (!_skipColumns.contains(c.toLowerCase())) c];
    sheet.appendRow([for (final c in cols) TextCellValue(c)]);
    for (final r in rows) {
      sheet.appendRow([
        for (final c in cols)
          switch (r[c]) {
            null => TextCellValue(''),
            final int v => IntCellValue(v),
            final double v => DoubleCellValue(v),
            final Object v => TextCellValue('$v'),
          },
      ]);
    }
    counts[name] = rows.length;
  }

  /// Arma el archivo y abre el menú de compartir (en la web, lo descarga)
  Future<Map<String, int>> exportAndShare({required String userId, required String userEmail}) async {
    final file = await build(userId: userId, userEmail: userEmail);
    const mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (kIsWeb) {
      await Share.shareXFiles([XFile.fromData(Uint8List.fromList(file.bytes), name: file.name, mimeType: mime)], subject: 'Mis datos de Stockealo');
    } else {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${file.name}';
      await File(path).writeAsBytes(file.bytes);
      await Share.shareXFiles([XFile(path, mimeType: mime)], subject: 'Mis datos de Stockealo');
    }
    return file.rows;
  }
}
