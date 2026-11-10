import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/app_version.dart';
import '../../../core/services/supabase_service.dart';

/// Un mensaje de Ajustes › Ayuda › Sugerencias y fallos
class AppFeedback {
  static const kinds = <String, String>{
    'FALLO': 'Algo no funciona',
    'IDEA': 'Tengo una idea',
    'PREGUNTA': 'Tengo una pregunta',
  };
  static const statuses = <String, String>{
    'NUEVO': 'Recibido',
    'REVISION': 'En revisión',
    'RESUELTO': 'Resuelto',
    'DESCARTADO': 'Descartado',
  };
  static const areas = ['Inicio', 'Inventario', 'Ventas', 'Servicios', 'Reportes', 'Ajustes', 'Otra'];

  final String id;
  final String userEmail;
  final String? businessName;
  final String? userRole;
  final String kind;
  final String? area;
  final String message;
  final String? contactPhone;
  final String? appVersion;
  final String? platform;
  final String status;
  final String? adminReply;
  final DateTime? repliedAt;
  final DateTime createdAt;

  const AppFeedback({
    required this.id,
    required this.userEmail,
    this.businessName,
    this.userRole,
    required this.kind,
    this.area,
    required this.message,
    this.contactPhone,
    this.appVersion,
    this.platform,
    required this.status,
    this.adminReply,
    this.repliedAt,
    required this.createdAt,
  });

  String get kindLabel => kinds[kind] ?? kind;
  String get statusLabel => statuses[status] ?? status;

  factory AppFeedback.fromRow(Map<String, dynamic> r) => AppFeedback(
        id: '${r['id']}',
        userEmail: r['user_email'] as String? ?? '',
        businessName: r['business_name'] as String?,
        userRole: r['user_role'] as String?,
        kind: r['kind'] as String? ?? 'IDEA',
        area: r['area'] as String?,
        message: r['message'] as String? ?? '',
        contactPhone: r['contact_phone'] as String?,
        appVersion: r['app_version'] as String?,
        platform: r['platform'] as String?,
        status: r['status'] as String? ?? 'NUEVO',
        adminReply: r['admin_reply'] as String?,
        repliedAt: DateTime.tryParse('${r['replied_at']}')?.toLocal(),
        createdAt: DateTime.tryParse('${r['created_at']}')?.toLocal() ?? DateTime.now(),
      );
}

/// Envía y lee sugerencias y fallos. Todo pasa por funciones del servidor.
class FeedbackService {
  FeedbackService._();
  static final instance = FeedbackService._();

  SupabaseClient? get _client {
    final c = SupabaseService.instance.client;
    return c?.auth.currentSession == null ? null : c;
  }

  static String get platform => kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

  /// Mensaje claro para cada error del servidor
  static String errorMessage(Object e) {
    final s = '$e';
    if (s.contains('too_many_feedback')) return 'Ya enviaste 10 mensajes hoy. Inténtalo mañana.';
    if (s.contains('message_too_short')) return 'Cuéntanos un poco más (al menos 3 letras).';
    if (s.contains('message_too_long')) return 'El mensaje es muy largo: máximo 2000 letras.';
    if (s.contains('not_authenticated')) return 'Inicia sesión para enviar tu mensaje.';
    if (s.contains('admin_only') || s.contains('admin_role_forbidden')) return 'Solo los administradores pueden hacer esto.';
    return 'No se pudo enviar. Revisa tu conexión e inténtalo de nuevo.';
  }

  Future<void> submit({
    required String kind,
    required String message,
    String? area,
    String? businessId,
    String? contactPhone,
  }) async {
    final client = _client;
    if (client == null) throw Exception('Necesitas conexión a internet para enviar tu mensaje.');
    try {
      await client.rpc('submit_feedback', params: {
        'p_kind': kind,
        'p_message': message.trim(),
        'p_area': area,
        'p_business_id': businessId,
        'p_contact_phone': (contactPhone ?? '').trim().isEmpty ? null : contactPhone!.trim(),
        'p_app_version': '$kAppVersion+$kAppBuildNumber',
        'p_platform': platform,
      });
    } catch (e) {
      throw Exception(errorMessage(e));
    }
  }

  /// Lo que envió esta cuenta, lo más nuevo primero
  Future<List<AppFeedback>> mine() async {
    final client = _client;
    if (client == null) return const [];
    final rows = await client.from('app_feedback').select().order('created_at', ascending: false).limit(50);
    return [for (final r in rows) AppFeedback.fromRow(Map<String, dynamic>.from(r))];
  }

  // --- Panel admin -----------------------------------------------------------

  Future<List<AppFeedback>> adminList({String? status, String? kind}) async {
    final client = _client;
    if (client == null) return const [];
    final rows = await client.rpc('admin_list_feedback', params: {'p_status': status, 'p_kind': kind, 'p_limit': 200});
    return [for (final r in rows as List) AppFeedback.fromRow(Map<String, dynamic>.from(r as Map))];
  }

  Future<void> adminUpdate(String id, {required String status, String? reply}) async {
    final client = _client;
    if (client == null) throw Exception('Sin conexión.');
    try {
      await client.rpc('admin_update_feedback', params: {'p_id': id, 'p_status': status, 'p_reply': reply});
    } catch (e) {
      throw Exception(errorMessage(e));
    }
  }
}
