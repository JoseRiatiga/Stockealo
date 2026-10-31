import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

/// Estado Pro de un negocio
class ProStatus {
  final bool active;

  /// 'business' (Pro Negocio) o 'global' (Pro Global)
  final String? kind;

  /// null con Pro activo = permanente
  final DateTime? endsAt;

  const ProStatus({required this.active, this.kind, this.endsAt});

  static const none = ProStatus(active: false);

  bool get lifetime => active && endsAt == null;

  String get kindLabel => kind == 'global' ? 'Pro Global' : 'Pro Negocio';
}

/// Un plan con su precio en una moneda
class ProPlan {
  final String id;
  final String kind;
  final String period;
  final String currency;
  final double price;
  final double? regularPrice;
  final String? label;

  const ProPlan({
    required this.id,
    required this.kind,
    required this.period,
    required this.currency,
    required this.price,
    this.regularPrice,
    this.label,
  });

  factory ProPlan.fromRow(Map<String, dynamic> r) => ProPlan(
        id: r['id'] as String,
        kind: r['kind'] as String,
        period: r['period'] as String,
        currency: r['currency'] as String,
        price: (r['price'] as num).toDouble(),
        regularPrice: (r['regular_price'] as num?)?.toDouble(),
        label: r['label'] as String?,
      );

  String get periodLabel => switch (period) {
        'week' => 'Semanal',
        'month' => 'Mensual',
        _ => 'Permanente',
      };

  String get perLabel => switch (period) {
        'week' => '/ semana',
        'month' => '/ mes',
        _ => 'un solo pago',
      };
}

/// Resultado de canjear un código
class RedeemResult {
  final bool ok;
  final String message;

  const RedeemResult(this.ok, this.message);
}

/// Stockealo Pro: estado del negocio, planes y canje de códigos.
/// La verdad está en el servidor (subscriptions); aquí solo se consulta.
class ProService {
  ProService._();
  static final ProService instance = ProService._();

  /// Estado del negocio activo, para que las pantallas se actualicen al canjear
  final status = ValueNotifier<ProStatus>(ProStatus.none);
  String? _statusBusinessId;

  SupabaseClient? get _client {
    final client = SupabaseService.instance.client;
    return client?.auth.currentSession == null ? null : client;
  }

  /// Consulta el estado Pro del negocio. Sin conexión deja el último conocido.
  Future<ProStatus> refresh(String businessId) async {
    if (_statusBusinessId != businessId) {
      _statusBusinessId = businessId;
      status.value = ProStatus.none;
    }
    final client = _client;
    if (client == null) return status.value;
    try {
      final data = await client.rpc('pro_status', params: {'p_business_id': businessId});
      final map = Map<String, dynamic>.from(data as Map);
      final result = ProStatus(
        active: map['active'] == true,
        kind: map['kind'] as String?,
        endsAt: map['ends_at'] == null ? null : DateTime.tryParse(map['ends_at'] as String)?.toLocal(),
      );
      if (_statusBusinessId == businessId) status.value = result;
      return result;
    } catch (e) {
      debugPrint('Estado Pro no disponible: $e');
      return status.value;
    }
  }

  Future<List<ProPlan>> plans(String currency) async {
    final client = _client;
    if (client == null) return const [];
    final rows = await client.from('pro_plans').select().eq('currency', currency).order('sort');
    return [for (final r in rows) ProPlan.fromRow(r)];
  }

  /// Número de Nequi, WhatsApp, aviso legal…
  Future<Map<String, String>> settings() async {
    final client = _client;
    if (client == null) return const {};
    final rows = await client.from('pro_settings').select();
    return {
      for (final r in rows)
        if (r['value'] != null && (r['value'] as String).trim().isNotEmpty) r['key'] as String: (r['value'] as String).trim(),
    };
  }

  Future<RedeemResult> redeem(String code, String businessId) async {
    final client = _client;
    if (client == null) return const RedeemResult(false, 'Necesitas conexión a internet para canjear el código.');
    final clean = code.trim().toUpperCase();
    if (clean.isEmpty) return const RedeemResult(false, 'Escribe el código que te enviamos.');
    try {
      final data = await client.rpc('redeem_pro_code', params: {'p_code': clean, 'p_business_id': businessId});
      final map = Map<String, dynamic>.from(data as Map);
      await refresh(businessId);
      final kind = map['kind'] == 'global' ? 'Pro Global' : 'Pro Negocio';
      final days = map['days'] as int?;
      return RedeemResult(true, days == null ? '¡Listo! Tienes $kind para siempre.' : '¡Listo! Sumaste $days días de $kind.');
    } on PostgrestException catch (e) {
      return RedeemResult(false, redeemErrorMessage(e.message));
    } catch (e) {
      debugPrint('Canje de código: $e');
      return const RedeemResult(false, 'No se pudo canjear el código. Inténtalo de nuevo.');
    }
  }

  /// Mensaje para cada error del servidor al canjear
  @visibleForTesting
  static String redeemErrorMessage(String serverMessage) {
    if (serverMessage.contains('code_not_found')) return 'Ese código no existe. Revisa que esté bien escrito.';
    if (serverMessage.contains('code_expired')) return 'Ese código ya venció.';
    if (serverMessage.contains('code_already_redeemed')) return 'Ya canjeaste ese código.';
    if (serverMessage.contains('code_used')) return 'Ese código ya fue usado.';
    if (serverMessage.contains('owner_only')) return 'Solo el dueño del negocio puede activar Pro Negocio.';
    return 'No se pudo canjear el código. Inténtalo de nuevo.';
  }
}
