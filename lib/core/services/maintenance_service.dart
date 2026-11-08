import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Estado del modo mantenimiento que se programa desde el panel.
///   1 = aviso, 2 = nube en pausa (la app sigue funcionando en el equipo),
///   3 = cierre total. Partes: 'app', 'stores', 'payments'.
@immutable
class MaintenanceState {
  final String state; // 'none' | 'notice' | 'active'
  final int level;
  final Set<String> scopes;
  final String? message;
  final DateTime? startsAt;
  final DateTime? endsAt;

  const MaintenanceState({
    this.state = 'none',
    this.level = 0,
    this.scopes = const {},
    this.message,
    this.startsAt,
    this.endsAt,
  });

  static const none = MaintenanceState();

  factory MaintenanceState.fromJson(Map<String, dynamic> j) => MaintenanceState(
        state: j['state'] as String? ?? 'none',
        level: (j['level'] as num?)?.toInt() ?? 0,
        scopes: {for (final s in (j['scopes'] as List? ?? const [])) '$s'},
        message: j['message'] as String?,
        startsAt: DateTime.tryParse('${j['starts_at']}')?.toLocal(),
        endsAt: DateTime.tryParse('${j['ends_at']}')?.toLocal(),
      );

  bool get active => state == 'active';
  bool get notice => state == 'notice';
  bool affects(String scope) => scopes.contains(scope);

  /// La app sigue funcionando en el equipo, pero sin enviar ni recibir de la nube
  bool get cloudPaused => active && affects('app') && level >= 2;

  /// Pantalla de mantenimiento en lugar de la app
  bool get appClosed => active && affects('app') && level >= 3;

  /// Tiendas en línea cerradas con su aviso
  bool get storesClosed => active && affects('stores') && level >= 2;

  bool get paymentsPaused => active && affects('payments') && level >= 2;

  @override
  bool operator ==(Object other) =>
      other is MaintenanceState &&
      other.state == state &&
      other.level == level &&
      setEquals(other.scopes, scopes) &&
      other.message == message &&
      other.startsAt == startsAt &&
      other.endsAt == endsAt;

  @override
  int get hashCode => Object.hash(state, level, Object.hashAllUnordered(scopes), message, startsAt, endsAt);
}

/// Consulta el mantenimiento al abrir, cada pocos minutos y al volver a la app.
/// Los administradores no quedan bloqueados: tienen que poder probar antes de reabrir.
class MaintenanceService {
  MaintenanceService._();
  static final instance = MaintenanceService._();

  final state = ValueNotifier<MaintenanceState>(MaintenanceState.none);
  bool _isAdmin = false;
  Timer? _timer;
  SupabaseClient? _client;

  bool get isAdmin => _isAdmin;

  /// Para quien no es administrador
  bool get cloudPaused => !_isAdmin && state.value.cloudPaused;
  bool get appClosed => !_isAdmin && state.value.appClosed;

  void start(SupabaseClient? client) {
    _client = client;
    refresh();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => refresh());
  }

  Future<void> refresh() async {
    final client = _client;
    if (client == null) return;
    try {
      final data = await client.rpc('get_maintenance');
      final next = data is Map ? MaintenanceState.fromJson(Map<String, dynamic>.from(data)) : MaintenanceState.none;
      if (client.auth.currentSession != null) {
        try {
          _isAdmin = await client.rpc('is_app_admin') == true;
        } catch (_) {
          _isAdmin = false;
        }
        _reportVersion(client);
      } else {
        _isAdmin = false;
      }
      // Si ya pasó la hora de fin se apaga sin esperar la próxima consulta
      state.value = next;
      _scheduleEnd(next);
    } catch (e) {
      // Sin conexión o servidor sin la función: se deja el último estado conocido
      debugPrint('Mantenimiento: $e');
    }
  }

  bool _versionReported = false;

  /// Una vez por apertura: plataforma y versión, para saber en el panel quién sigue en
  /// versiones viejas. No se envía nada más.
  Future<void> _reportVersion(SupabaseClient client) async {
    if (_versionReported) return;
    _versionReported = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final platform = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
      final version = info.buildNumber.isEmpty ? info.version : '${info.version}+${info.buildNumber}';
      await client.rpc('report_app_version', params: {'p_platform': platform, 'p_version': version});
    } catch (_) {
      _versionReported = false; // se reintenta en la próxima consulta
    }
  }

  Timer? _endTimer;
  void _scheduleEnd(MaintenanceState s) {
    _endTimer?.cancel();
    final target = s.active ? s.endsAt : (s.notice ? s.startsAt : null);
    if (target == null) return;
    final wait = target.difference(DateTime.now());
    if (wait.isNegative || wait > const Duration(hours: 49)) return;
    _endTimer = Timer(wait + const Duration(seconds: 5), refresh);
  }

  @visibleForTesting
  void debugSet(MaintenanceState s, {bool admin = false}) {
    _isAdmin = admin;
    state.value = s;
  }
}
