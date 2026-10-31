import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';

enum ToastType { success, error, warning, info, permission }

/// Avisos de Stockealo (V1): una barra oscura y discreta que flota sobre el contenido,
/// con un ícono según el tipo y sin emojis. Reemplaza al SnackBar estándar de Flutter.
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

    final c = context.colors;
    final (IconData icon, Color iconColor) = switch (type) {
      ToastType.success => (Icons.check_circle_rounded, AppPalette.successDark),
      ToastType.error => (Icons.error_rounded, AppPalette.dangerDark),
      ToastType.warning => (Icons.warning_amber_rounded, AppPalette.warningDark),
      ToastType.permission => (Icons.lock_outline_rounded, AppPalette.warningDark),
      ToastType.info => (Icons.info_outline_rounded, AppPalette.infoDark),
    };

    try {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          elevation: 0,
          backgroundColor: c.toast,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
          duration: duration,
          dismissDirection: DismissDirection.horizontal,
          content: Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: AppText.fontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: c.onToast,
                        ),
                      ),
                    Text(
                      message,
                      style: TextStyle(
                        fontFamily: AppText.fontFamily,
                        fontSize: 13.5,
                        height: 1.3,
                        color: title == null ? c.onToast : c.onToast.withOpacity(0.78),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {}
  }

  /// Aviso de éxito
  static void showSuccess(BuildContext context, String message, {String? title}) =>
      show(context, message: message, title: title, type: ToastType.success);

  /// Aviso de error
  static void showError(BuildContext context, String message, {String? title}) =>
      show(context, message: message, title: title, type: ToastType.error);

  /// Aviso de advertencia
  static void showWarning(BuildContext context, String message, {String? title}) =>
      show(context, message: message, title: title, type: ToastType.warning);

  /// Aviso de permiso denegado o rol restringido
  static void showPermission(BuildContext context, String message, {String? title}) =>
      show(context, message: message, title: title, type: ToastType.permission);

  /// Aviso informativo
  static void showInfo(BuildContext context, String message, {String? title}) =>
      show(context, message: message, title: title, type: ToastType.info);
}
