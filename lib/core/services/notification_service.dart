import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'supabase_service.dart';

enum NotificationType {
  sale,
  stockAlert,
  team,
  system,
}

class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final NotificationType type;
  bool isRead;
  final Map<String, dynamic>? data;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.type,
    this.isRead = false,
    this.data,
  });
}

class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final List<AppNotification> _notifications = [];
  RealtimeChannel? _salesChannel;
  String? _subscribedBusinessId;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Añade una notificación local con respuesta háptica
  void addNotification({
    required String title,
    required String message,
    required NotificationType type,
    Map<String, dynamic>? data,
  }) {
    final notification = AppNotification(
      id: const Uuid().v4(),
      title: title,
      message: message,
      timestamp: DateTime.now(),
      type: type,
      data: data,
    );

    _notifications.insert(0, notification);
    if (_notifications.length > 50) {
      _notifications.removeLast();
    }

    // Vibración sutil si la plataforma lo soporta
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}

    notifyListeners();
  }

  /// Marca todas las notificaciones como leídas
  void markAllAsRead() {
    for (final n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  /// Marca una notificación específica como leída
  void markAsRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1) {
      _notifications[index].isRead = true;
      notifyListeners();
    }
  }

  /// Limpia todas las notificaciones
  void clearAll() {
    _notifications.clear();
    notifyListeners();
  }

  /// Inicia la escucha en tiempo real de nuevas ventas desde Supabase Realtime
  void startRealtimeSalesListening({
    required String businessId,
    required String currentUserId,
  }) {
    if (_subscribedBusinessId == businessId && _salesChannel != null) {
      return;
    }

    stopRealtimeSalesListening();

    final client = SupabaseService.instance.client;
    if (client == null) return;

    _subscribedBusinessId = businessId;

    try {
      _salesChannel = client.channel('realtime:business_sales:$businessId')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sales',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'business_id',
            value: businessId,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            final createdBy = newRecord['created_by'] as String?;

            // Evitar auto-notificarse si la venta la hizo el mismo usuario
            if (createdBy == currentUserId) return;

            final productName = newRecord['product_name'] ?? 'Producto';
            final qty = newRecord['quantity'] ?? 1;
            final total = newRecord['total_amount'] ?? 0;
            final method = newRecord['payment_method'] ?? 'EFECTIVO';

            addNotification(
              title: 'Nueva Venta en Tiempo Real 🚀',
              message: '$productName x$qty ($total) cobrado por $method.',
              type: NotificationType.sale,
              data: newRecord,
            );
          },
        )
        ..subscribe();

      debugPrint('Realtime: Escuchando ventas para empresa $businessId');
    } catch (e) {
      debugPrint('Error iniciando Realtime Sales: $e');
    }
  }

  /// Detiene la escucha de ventas en tiempo real
  void stopRealtimeSalesListening() {
    if (_salesChannel != null) {
      final client = SupabaseService.instance.client;
      if (client != null) {
        client.removeChannel(_salesChannel!);
      }
      _salesChannel = null;
      _subscribedBusinessId = null;
    }
  }
}
