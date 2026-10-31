import '../../../../core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/widgets/stocky_empty_state.dart';

class NotificationsModal extends StatelessWidget {
  final Function(int tabIndex)? onNavigateToTab;

  const NotificationsModal({super.key, this.onNavigateToTab});

  static Future<void> show({
    required BuildContext context,
    Function(int tabIndex)? onNavigateToTab,
  }) {
    return showModalBottomSheet(
      showDragHandle: false,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NotificationsModal(onNavigateToTab: onNavigateToTab),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Hace un momento';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    return DateFormat('dd/MM • hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final service = NotificationService.instance;

    final bgColor = context.colors.surface;
    final cardBg = context.colors.surfaceMuted;
    final borderColor = context.colors.line;
    final textMain = context.colors.ink;
    final textMuted = context.colors.inkMuted;

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final notifications = service.notifications;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Barra de arrastre
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: context.colors.lineStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Cabecera
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: context.colors.accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.notifications_active_rounded, color: context.colors.accent, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Centro de Notificaciones',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textMain),
                            ),
                            Text(
                              '${service.unreadCount} sin leer',
                              style: TextStyle(fontSize: 11, color: textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (notifications.isNotEmpty)
                      TextButton.icon(
                        onPressed: service.unreadCount > 0 ? service.markAllAsRead : null,
                        icon: const Icon(Icons.done_all_rounded, size: 16),
                        label: const Text('Leídas', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: context.colors.accent,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // Lista de Notificaciones o Empty State con Stocky
                if (notifications.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: StockyEmptyState(
                      title: 'Todo en calma por aquí',
                      message: 'Te notificaremos aquí al instante cuando un cajero registre una venta o haya alertas de inventario.',
                      mascotSize: 72,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final notif = notifications[index];
                        return _buildNotificationTile(
                          context,
                          notif: notif,
                          isDark: isDark,
                          cardBg: cardBg,
                          borderColor: borderColor,
                          textMain: textMain,
                          textMuted: textMuted,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotificationTile(
    BuildContext context, {
    required AppNotification notif,
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color textMain,
    required Color textMuted,
  }) {
    Color iconColor;
    IconData icon;

    switch (notif.type) {
      case NotificationType.sale:
        iconColor = context.colors.accent;
        icon = Icons.shopping_bag_rounded;
        break;
      case NotificationType.stockAlert:
        iconColor = context.colors.warning;
        icon = Icons.warning_amber_rounded;
        break;
      case NotificationType.team:
        iconColor = const Color(0xFF38BDF8);
        icon = Icons.group_rounded;
        break;
      case NotificationType.system:
      default:
        iconColor = context.colors.accent;
        icon = Icons.auto_awesome_rounded;
    }

    return InkWell(
      onTap: () {
        NotificationService.instance.markAsRead(notif.id);
        Navigator.pop(context);

        // Si es una venta, navegar al Historial de Ventas (pestaña 2)
        if (notif.type == NotificationType.sale) {
          onNavigateToTab?.call(2);
        } else if (notif.type == NotificationType.stockAlert) {
          onNavigateToTab?.call(1);
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: notif.isRead ? cardBg : (isDark ? const Color(0xFF221B42) : const Color(0xFFF3E8FF)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: notif.isRead ? borderColor : context.colors.accent.withOpacity(0.4),
            width: notif.isRead ? 1 : 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          notif.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: notif.isRead ? FontWeight.w600 : FontWeight.bold,
                            color: textMain,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTimeAgo(notif.timestamp),
                        style: TextStyle(fontSize: 10, color: textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notif.message,
                    style: TextStyle(
                      fontSize: 12,
                      color: notif.isRead ? textMuted : (context.colors.ink),
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            if (!notif.isRead) ...[
              const SizedBox(width: 8),
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: context.colors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
