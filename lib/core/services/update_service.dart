import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String? releaseNotes;
  final String? downloadUrl;
  final String? publishedAt;
  final int? apkSizeBytes;
  final String? errorMessage;

  AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    this.releaseNotes,
    this.downloadUrl,
    this.publishedAt,
    this.apkSizeBytes,
    this.errorMessage,
  });

  String get formattedSize {
    if (apkSizeBytes == null || apkSizeBytes! <= 0) return '';
    final mb = apkSizeBytes! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class UpdateService {
  static final UpdateService instance = UpdateService._internal();
  UpdateService._internal();

  static const String repoOwner = 'JoseRiatiga';
  static const String repoName = 'Stockealo';
  static const String releasesUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  /// Obtiene la versión actual instalada de la aplicación (ej: 1.0.0)
  Future<String> getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '1.0.0';
    }
  }

  /// Consulta el último Release publicado en GitHub y verifica si es mayor que la versión actual
  Future<AppUpdateInfo> checkForUpdate() async {
    final currentVer = await getCurrentVersion();

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return AppUpdateInfo(
        currentVersion: currentVer,
        latestVersion: currentVer,
        hasUpdate: false,
      );
    }

    try {
      final response = await http.get(
        Uri.parse(releasesUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Stockealo-Flutter-App',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 404) {
        // Aún no se ha publicado ningún Release en GitHub
        return AppUpdateInfo(
          currentVersion: currentVer,
          latestVersion: currentVer,
          hasUpdate: false,
        );
      }

      if (response.statusCode != 200) {
        return AppUpdateInfo(
          currentVersion: currentVer,
          latestVersion: currentVer,
          hasUpdate: false,
          errorMessage: 'Error del servidor (${response.statusCode})',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String? ?? '').replaceAll('v', '').trim();
      final body = data['body'] as String? ?? 'Novedades y mejoras de rendimiento.';
      final publishedAt = data['published_at'] as String?;

      // Buscar el archivo APK adjunto en la lista de assets
      final assets = data['assets'] as List<dynamic>? ?? [];
      String? apkUrl;
      int? apkSize;

      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          apkSize = asset['size'] as int?;
          break;
        }
      }

      final isGreater = _isVersionGreater(tagName, currentVer);

      return AppUpdateInfo(
        currentVersion: currentVer,
        latestVersion: tagName.isNotEmpty ? tagName : currentVer,
        hasUpdate: isGreater && apkUrl != null,
        releaseNotes: body,
        downloadUrl: apkUrl,
        publishedAt: publishedAt,
        apkSizeBytes: apkSize,
      );
    } catch (e) {
      debugPrint('Error al verificar actualización en GitHub: $e');
      return AppUpdateInfo(
        currentVersion: currentVer,
        latestVersion: currentVer,
        hasUpdate: false,
        errorMessage: 'Sin conexión para verificar actualizaciones',
      );
    }
  }

  /// Compara dos versiones semánticas (ej: "1.0.1" con "1.0.0")
  bool _isVersionGreater(String remote, String current) {
    if (remote.isEmpty) return false;
    try {
      final remoteParts = remote.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final currentParts = current.split('.').map((p) => int.tryParse(p) ?? 0).toList();

      while (remoteParts.length < 3) {
        remoteParts.add(0);
      }
      while (currentParts.length < 3) {
        currentParts.add(0);
      }

      // Transición especial: Si el usuario tenía una versión legacy 1.x.x
      // y la versión oficial en GitHub pasó al esquema Beta 0.x.x, considerar como actualización disponible
      if (currentParts[0] >= 1 && remoteParts[0] == 0) {
        return true;
      }

      for (int i = 0; i < 3; i++) {
        if (remoteParts[i] > currentParts[i]) return true;
        if (remoteParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Descarga el APK con reporte de progreso en vivo e invoca el instalador del sistema Android
  Future<void> downloadAndInstallApk({
    required String downloadUrl,
    required void Function(double progress, int receivedBytes, int totalBytes) onProgress,
    required void Function(String errorMessage) onError,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      onError('Las actualizaciones APK solo aplican en dispositivos Android.');
      return;
    }

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers['User-Agent'] = 'Stockealo-Flutter-App';

      final response = await client.send(request);

      if (response.statusCode != 200) {
        onError('Error en la descarga (${response.statusCode})');
        return;
      }

      final totalBytes = response.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/stockealo-update.apk');

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final sink = apkFile.openWrite();
      int receivedBytes = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          onProgress(progress, receivedBytes, totalBytes);
        } else {
          onProgress(0.5, receivedBytes, totalBytes);
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      onProgress(1.0, receivedBytes, totalBytes);

      // Abrir el APK con el instalador nativo de Android
      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done && result.type != ResultType.noAppToOpen) {
        onError('No se pudo iniciar el instalador: ${result.message}');
      }
    } catch (e) {
      debugPrint('Error durante la descarga o apertura del APK: $e');
      onError('Error al descargar la actualización: $e');
    }
  }
}
