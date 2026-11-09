import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_version.dart';
import 'web_reload_stub.dart' if (dart.library.js_interop) 'web_reload_web.dart' as reload;

/// Aviso de versión nueva en la web (stockealo.online/app).
///
/// La web guarda la app en el navegador (service worker) y la gente se quedaba
/// con versiones viejas. Cada cierto tiempo se consulta el version.json publicado
/// (sin caché) y, si su número de compilación es mayor que el de esta app, se
/// ofrece actualizar: se borra lo guardado y se recarga la página.
class WebUpdateService {
  WebUpdateService._();
  static final WebUpdateService instance = WebUpdateService._();

  /// Cada cuánto se vuelve a consultar mientras la app está abierta
  static const Duration checkEvery = Duration(minutes: 30);

  /// Versión publicada si es más nueva que la que está corriendo; null si no
  /// hay versión nueva, no es la web o no hubo conexión.
  Future<String?> checkForNewVersion() async {
    if (!kIsWeb) return null;
    try {
      final url = Uri.base.resolve('version.json').replace(
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch.toString()},
      );
      final res = await http
          .get(url, headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) return null;
      if (!isNewer(data, currentBuild: kAppBuildNumber)) return null;
      return (data['version'] as String?) ?? '';
    } catch (_) {
      return null;
    }
  }

  /// Borra la app guardada en el navegador y recarga la página
  Future<void> reloadToLatest() => reload.clearCacheAndReload();

  @visibleForTesting
  static bool isNewer(Map<String, dynamic> versionJson, {required int currentBuild}) {
    final raw = versionJson['build_number'];
    final build = raw is int ? raw : int.tryParse('${raw ?? ''}');
    return build != null && build > currentBuild;
  }
}
