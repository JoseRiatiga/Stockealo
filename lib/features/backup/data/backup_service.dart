import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/database/app_database.dart';
import '../../business/data/business_repository.dart';

/// Respaldo completo de la cuenta en un archivo (.db) para guardarlo fuera del
/// teléfono o pasarlo a otro dispositivo sin usar la nube.
class BackupService {
  static final BackupService instance = BackupService();

  /// En la versión web los datos no viven en un archivo que se pueda compartir
  bool get isSupported => !kIsWeb;

  /// Crea el respaldo y abre el menú del sistema para guardarlo o enviarlo
  Future<void> exportBackup() async {
    if (!isSupported) throw Exception('El respaldo en archivo no está disponible en la versión web.');
    final dir = await getTemporaryDirectory();
    final name = 'stockealo_respaldo_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.db';
    final path = p.join(dir.path, name);
    await AppDatabase.instance.exportTo(path);
    await Share.shareXFiles([XFile(path)], subject: 'Respaldo de Stockealo');
  }

  /// Pide un archivo de respaldo y reemplaza con él los datos de esta cuenta.
  /// Devuelve false si el usuario canceló la selección.
  Future<bool> importBackup() async {
    if (!isSupported) throw Exception('El respaldo en archivo no está disponible en la versión web.');
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return false;

    await AppDatabase.instance.restoreFrom(path);
    // Los negocios pueden ser otros: que la app vuelva a elegir el activo
    BusinessRepository.instance.setActiveBusiness(null);
    return true;
  }
}
