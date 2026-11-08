import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();
int _int(Object? v) => (v as num?)?.toInt() ?? 0;

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

  /// Fecha límite para canjearlo; null = sin vencimiento
  final DateTime? expiresAt;

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
    this.expiresAt,
    this.redeemedBy,
  });

  factory ProCode.fromRow(Map<String, dynamic> r) => ProCode(
        code: r['code'] as String,
        kind: r['kind'] as String,
        days: (r['days'] as num?)?.toInt(),
        maxUses: (r['max_uses'] as num?)?.toInt() ?? 1,
        uses: _int(r['uses']),
        note: r['note'] as String?,
        createdAt: _date(r['created_at']) ?? DateTime.now(),
        expiresAt: _date(r['expires_at']),
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

  bool isExpired([DateTime? now]) => expiresAt != null && !expiresAt!.isAfter(now ?? DateTime.now());

  /// 'Usado', 'Vencido', 'n/m usos' o 'Sin usar'
  String statusLabel([DateTime? now]) {
    if (exhausted) return 'Usado';
    if (isExpired(now)) return 'Vencido';
    return uses > 0 ? '$uses/$maxUses usos' : 'Sin usar';
  }

  bool canDisable([DateTime? now]) => !exhausted && !isExpired(now);

  /// Mensaje para mandarle el código al cliente por WhatsApp
  String shareMessage() => 'Hola, este es tu código de Stockealo Pro ($kindLabel · $durationLabel): $code\n\n'
      'Canjéalo en la app: Ajustes › Stockealo Pro › "¿Tienes un código?". ¡Gracias por tu compra!';
}

/// Cifras de la portada del panel
class AdminSummary {
  final int usersTotal;
  final int users7d;
  final int users30d;
  final int businessesTotal;
  final int businessesPro;
  final int subscriptionsActive;
  final int subscriptionsEnding7d;
  final int redemptions30d;
  final int codesUnused;
  final int storesTotal;
  final int storesLive;

  const AdminSummary({
    required this.usersTotal,
    required this.users7d,
    required this.users30d,
    required this.businessesTotal,
    required this.businessesPro,
    required this.subscriptionsActive,
    required this.subscriptionsEnding7d,
    required this.redemptions30d,
    required this.codesUnused,
    required this.storesTotal,
    required this.storesLive,
  });

  factory AdminSummary.fromJson(Map<String, dynamic> j) => AdminSummary(
        usersTotal: _int(j['users_total']),
        users7d: _int(j['users_7d']),
        users30d: _int(j['users_30d']),
        businessesTotal: _int(j['businesses_total']),
        businessesPro: _int(j['businesses_pro']),
        subscriptionsActive: _int(j['subscriptions_active']),
        subscriptionsEnding7d: _int(j['subscriptions_ending_7d']),
        redemptions30d: _int(j['redemptions_30d']),
        codesUnused: _int(j['codes_unused']),
        storesTotal: _int(j['stores_total']),
        storesLive: _int(j['stores_live']),
      );
}

/// Una cuenta registrada
class AdminUser {
  final String email;
  final String? name;
  final String? phone;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final int businesses;
  final bool pro;

  const AdminUser({
    required this.email,
    this.name,
    this.phone,
    this.createdAt,
    this.lastSignInAt,
    this.businesses = 0,
    this.pro = false,
  });

  factory AdminUser.fromRow(Map<String, dynamic> r) => AdminUser(
        email: r['email'] as String? ?? '',
        name: r['name'] as String?,
        phone: r['phone'] as String?,
        createdAt: _date(r['created_at']),
        lastSignInAt: _date(r['last_sign_in_at']),
        businesses: _int(r['businesses']),
        pro: r['pro'] == true,
      );
}

/// Un negocio, para buscar a quién darle Pro
class AdminBusiness {
  final String id;
  final String name;
  final String? ownerEmail;
  final String? country;
  final bool pro;

  const AdminBusiness({required this.id, required this.name, this.ownerEmail, this.country, this.pro = false});

  factory AdminBusiness.fromRow(Map<String, dynamic> r) => AdminBusiness(
        id: r['id'] as String,
        name: r['name'] as String? ?? '',
        ownerEmail: r['owner_email'] as String?,
        country: r['country'] as String?,
        pro: r['pro'] == true,
      );
}

/// Una tienda en línea
class AdminStore {
  final String businessId;
  final String businessName;
  final String? ownerEmail;
  final String slug;
  final bool enabled;
  final bool pro;
  final int products;
  final DateTime? updatedAt;

  const AdminStore({
    required this.businessId,
    required this.businessName,
    required this.slug,
    this.ownerEmail,
    this.enabled = false,
    this.pro = false,
    this.products = 0,
    this.updatedAt,
  });

  factory AdminStore.fromRow(Map<String, dynamic> r) => AdminStore(
        businessId: r['business_id'] as String,
        businessName: r['business_name'] as String? ?? '',
        ownerEmail: r['owner_email'] as String?,
        slug: r['slug'] as String,
        enabled: r['enabled'] == true,
        pro: r['pro'] == true,
        products: _int(r['products']),
        updatedAt: _date(r['updated_at']),
      );

  /// La ven los compradores: encendida y con Pro
  bool get live => enabled && pro;

  String get statusLabel => live ? 'Publicada' : (!enabled ? 'Apagada' : 'Sin Pro (no se ve)');

  String get url => 'https://stockealo.online/tienda/$slug';
}

/// Una suscripción Pro
class AdminSubscription {
  final String id;
  final String kind;
  final String? businessId;
  final String? businessName;
  final String ownerEmail;
  final String source;
  final DateTime? startsAt;

  /// null = permanente
  final DateTime? endsAt;
  final bool active;

  const AdminSubscription({
    required this.id,
    required this.kind,
    required this.ownerEmail,
    required this.source,
    this.businessId,
    this.businessName,
    this.startsAt,
    this.endsAt,
    this.active = false,
  });

  factory AdminSubscription.fromRow(Map<String, dynamic> r) => AdminSubscription(
        id: r['id'] as String,
        kind: r['kind'] as String,
        businessId: r['business_id'] as String?,
        businessName: r['business_name'] as String?,
        ownerEmail: r['owner_email'] as String? ?? '',
        source: r['source'] as String? ?? 'code',
        startsAt: _date(r['starts_at']),
        endsAt: _date(r['ends_at']),
        active: r['active'] == true,
      );

  String get kindLabel => kind == 'global' ? 'Pro Global' : 'Pro Negocio';

  String get sourceLabel => switch (source) {
        'manual' => 'Dado a mano',
        'gateway' => 'Pago en línea',
        _ => 'Código',
      };

  /// Vence en los próximos 7 días
  bool endingSoon([DateTime? now]) {
    final n = now ?? DateTime.now();
    return active && endsAt != null && endsAt!.isBefore(n.add(const Duration(days: 7)));
  }
}

/// Un pago en línea (Wompi)
class AdminPayment {
  final String reference;
  final String? businessName;
  final String userEmail;
  final String kind;
  final String period;
  final int amountInCents;
  final String currency;
  final String status;
  final String? paymentMethod;
  final String? transactionId;
  final DateTime? createdAt;

  const AdminPayment({
    required this.reference,
    required this.userEmail,
    required this.kind,
    required this.period,
    required this.amountInCents,
    required this.currency,
    required this.status,
    this.businessName,
    this.paymentMethod,
    this.transactionId,
    this.createdAt,
  });

  factory AdminPayment.fromRow(Map<String, dynamic> r) => AdminPayment(
        reference: r['reference'] as String,
        businessName: r['business_name'] as String?,
        userEmail: r['user_email'] as String? ?? '',
        kind: r['kind'] as String? ?? 'business',
        period: r['period'] as String? ?? 'month',
        amountInCents: _int(r['amount_in_cents']),
        currency: r['currency'] as String? ?? 'COP',
        status: r['status'] as String? ?? 'PENDING',
        paymentMethod: r['payment_method'] as String?,
        transactionId: r['wompi_transaction_id'] as String?,
        createdAt: _date(r['created_at']),
      );

  double get amount => amountInCents / 100;

  String get planLabel {
    final plan = kind == 'global' ? 'Pro Global' : 'Pro Negocio';
    final per = switch (period) {
      'week' => 'Semanal',
      'month' => 'Mensual',
      'year' => 'Anual',
      _ => 'Permanente',
    };
    return '$plan · $per';
  }

  String get statusLabel => switch (status) {
        'APPROVED' => 'Aprobado',
        'DECLINED' => 'Rechazado',
        'VOIDED' => 'Anulado',
        'ERROR' => 'Revisar',
        _ => 'Pendiente',
      };

  String get methodLabel => switch (paymentMethod) {
        'NEQUI' => 'Nequi',
        'PSE' => 'PSE',
        'CARD' => 'Tarjeta',
        'BANCOLOMBIA_TRANSFER' => 'Bancolombia',
        'BANCOLOMBIA_QR' => 'QR Bancolombia',
        null || '' => '—',
        final other => other,
      };
}

/// Un plan con su precio, para editarlo
class AdminPlan {
  final String id;
  final String kind;
  final String period;
  final String currency;
  final double price;
  final double? regularPrice;
  final String? label;
  final bool active;

  const AdminPlan({
    required this.id,
    required this.kind,
    required this.period,
    required this.currency,
    required this.price,
    this.regularPrice,
    this.label,
    this.active = true,
  });

  factory AdminPlan.fromJson(Map<String, dynamic> j) => AdminPlan(
        id: j['id'] as String,
        kind: j['kind'] as String,
        period: j['period'] as String,
        currency: j['currency'] as String,
        price: (j['price'] as num).toDouble(),
        regularPrice: (j['regular_price'] as num?)?.toDouble(),
        label: j['label'] as String?,
        active: j['active'] != false,
      );

  String get name =>
      '${kind == 'global' ? 'Pro Global' : 'Pro Negocio'} · ${switch (period) {
        'week' => 'Semanal',
        'month' => 'Mensual',
      'year' => 'Anual',
        _ => 'Permanente',
      }}';
}

/// Datos de pago y precios de Pro
class AdminConfig {
  final Map<String, String?> settings;
  final List<AdminPlan> plans;

  const AdminConfig({required this.settings, required this.plans});

  factory AdminConfig.fromJson(Map<String, dynamic> j) => AdminConfig(
        settings: {
          for (final e in Map<String, dynamic>.from(j['settings'] as Map? ?? const {}).entries) e.key: e.value as String?,
        },
        plans: [for (final p in (j['plans'] as List? ?? const [])) AdminPlan.fromJson(Map<String, dynamic>.from(p as Map))],
      );

  /// Faltan los datos para que los clientes puedan pagar
  bool get missingPaymentData =>
      [settings['nequi_number'], settings['nequi_name'], settings['whatsapp']].any((v) => v == null || v.trim().isEmpty);
}

/// Administración de Stockealo (solo cuentas de app_admins). El servidor
/// comprueba el permiso en cada llamada.
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

  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) async {
    final client = _client;
    if (client == null) throw const ProAdminException('Necesitas conexión a internet.');
    try {
      return await client.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      throw ProAdminException(errorMessage(e.message));
    }
  }

  List<Map<String, dynamic>> _rows(dynamic data) => [for (final r in data as List) Map<String, dynamic>.from(r as Map)];

  // --- Resumen, usuarios, negocios y tiendas ---------------------------------

  Future<AdminSummary> summary() async =>
      AdminSummary.fromJson(Map<String, dynamic>.from(await _rpc('admin_summary') as Map));

  Future<List<AdminUser>> listUsers({String? search}) async =>
      _rows(await _rpc('admin_list_users', {'p_search': search, 'p_limit': 200})).map(AdminUser.fromRow).toList();

  Future<List<AdminBusiness>> findBusinesses(String search) async =>
      _rows(await _rpc('admin_find_businesses', {'p_search': search})).map(AdminBusiness.fromRow).toList();

  // --- Rol, equipo y registro -------------------------------------------------

  /// Rol de quien usa el panel: 'OWNER', 'SUPPORT' o 'VIEWER'. Se guarda para que
  /// las pantallas oculten lo que no puede hacer (el servidor igual lo impide).
  final role = ValueNotifier<String>('VIEWER');
  bool get isOwner => role.value == 'OWNER';
  bool get canSupport => role.value == 'OWNER' || role.value == 'SUPPORT';

  Future<void> loadMe() async {
    try {
      final me = Map<String, dynamic>.from(await _rpc('admin_me') as Map);
      role.value = me['role'] as String? ?? 'VIEWER';
    } catch (_) {
      // Servidor sin roles todavía: los administradores de antes son dueños
      role.value = 'OWNER';
    }
  }

  Future<List<Map<String, dynamic>>> listAdmins() async => _maps(await _rpc('admin_list_admins'));
  Future<void> setAdmin(String email, String? role) => _rpc('admin_set_admin', {'p_email': email, 'p_role': role});
  Future<List<Map<String, dynamic>>> listActions({int limit = 100}) async =>
      _maps(await _rpc('admin_list_actions', {'p_limit': limit}));

  // --- Notas y contactos ------------------------------------------------------

  Future<Map<String, dynamic>> notes(String email) async =>
      Map<String, dynamic>.from(await _rpc('admin_list_notes', {'p_email': email}) as Map);
  Future<void> addNote(String email, String note) => _rpc('admin_add_note', {'p_email': email, 'p_note': note});
  Future<void> deleteNote(int id) => _rpc('admin_delete_note', {'p_id': id});
  Future<void> setContacted(String email, bool contacted) =>
      _rpc('admin_set_contacted', {'p_email': email, 'p_contacted': contacted});

  /// correo → {at, by}
  Future<Map<String, Map<String, dynamic>>> contacts() async {
    final data = Map<String, dynamic>.from(await _rpc('admin_list_contacts') as Map);
    return {for (final e in data.entries) e.key: Map<String, dynamic>.from(e.value as Map)};
  }

  // --- Búsqueda, embudo, IA y versiones --------------------------------------

  Future<Map<String, dynamic>> search(String query) async =>
      Map<String, dynamic>.from(await _rpc('admin_search', {'p_query': query}) as Map);
  Future<Map<String, dynamic>> funnel() async => Map<String, dynamic>.from(await _rpc('admin_funnel') as Map);
  Future<Map<String, dynamic>> aiUsage() async => Map<String, dynamic>.from(await _rpc('admin_ai_usage') as Map);
  Future<List<Map<String, dynamic>>> appVersions() async => _maps(await _rpc('admin_app_versions'));

  // --- Mantenimiento ----------------------------------------------------------

  Future<Map<String, dynamic>> getMaintenance() async =>
      Map<String, dynamic>.from(await _rpc('admin_get_maintenance') as Map);
  Future<void> setMaintenance({
    required int level,
    required List<String> scopes,
    required DateTime startsAt,
    required DateTime endsAt,
    String? message,
    int noticeHours = 2,
    String? confirm,
  }) =>
      _rpc('admin_set_maintenance', {
        'p_level': level,
        'p_scopes': scopes,
        'p_message': message,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt.toUtc().toIso8601String(),
        'p_notice_hours': noticeHours,
        'p_confirm': confirm,
      });
  Future<void> endMaintenance() => _rpc('admin_end_maintenance');

  /// Ficha de soporte de una cuenta: cuenta, negocios, Pro, códigos y pagos.
  /// Nunca productos, ventas ni clientes.
  Future<AdminUserDetail> userDetail(String email) async =>
      AdminUserDetail.fromJson(Map<String, dynamic>.from(await _rpc('admin_user_detail', {'p_email': email}) as Map));

  /// A quién conviene escribirle hoy
  Future<AdminHealth> health() async => AdminHealth.fromJson(Map<String, dynamic>.from(await _rpc('admin_health') as Map));

  Future<List<AdminStore>> listStores() async => _rows(await _rpc('admin_list_stores')).map(AdminStore.fromRow).toList();

  // --- Suscripciones ---------------------------------------------------------

  Future<List<AdminSubscription>> listSubscriptions({bool onlyActive = true}) async =>
      _rows(await _rpc('admin_list_subscriptions', {'p_only_active': onlyActive}))
          .map(AdminSubscription.fromRow)
          .toList();

  /// Pro Negocio a mano; [days] null = permanente
  Future<void> grantPro(String businessId, int? days) =>
      _rpc('admin_grant_pro', {'p_business_id': businessId, 'p_days': days});

  Future<void> endSubscription(String id) => _rpc('admin_end_subscription', {'p_id': id});

  // --- Códigos ---------------------------------------------------------------

  /// Crea [count] códigos; [days] null = permanentes; [validDays] = días para canjearlos
  Future<List<String>> createCodes({
    required String kind,
    required int? days,
    int count = 1,
    int maxUses = 1,
    String? note,
    int? validDays,
  }) async {
    final data = await _rpc('admin_create_pro_codes', {
      'p_kind': kind,
      'p_days': days,
      'p_count': count,
      'p_note': note,
      'p_max_uses': maxUses,
      'p_valid_days': validDays,
    });
    return [for (final c in data as List) c as String];
  }

  Future<List<ProCode>> listCodes({int limit = 100, String? search}) async =>
      _rows(await _rpc('admin_list_pro_codes', {'p_limit': limit, 'p_search': search})).map(ProCode.fromRow).toList();

  Future<void> disableCode(String code) => _rpc('admin_disable_code', {'p_code': code});

  // --- Pagos -----------------------------------------------------------------

  Future<List<AdminPayment>> listPayments() async =>
      _rows(await _rpc('admin_list_payments', {'p_limit': 200})).map(AdminPayment.fromRow).toList();

  // --- Configuración ---------------------------------------------------------

  Future<AdminConfig> config() async =>
      AdminConfig.fromJson(Map<String, dynamic>.from(await _rpc('admin_get_config') as Map));

  Future<void> setSetting(String key, String? value) => _rpc('admin_set_setting', {'p_key': key, 'p_value': value});

  Future<void> setPlan(AdminPlan plan, {required double price, double? regularPrice, String? label, required bool active}) =>
      _rpc('admin_set_plan', {
        'p_id': plan.id,
        'p_price': price,
        'p_regular_price': regularPrice,
        'p_label': label,
        'p_active': active,
      });

  @visibleForTesting
  static String errorMessage(String serverMessage) {
    if (serverMessage.contains('admin_only')) return 'Esta cuenta no es administradora.';
    if (serverMessage.contains('user_not_found')) return 'Esa cuenta ya no existe.';
    if (serverMessage.contains('admin_role_forbidden')) return 'Tu rol en el panel no permite hacer esto.';
    if (serverMessage.contains('cannot_demote_self')) return 'No puedes quitarte a ti mismo el rol de dueño.';
    if (serverMessage.contains('last_owner')) return 'El panel debe tener al menos un dueño.';
    if (serverMessage.contains('invalid_email')) return 'Escribe un correo válido.';
    if (serverMessage.contains('invalid_role')) return 'Elige un rol válido.';
    if (serverMessage.contains('empty_note')) return 'Escribe la nota.';
    if (serverMessage.contains('invalid_level')) return 'Elige el nivel del mantenimiento.';
    if (serverMessage.contains('invalid_scopes')) return 'Elige qué partes entran en mantenimiento.';
    if (serverMessage.contains('invalid_end')) return 'La hora de fin debe ser después del inicio y en el futuro.';
    if (serverMessage.contains('too_long')) return 'El mantenimiento puede durar máximo 48 horas.';
    if (serverMessage.contains('confirm_required')) return 'Para el cierre total escribe MANTENIMIENTO.';
    if (RegExp(r'admin_(user_detail|health|me|search|funnel|ai_usage|app_versions|list_notes|list_contacts|'
            r'get_maintenance|list_admins|list_actions)')
        .hasMatch(serverMessage)) {
      return 'Falta actualizar el servidor para esta función.';
    }
    if (serverMessage.contains('invalid_count')) return 'Puedes crear de 1 a 50 códigos por vez.';
    if (serverMessage.contains('invalid_valid_days')) return 'El plazo para canjear debe ser de 1 a 3650 días.';
    if (serverMessage.contains('invalid_days')) return 'La duración debe ser de 1 a 3650 días.';
    if (serverMessage.contains('invalid_max_uses')) return 'Los usos por código deben ser de 1 a 1000.';
    if (serverMessage.contains('invalid_kind')) return 'Elige Pro Negocio o Pro Global.';
    if (serverMessage.contains('business_not_found')) return 'Ese negocio no existe o fue eliminado.';
    if (serverMessage.contains('invalid_price')) return 'Revisa el precio.';
    if (serverMessage.contains('invalid_setting')) return 'Ese ajuste no se puede cambiar desde aquí.';
    return 'No se pudo completar. Inténtalo de nuevo.';
  }
}

class ProAdminException implements Exception {
  final String message;

  const ProAdminException(this.message);

  @override
  String toString() => message;
}

List<Map<String, dynamic>> _maps(Object? v) => [for (final r in (v as List? ?? const [])) Map<String, dynamic>.from(r as Map)];

/// "+57 311 769 7927" o "3117697927" → "573117697927" para wa.me; null si no sirve
String? whatsappDigits(String? phone) {
  final d = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.length < 10) return null;
  return d.length == 10 ? '57$d' : d;
}

/// Ficha de soporte de una cuenta
class AdminUserDetail {
  final String email;
  final String? name;
  final String? phone;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final DateTime? emailConfirmedAt;
  final String provider;
  final List<AdminUserBusiness> businesses;
  final List<Map<String, dynamic>> redemptions;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> subscriptions;

  const AdminUserDetail({
    required this.email,
    this.name,
    this.phone,
    this.createdAt,
    this.lastSignInAt,
    this.emailConfirmedAt,
    this.provider = 'email',
    this.businesses = const [],
    this.redemptions = const [],
    this.payments = const [],
    this.subscriptions = const [],
  });

  String get providerLabel => switch (provider) {
        'google' => 'Google',
        'apple' => 'Apple',
        'facebook' => 'Facebook',
        _ => 'Correo',
      };

  factory AdminUserDetail.fromJson(Map<String, dynamic> j) {
    final a = Map<String, dynamic>.from(j['account'] as Map);
    return AdminUserDetail(
      email: a['email'] as String? ?? '',
      name: a['name'] as String?,
      phone: a['phone'] as String?,
      createdAt: _date(a['created_at']),
      lastSignInAt: _date(a['last_sign_in_at']),
      emailConfirmedAt: _date(a['email_confirmed_at']),
      provider: a['provider'] as String? ?? 'email',
      businesses: [for (final b in _maps(j['businesses'])) AdminUserBusiness.fromJson(b)],
      redemptions: _maps(j['redemptions']),
      payments: _maps(j['payments']),
      subscriptions: _maps(j['subscriptions']),
    );
  }
}

/// Un negocio de la cuenta, visto desde el panel
class AdminUserBusiness {
  final String id;
  final String name;
  final String role;
  final String? country;
  final bool pro;
  final DateTime? proUntil;
  final String? storeSlug;
  final bool storeEnabled;

  const AdminUserBusiness({
    required this.id,
    required this.name,
    required this.role,
    this.country,
    this.pro = false,
    this.proUntil,
    this.storeSlug,
    this.storeEnabled = false,
  });

  String get roleLabel => switch (role) {
        'OWNER' => 'Dueño',
        'ADMIN' => 'Administrador',
        _ => 'Cajero',
      };

  factory AdminUserBusiness.fromJson(Map<String, dynamic> j) {
    final pro = j['pro'] is Map ? Map<String, dynamic>.from(j['pro'] as Map) : const <String, dynamic>{};
    return AdminUserBusiness(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      role: j['role'] as String? ?? 'CASHIER',
      country: j['country'] as String?,
      pro: pro['active'] == true,
      proUntil: _date(pro['ends_at']),
      storeSlug: j['store_slug'] as String?,
      storeEnabled: j['store_enabled'] == true,
    );
  }
}

/// Salud de Stockealo: a quién conviene escribirle hoy
class AdminHealth {
  final List<Map<String, dynamic>> noCloud;
  final List<Map<String, dynamic>> expiring;
  final List<Map<String, dynamic>> failedPayments;
  final int inactive30d;
  final int dbBytes;
  final int dbLimitBytes;
  final int storageBytes;
  final int storageObjects;
  final int storageLimitBytes;

  const AdminHealth({
    this.noCloud = const [],
    this.expiring = const [],
    this.failedPayments = const [],
    this.inactive30d = 0,
    this.dbBytes = 0,
    this.dbLimitBytes = 0,
    this.storageBytes = 0,
    this.storageObjects = 0,
    this.storageLimitBytes = 0,
  });

  double get dbUse => dbLimitBytes == 0 ? 0 : dbBytes / dbLimitBytes;
  double get storageUse => storageLimitBytes == 0 ? 0 : storageBytes / storageLimitBytes;

  /// "14,2 MB", "2,5 MB", "1 GB"
  static String bytesLabel(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }

  bool get allGood => noCloud.isEmpty && expiring.isEmpty && failedPayments.isEmpty;

  factory AdminHealth.fromJson(Map<String, dynamic> j) => AdminHealth(
        noCloud: _maps(j['no_cloud']),
        expiring: _maps(j['expiring']),
        failedPayments: _maps(j['failed_payments']),
        inactive30d: (j['inactive_30d'] as num?)?.toInt() ?? 0,
        dbBytes: _int((j['usage'] as Map?)?['db_bytes']),
        dbLimitBytes: _int((j['usage'] as Map?)?['db_limit_bytes']),
        storageBytes: _int((j['usage'] as Map?)?['storage_bytes']),
        storageObjects: _int((j['usage'] as Map?)?['storage_objects']),
        storageLimitBytes: _int((j['usage'] as Map?)?['storage_limit_bytes']),
      );
}
