import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

/// Una solicitud de autorización (0.15.0, etapa 3 de `docs/plan-roles.md`)
class AuthRequest {
  final String id;
  final String businessId;
  final int number;
  final String action;
  final String? detail;
  final double? amount;
  final String requestedBy;
  final String? requestedName;

  /// 'PENDIENTE', 'APROBADA', 'RECHAZADA' o 'USADA'
  final String status;
  final String? decidedName;
  final DateTime createdAt;
  final DateTime expiresAt;

  const AuthRequest({
    required this.id,
    required this.businessId,
    required this.number,
    required this.action,
    this.detail,
    this.amount,
    required this.requestedBy,
    this.requestedName,
    required this.status,
    this.decidedName,
    required this.createdAt,
    required this.expiresAt,
  });

  static const pending = 'PENDIENTE';
  static const approved = 'APROBADA';
  static const rejected = 'RECHAZADA';
  static const used = 'USADA';

  bool expired([DateTime? now]) => (now ?? DateTime.now()).isAfter(expiresAt);

  factory AuthRequest.fromJson(Map<String, dynamic> j) => AuthRequest(
        id: j['id'] as String,
        businessId: j['business_id'] as String,
        number: (j['number'] as num).toInt(),
        action: j['action'] as String? ?? '',
        detail: j['detail'] as String?,
        amount: (j['amount'] as num?)?.toDouble(),
        requestedBy: j['requested_by'] as String? ?? '',
        requestedName: j['requested_name'] as String?,
        status: j['status'] as String? ?? pending,
        decidedName: j['decided_name'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
        expiresAt: DateTime.tryParse('${j['expires_at']}')?.toLocal() ?? DateTime.now(),
      );
}

class AuthorizationException implements Exception {
  final String message;
  const AuthorizationException(this.message);
  @override
  String toString() => message;
}

/// Autorización de un solo uso, solo con internet (decisión del dueño, 14 nov 2026):
/// el cajero pide, el administrador o el dueño aprueba en su celular, y la aprobación
/// sirve una sola vez durante 5 minutos. Todo lo decide el servidor.
class AuthorizationService {
  static final AuthorizationService instance = AuthorizationService._();
  AuthorizationService._();

  SupabaseClient get _client {
    final client = SupabaseService.instance.client;
    if (client == null || client.auth.currentSession == null) {
      throw const AuthorizationException('Para pedir una autorización necesitas internet y haber iniciado sesión.');
    }
    return client;
  }

  String? get myUserId => SupabaseService.instance.client?.auth.currentUser?.id;

  static String _message(Object e) {
    final text = e is PostgrestException ? e.message : '$e';
    if (text.contains('own_request')) return 'No puedes aprobar tu propia solicitud.';
    if (text.contains('not_allowed')) return 'Solo el dueño o un administrador pueden autorizar.';
    if (text.contains('not_pending')) return 'Esa solicitud ya se decidió o venció.';
    if (text.contains('not_member')) return 'No perteneces a este negocio.';
    return 'Sin conexión: la autorización necesita internet. Inténtalo de nuevo.';
  }

  Future<T> _run<T>(Future<T> Function(SupabaseClient c) body) async {
    final client = _client;
    try {
      return await body(client);
    } on AuthorizationException {
      rethrow;
    } catch (e) {
      debugPrint('Autorización: $e');
      throw AuthorizationException(_message(e));
    }
  }

  Future<AuthRequest> create({
    required String businessId,
    required String action,
    String? detail,
    double? amount,
    String? requestedName,
  }) =>
      _run((c) async {
        final data = await c.rpc('create_auth_request', params: {
          'p_business_id': businessId,
          'p_action': action,
          'p_detail': detail,
          'p_amount': amount,
          'p_name': requestedName,
        });
        return AuthRequest.fromJson(Map<String, dynamic>.from(data as Map));
      });

  Future<AuthRequest?> fetch(String id) => _run((c) async {
        final row = await c.from('auth_requests').select().eq('id', id).maybeSingle();
        return row == null ? null : AuthRequest.fromJson(row);
      });

  Future<AuthRequest> decide(String id, {required bool approve, String? name}) => _run((c) async {
        final data = await c.rpc('decide_auth_request', params: {'p_id': id, 'p_approve': approve, 'p_name': name});
        return AuthRequest.fromJson(Map<String, dynamic>.from(data as Map));
      });

  /// Gasta la aprobación: true solo una vez y antes de que venza
  Future<bool> use(String id) => _run((c) async => await c.rpc('use_auth_request', params: {'p_id': id}) == true);

  /// Las que esperan respuesta en el negocio (para quien autoriza)
  Future<List<AuthRequest>> pendingFor(String businessId) => _run((c) async {
        final rows = await c
            .from('auth_requests')
            .select()
            .eq('business_id', businessId)
            .eq('status', AuthRequest.pending)
            .gt('expires_at', DateTime.now().toUtc().toIso8601String())
            .order('created_at');
        return [for (final r in rows) AuthRequest.fromJson(r)];
      });

  /// Avisa al instante cuando llega una solicitud nueva al negocio
  RealtimeChannel? listen(String businessId, void Function(AuthRequest request) onNew) {
    final client = SupabaseService.instance.client;
    if (client == null || client.auth.currentSession == null) return null;
    return client
        .channel('auth-requests-$businessId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'auth_requests',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'business_id', value: businessId),
          callback: (payload) {
            try {
              onNew(AuthRequest.fromJson(payload.newRecord));
            } catch (e) {
              debugPrint('Aviso de autorización: $e');
            }
          },
        )
        .subscribe();
  }
}
