import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

/// Un código Pro visto desde la administración
class ProCode {
  final String code;
  final String kind;

  /// null = permanente
  final int? days;
  final int maxUses;
  final int uses;
  final String? note;
  final DateTime createdAt;

  /// Correos de quienes lo canjearon
  final String? redeemedBy;

  const ProCode({
    required this.code,
    required this.kind,
    required this.days,
    required this.maxUses,
    required this.uses,
    required this.note,
    required this.createdAt,
    this.redeemedBy,
  });

  factory ProCode.fromRow(Map<String, dynamic> r) => ProCode(
        code: r['code'] as String,
        kind: r['kind'] as String,
        days: (r['days'] as num?)?.toInt(),
        maxUses: (r['max_uses'] as num?)?.toInt() ?? 1,
        uses: (r['uses'] as num?)?.toInt() ?? 0,
        note: r['note'] as String?,
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        redeemedBy: r['redeemed_by'] as String?,
      );

  String get kindLabel => kind == 'global' ? 'Pro Global' : 'Pro Negocio';

  String get durationLabel => switch (days) {
        null => 'Permanente',
        1 => '1 día',
        7 => '1 semana',
        30 => '1 mes',
        _ => '$days días',
      };

  bool get exhausted => uses >= maxUses;
}

/// Administración de Stockealo Pro (solo cuentas de app_admins). El servidor
/// comprueba el permiso en cada llamada; aquí solo se decide si mostrar la opción.
class ProAdminService {
  ProAdminService._();
  static final ProAdminService instance = ProAdminService._();

  SupabaseClient? get _client {
    final client = SupabaseService.instance.client;
    return client?.auth.currentSession == null ? null : client;
  }

  Future<bool> isAdmin() async {
    final client = _client;
    if (client == null) return false;
    try {
      return await client.rpc('is_app_admin') == true;
    } catch (e) {
      debugPrint('Administración no disponible: $e');
      return false;
    }
  }

  /// Crea [count] códigos; [days] null = permanentes. Devuelve los códigos nuevos.
  Future<List<String>> createCodes({
    required String kind,
    required int? days,
    int count = 1,
    int maxUses = 1,
    String? note,
  }) async {
    final client = _client;
    if (client == null) throw const ProAdminException('Necesitas conexión a internet.');
    try {
      final data = await client.rpc('admin_create_pro_codes', params: {
        'p_kind': kind,
        'p_days': days,
        'p_count': count,
        'p_note': note,
        'p_max_uses': maxUses,
      });
      return [for (final c in data as List) c as String];
    } on PostgrestException catch (e) {
      throw ProAdminException(errorMessage(e.message));
    }
  }

  Future<List<ProCode>> listCodes({int limit = 50}) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client.rpc('admin_list_pro_codes', params: {'p_limit': limit});
      return [for (final r in rows as List) ProCode.fromRow(Map<String, dynamic>.from(r as Map))];
    } on PostgrestException catch (e) {
      throw ProAdminException(errorMessage(e.message));
    }
  }

  @visibleForTesting
  static String errorMessage(String serverMessage) {
    if (serverMessage.contains('admin_only')) return 'Esta cuenta no es administradora.';
    if (serverMessage.contains('invalid_count')) return 'Puedes crear de 1 a 50 códigos por vez.';
    if (serverMessage.contains('invalid_days')) return 'La duración debe ser de 1 a 3650 días.';
    if (serverMessage.contains('invalid_max_uses')) return 'Los usos por código deben ser de 1 a 1000.';
    if (serverMessage.contains('invalid_kind')) return 'Elige Pro Negocio o Pro Global.';
    return 'No se pudo completar. Inténtalo de nuevo.';
  }
}

class ProAdminException implements Exception {
  final String message;

  const ProAdminException(this.message);

  @override
  String toString() => message;
}
