import 'package:flutter/foundation.dart';

import '../app_version.dart';
import 'supabase_service.dart';

/// Reporte automático de errores (0.16.0, fase 5): cuando algo falla, la app lo manda
/// al panel de administración. Nunca manda datos de clientes ni contraseñas: solo el
/// error, la versión, el tipo de equipo y en qué app pasó. Los correos y los números
/// largos (teléfonos, documentos) se tapan antes de enviar.
class ErrorReporter {
  ErrorReporter._();
  static final ErrorReporter instance = ErrorReporter._();

  /// Máximo por sesión: si algo falla en bucle, no inunda la nube
  static const maxPerSession = 20;

  final Set<String> _sent = {};
  String _app = 'app';

  /// Para las pruebas: a dónde va el reporte (por defecto, la nube; en modo de
  /// desarrollo no se manda nada)
  @visibleForTesting
  Future<void> Function(Map<String, dynamic> report)? sender;

  /// Se llama al arrancar: 'app', 'admin' o 'tienda'
  void install(String app) {
    _app = app;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(details.exception, details.stack, kind: 'flutter');
    };
    final platformPrevious = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, kind: 'async');
      return platformPrevious?.call(error, stack) ?? false;
    };
  }

  /// Tapa lo que podría ser personal: correos y números de 7 cifras o más
  static String clean(String text) => text
      .replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '<correo>')
      .replaceAll(RegExp(r'\d[\d ]{6,}\d'), '<número>');

  /// El mismo error (mensaje y primera línea del rastro) cuenta una vez por sesión
  static String fingerprint(String message, String? stack) {
    final firstFrame = (stack ?? '').split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
    final base = '${message.length > 160 ? message.substring(0, 160) : message}|$firstFrame';
    var h = 0;
    for (final c in base.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h.toRadixString(16);
  }

  static String get platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'otro',
    };
  }

  Future<void> report(Object error, StackTrace? stack, {String kind = 'manual'}) async {
    final message = clean('$error');
    final trace = stack == null ? null : clean(stack.toString());
    final fp = fingerprint(message, trace);
    if (_sent.length >= maxPerSession || !_sent.add(fp)) return;
    final payload = <String, dynamic>{
      'p_app': _app,
      'p_version': '$kAppVersion+$kAppBuildNumber',
      'p_platform': platform,
      'p_kind': kind,
      'p_fingerprint': fp,
      'p_message': message.length > 500 ? message.substring(0, 500) : message,
      'p_stack': trace == null ? null : (trace.length > 4000 ? trace.substring(0, 4000) : trace),
    };
    final send = sender;
    try {
      if (send != null) {
        await send(payload);
      } else if (!kDebugMode) {
        await SupabaseService.instance.client?.rpc('report_app_error', params: payload);
      }
    } catch (_) {
      // Si no se puede reportar, no pasa nada: nunca se rompe la app por esto
    }
  }

  @visibleForTesting
  void resetForTest() => _sent.clear();
}
