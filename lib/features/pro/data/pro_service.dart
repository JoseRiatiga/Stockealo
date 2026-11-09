import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

/// Estado Pro de un negocio
class ProStatus {
  final bool active;

  /// 'business' (Pro Negocio), 'global' (Pro Global) o 'services' (Pro Servicios)
  final String? kind;

  /// null con Pro activo = permanente
  final DateTime? endsAt;

  /// Tiene Pro Servicios: se ve la pestaña Servicios (incluye todo lo de Pro)
  final bool services;

  const ProStatus({required this.active, this.kind, this.endsAt, this.services = false});

  static const none = ProStatus(active: false);

  bool get lifetime => active && endsAt == null;

  String get kindLabel => proKindLabel(kind);
}

/// Nombre de cada plan para mostrar
String proKindLabel(String? kind) => switch (kind) {
      'global' => 'Pro Global',
      'services' => 'Pro Servicios',
      _ => 'Pro Negocio',
    };

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

  String get kindLabel => proKindLabel(kind);

  String get periodLabel => switch (period) {
        'week' => 'Semanal',
        'month' => 'Mensual',
        'year' => 'Anual',
        _ => 'Permanente',
      };

  String get perLabel => switch (period) {
        'week' => '/ semana',
        'month' => '/ mes',
        'year' => '/ año',
        _ => 'un solo pago',
      };
}

/// Un pago en línea con Wompi recién iniciado
class ProCheckout {
  final String reference;
  final String url;

  const ProCheckout(this.reference, this.url);
}

/// No se pudo iniciar el pago en línea; [message] se muestra tal cual
class ProCheckoutException implements Exception {
  final String message;

  const ProCheckoutException(this.message);

  @override
  String toString() => message;
}

/// Estado de un pago en línea: PENDING, APPROVED, DECLINED, VOIDED o ERROR
enum ProPaymentState { pending, approved, declined, error }

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
    await SupabaseService.instance.ensureFreshSession();
    try {
      final data = await client.rpc('pro_status', params: {'p_business_id': businessId});
      final map = Map<String, dynamic>.from(data as Map);
      final result = ProStatus(
        active: map['active'] == true,
        kind: map['kind'] as String?,
        endsAt: map['ends_at'] == null ? null : DateTime.tryParse(map['ends_at'] as String)?.toLocal(),
        services: map['services'] == true,
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

  /// Precios y compra se muestran solo si el panel encendió «Mostrar precios y compra»
  static bool pricingVisible(Map<String, String> settings) => settings['show_pricing'] == 'on';

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
    final clean = normalizeCode(code);
    if (clean.isEmpty) return const RedeemResult(false, 'Escribe el código que te enviamos.');
    // El servidor busca al dueño en la nube: un negocio que solo vive en este
    // equipo respondería "Solo el dueño…" aunque quien canjea sí sea el dueño
    if (!await SupabaseService.instance.ensureBusinessInCloud(businessId)) {
      return const RedeemResult(false, notInCloudMessage);
    }
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

  /// Inicia el pago de un plan con Wompi: el servidor fija el precio y firma el enlace
  Future<ProCheckout> startCheckout(String businessId, String planId) async {
    final client = _client;
    if (client == null) throw const ProCheckoutException('Necesitas conexión a internet para pagar.');
    // Antes de cobrar: el pago se aplica a un negocio que debe existir en la nube
    if (!await SupabaseService.instance.ensureBusinessInCloud(businessId)) {
      throw const ProCheckoutException(notInCloudMessage);
    }
    try {
      // En la web, Wompi devuelve a una página que dice "vuelve a la pestaña de Stockealo"
      final res = await client.functions.invoke('pro-checkout',
          body: {'business_id': businessId, 'plan_id': planId, 'platform': kIsWeb ? 'web' : 'app'});
      final data = Map<String, dynamic>.from(res.data as Map);
      return ProCheckout(data['reference'] as String, data['url'] as String);
    } on FunctionException catch (e) {
      final code = e.details is Map ? (e.details as Map)['error']?.toString() ?? '' : '${e.details}';
      throw ProCheckoutException(checkoutErrorMessage(code));
    } on ProCheckoutException {
      rethrow;
    } catch (e) {
      debugPrint('Pago en línea: $e');
      throw const ProCheckoutException('No se pudo iniciar el pago. Inténtalo de nuevo.');
    }
  }

  /// Estado de un pago iniciado desde este celular; null si no se encuentra
  Future<ProPaymentState?> paymentState(String reference) async {
    final client = _client;
    if (client == null) return null;
    try {
      final data = await client.rpc('pro_payment_status', params: {'p_reference': reference});
      if (data == null) return null;
      return paymentStateFrom((data as Map)['status'] as String?);
    } catch (e) {
      debugPrint('Estado del pago: $e');
      return null;
    }
  }

  @visibleForTesting
  static ProPaymentState paymentStateFrom(String? status) => switch (status) {
        'APPROVED' => ProPaymentState.approved,
        'DECLINED' || 'VOIDED' => ProPaymentState.declined,
        'ERROR' => ProPaymentState.error,
        _ => ProPaymentState.pending,
      };

  @visibleForTesting
  static String checkoutErrorMessage(String code) {
    if (code.contains('maintenance')) return 'Los pagos están en pausa por mantenimiento. Inténtalo en un rato.';
    if (code.contains('not_allowed')) return 'Solo el dueño o un administrador del negocio puede comprar Pro.';
    if (code.contains('currency_not_supported')) return 'El pago en línea por ahora es solo en pesos colombianos.';
    if (code.contains('payments_not_configured')) return 'El pago en línea no está disponible ahora. Usa Nequi.';
    if (code.contains('plan_not_found')) return 'Ese plan ya no está disponible.';
    return 'No se pudo iniciar el pago. Inténtalo de nuevo.';
  }

  static const notInCloudMessage =
      'Tu negocio todavía no está en la nube y Pro lo necesita. Revisa tu conexión, '
      've a Ajustes › Nube y respaldo, toca "Sincronizar ahora" e inténtalo de nuevo.';

  /// Mayúsculas y sin espacios; si escribieron el código sin guiones
  /// (STKJA4YFVFV) se le ponen, porque así se guardan (STK-JA4Y-FVFV).
  @visibleForTesting
  static String normalizeCode(String code) {
    final clean = code.replaceAll(RegExp(r'\s'), '').toUpperCase();
    final bare = RegExp(r'^STK([A-Z0-9]{4})([A-Z0-9]{4})$').firstMatch(clean);
    return bare == null ? clean : 'STK-${bare[1]}-${bare[2]}';
  }

  /// Mensaje para cada error del servidor al canjear
  @visibleForTesting
  static String redeemErrorMessage(String serverMessage) {
    if (serverMessage.contains('not_member')) return notInCloudMessage;
    if (serverMessage.contains('code_not_found')) return 'Ese código no existe. Revisa que esté bien escrito.';
    if (serverMessage.contains('code_expired')) return 'Ese código ya venció.';
    if (serverMessage.contains('code_already_redeemed')) return 'Ya canjeaste ese código.';
    if (serverMessage.contains('code_used')) return 'Ese código ya fue usado.';
    if (serverMessage.contains('owner_only')) return 'Solo el dueño del negocio puede activar Pro Negocio.';
    return 'No se pudo canjear el código. Inténtalo de nuevo.';
  }
}
