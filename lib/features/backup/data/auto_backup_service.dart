import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../business/data/business_repository.dart';

/// Una copia automática guardada en el celular
class AutoBackup {
  final String path;
  final DateTime date;
  final int bytes;

  const AutoBackup({required this.path, required this.date, required this.bytes});
}

/// Copia diaria de los datos de la cuenta dentro del celular, sin internet.
/// Guarda las últimas [keep] copias en una carpeta por cuenta y borra las más viejas.
/// Sirve para deshacer un error (borrar productos, restaurar mal) aunque no haya nube.
class AutoBackupService {
  AutoBackupService._();
  static final AutoBackupService instance = AutoBackupService._();

  static const enabledKey = 'auto_backup_enabled';
  static const lastKey = 'auto_backup_last';
  static const keep = 7;
  static const _prefix = 'auto_';

  /// Carpeta base de las copias; en pruebas se reemplaza por una temporal
  @visibleForTesting
  static Future<Directory> Function() baseDirectory = getApplicationDocumentsDirectory;

  bool get isSupported => !kIsWeb;

  bool _running = false;

  Future<bool> isEnabled() async => await AppDatabase.instance.getSetting(enabledKey) != '0';

  Future<void> setEnabled(bool value) => AppDatabase.instance.setSetting(enabledKey, value ? '1' : '0');

  Future<DateTime?> lastBackup() async {
    final value = await AppDatabase.instance.getSetting(lastKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  /// Carpeta de las copias de la cuenta abierta (cada cuenta tiene su archivo de datos)
  Future<Directory> _folder() async {
    final base = await baseDirectory();
    final account = p.basenameWithoutExtension(AppDatabase.instance.openFile);
    return Directory(p.join(base.path, 'respaldos', account));
  }

  /// Hace la copia si está activada y la última tiene más de 20 horas.
  /// Nunca lanza errores: un fallo del respaldo no debe estorbar el uso de la app.
  Future<bool> runIfDue({DateTime? now}) async {
    if (!isSupported || _running) return false;
    try {
      if (!await isEnabled()) return false;
      final last = await lastBackup();
      final at = now ?? DateTime.now();
      if (last != null && at.difference(last) < const Duration(hours: 20)) return false;
      await backupNow(now: at);
      return true;
    } catch (e) {
      debugPrint('Respaldo automático: $e');
      return false;
    }
  }

  /// Copia ahora mismo y deja solo las [keep] más recientes
  Future<AutoBackup> backupNow({DateTime? now}) async {
    _running = true;
    try {
      final at = now ?? DateTime.now();
      final folder = await _folder();
      await folder.create(recursive: true);
      final stamp = at.toIso8601String().substring(0, 19).replaceAll(':', '-');
      final path = p.join(folder.path, '$_prefix$stamp.db');
      await AppDatabase.instance.exportTo(path);
      await AppDatabase.instance.setSetting(lastKey, at.toIso8601String());

      final copies = await list();
      for (final old in copies.skip(keep)) {
        await File(old.path).delete();
      }
      return copies.firstWhere((c) => c.path == path, orElse: () => AutoBackup(path: path, date: at, bytes: 0));
    } finally {
      _running = false;
    }
  }

  /// Copias disponibles, la más reciente primero
  Future<List<AutoBackup>> list() async {
    if (!isSupported) return [];
    final folder = await _folder();
    if (!await folder.exists()) return [];
    final copies = <AutoBackup>[];
    await for (final entity in folder.list()) {
      if (entity is! File) continue;
      final name = p.basenameWithoutExtension(entity.path);
      if (!name.startsWith(_prefix)) continue;
      final stamp = name.substring(_prefix.length);
      // 2026-10-31T08-15-00 → 2026-10-31T08:15:00
      final date = DateTime.tryParse(stamp.length >= 19
          ? '${stamp.substring(0, 13)}:${stamp.substring(14, 16)}:${stamp.substring(17, 19)}'
          : stamp);
      if (date == null) continue;
      copies.add(AutoBackup(path: entity.path, date: date, bytes: await entity.length()));
    }
    copies.sort((a, b) => b.date.compareTo(a.date));
    return copies;
  }

  /// Vuelve los datos de la cuenta a como estaban en [backup]
  Future<void> restore(AutoBackup backup) async {
    await AppDatabase.instance.restoreFrom(backup.path);
    // Los negocios pueden ser otros: que la app vuelva a elegir el activo
    BusinessRepository.instance.setActiveBusiness(null);
  }
}
