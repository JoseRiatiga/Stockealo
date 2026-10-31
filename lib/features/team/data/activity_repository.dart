import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/data/auth_repository.dart';

/// Tipos de acción del registro. El texto de cada anotación ya viene redactado;
/// el tipo sirve para filtrar y para el ícono.
abstract final class ActivityAction {
  static const sale = 'sale';
  static const saleCancel = 'sale_cancel';
  static const productCreate = 'product_create';
  static const productUpdate = 'product_update';
  static const priceChange = 'price_change';
  static const productDelete = 'product_delete';
  static const stockAdjust = 'stock_adjust';
  static const shrinkage = 'shrinkage';
  static const debtPayment = 'debt_payment';
  static const customerDelete = 'customer_delete';
  static const cashOpen = 'cash_open';
  static const cashClose = 'cash_close';
  static const memberJoin = 'member_join';
  static const memberAdd = 'member_add';
  static const memberRemove = 'member_remove';
  static const roleChange = 'role_change';
}

/// Forma de pago en palabras, para las frases del registro
String activityPaymentLabel(String method) => switch (method.toUpperCase()) {
      'EFECTIVO' => 'efectivo',
      'TRANSFERENCIA' => 'transferencia',
      'FIADO' => 'fiado',
      'TARJETA' => 'tarjeta',
      _ => method.toLowerCase(),
    };

/// Una anotación del registro de actividad
class ActivityEntry {
  final String id;
  final String businessId;
  final String actorEmail;
  final String? actorName;
  final String action;
  final String summary;
  final Map<String, dynamic>? data;
  final DateTime createdAt;

  /// Todavía no subió a la nube (solo está en este celular)
  final bool pending;

  const ActivityEntry({
    required this.id,
    required this.businessId,
    required this.actorEmail,
    required this.actorName,
    required this.action,
    required this.summary,
    required this.createdAt,
    this.data,
    this.pending = false,
  });

  /// Nombre para mostrar: el guardado o la parte del correo antes de la @
  String get actor {
    final name = actorName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return actorEmail.split('@').first;
  }

  factory ActivityEntry.fromRow(Map<String, dynamic> row, {bool pending = false}) {
    final raw = row['data'];
    Map<String, dynamic>? data;
    if (raw is Map) {
      data = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.isNotEmpty) {
      try {
        data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    return ActivityEntry(
      id: row['id'] as String,
      businessId: row['business_id'] as String,
      actorEmail: (row['actor_email'] as String?) ?? '',
      actorName: row['actor_name'] as String?,
      action: row['action'] as String,
      summary: row['summary'] as String,
      data: data,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      pending: pending,
    );
  }
}

/// Registro de actividad del equipo: quién vendió, cambió precios, ajustó stock…
///
/// Cada anotación se guarda en el celular y se sube a la nube con la cola de
/// sincronización; la nube no deja editarla ni borrarla. Anotar nunca debe estorbar
/// la acción principal, por eso [log] no lanza errores.
class ActivityRepository {
  ActivityRepository._();
  static final ActivityRepository instance = ActivityRepository._();

  Future<void> log({
    required String businessId,
    required String action,
    required String summary,
    Map<String, dynamic>? data,
  }) async {
    try {
      final user = AuthRepository.instance.currentUser;
      if (user == null) return;
      final row = <String, dynamic>{
        'id': const Uuid().v4(),
        'business_id': businessId,
        'actor_email': user.email.toLowerCase(),
        'actor_name': user.displayName.isNotEmpty ? user.displayName : null,
        'action': action,
        // La nube limita el texto a 300 caracteres
        'summary': summary.length > 300 ? '${summary.substring(0, 297)}...' : summary,
        'data': data,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      final db = await AppDatabase.instance.database;
      await db.insert('activity_log', {...row, 'data': data == null ? null : jsonEncode(data)});
      // Sin esperar: la venta o el cambio no deben demorarse por la nube
      SupabaseService.instance.insertActivityToCloud(row);
    } catch (e) {
      debugPrint('Registro de actividad: $e');
    }
  }

  /// Actividad del negocio, la más reciente primero. Con la nube activa trae la de todo
  /// el equipo y le suma lo de este celular que aún no ha subido.
  Future<List<ActivityEntry>> list(String businessId, {int limit = 300}) async {
    final db = await AppDatabase.instance.database;
    final localRows = await db.query(
      'activity_log',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'created_at DESC',
      limit: limit,
    );

    List<ActivityEntry> cloud = const [];
    try {
      final client = SupabaseService.instance.client;
      if (client != null && client.auth.currentSession != null && await SupabaseService.instance.isCloudSyncEnabled()) {
        final rows = await client
            .from('business_activity')
            .select()
            .eq('business_id', businessId)
            .order('created_at', ascending: false)
            .limit(limit);
        cloud = [for (final r in rows) ActivityEntry.fromRow(r)];
      }
    } catch (e) {
      debugPrint('Actividad en la nube no disponible: $e');
    }

    final cloudIds = {for (final e in cloud) e.id};
    final merged = [
      ...cloud,
      for (final r in localRows)
        if (!cloudIds.contains(r['id'])) ActivityEntry.fromRow(r, pending: cloud.isNotEmpty),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged.take(limit).toList();
  }
}
