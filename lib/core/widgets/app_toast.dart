import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ToastType { success, error, warning, info, permission }

/// Notificaciones y alertas dinámicas y estilizadas para Stockealo
class AppToast {
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}

    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color borderColor;
    Color iconColor;
    IconData icon;
    String defaultTitle;

    switch (type) {
      case ToastType.success:
        bg = isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5);
        borderColor = const Color(0xFF059669);
        iconColor = const Color(0xFF059669);
        icon = Icons.check_circle_rounded;
        defaultTitle = '¡Acción Exitosa!';
        break;
      case ToastType.error:
        bg = isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFDC2626);
        iconColor = const Color(0xFFDC2626);
        icon = Icons.error_rounded;
        defaultTitle = 'Ha ocurrido un error';
        break;
      case ToastType.warning:
        bg = isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB);
        borderColor = const Color(0xFFD97706);
        iconColor = const Color(0xFFD97706);
        icon = Icons.warning_amber_rounded;
        defaultTitle = 'Atención';
        break;
      case ToastType.permission:
        bg = isDark ? const Color(0xFF311042) : const Color(0xFFFAF5FF);
        borderColor = const Color(0xFF9333EA);
        iconColor = const Color(0xFF9333EA);
        icon = Icons.shield_outlined;
        defaultTitle = 'Permisos Insuficientes';
        break;
      case ToastType.info:
        bg = isDark ? const Color(0xFF0C2A4D) : const Color(0xFFEFF6FF);
        borderColor = const Color(0xFF2563EB);
        iconColor = const Color(0xFF2563EB);
        icon = Icons.info_rounded;
        defaultTitle = 'Información';
        break;
    }

    try {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();

      messenger.showSnackBar(
        SnackBar(
          elevation: 6,
          backgroundColor: Colors.transparent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          padding: EdgeInsets.zero,
          duration: duration,
          dismissDirection: DismissDirection.horizontal,
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: borderColor.withOpacity(0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ?? defaultTitle,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {}
  }

  /// Mensaje dinámico de éxito
  static void showSuccess(BuildContext context, String message, {String? title}) =>
      show(context, message: message, title: title, type: ToastType.success);

  /// Mensaje dinámico de error
  static void showError(BuildContext context, String message, {String? title}) =>
      show(context, message: message, title: title, type: ToastType.error);

  /// Mensaje dinámico de advertencia
  static void showWarning(BuildContext context, String message, {String? title}) =>
      show(context, message: message, title: title, type: ToastType.warning);

  /// Mensaje dinámico de permiso denegado o rol restringido
  static void showPermission(BuildContext context, String message, {String? title}) =>
      show(context, message: message, title: title, type: ToastType.permission);

  /// Mensaje dinámico informativo
  static void showInfo(BuildContext context, String message, {String? title}) =>
      show(context, message: message, title: title, type: ToastType.info);
}
