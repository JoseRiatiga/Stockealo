import 'package:flutter/material.dart';

import '../../../core/design/app_dialog.dart';
import '../../../core/services/sync_queue.dart';

/// «¿Cerrar sesión?» (0.16.1): se pregunta antes de salir, desde cualquier lugar, para
/// que nadie cierre la sesión por accidente. Si hay cambios sin subir a la nube, lo dice:
/// quedan guardados en este equipo y suben cuando vuelva a entrar con la misma cuenta.
abstract final class LogoutConfirm {
  static Future<bool> ask(BuildContext context, {Future<int> Function()? pending}) async {
    var waiting = 0;
    try {
      waiting = await (pending ?? SyncQueue.instance.pendingCount)();
    } catch (_) {}
    if (!context.mounted) return false;
    return AppDialog.confirm(
      context: context,
      title: '¿Cerrar sesión?',
      message: message(waiting),
      icon: Icons.logout_outlined,
      confirmText: 'Cerrar sesión',
      destructive: true,
    );
  }

  /// El texto del aviso según los cambios que esperan subir a la nube
  static String message(int waiting) => waiting <= 0
      ? 'Para volver a entrar necesitas tu correo y tu contraseña, o tu cuenta de Google.'
      : 'Tienes $waiting ${waiting == 1 ? 'cambio' : 'cambios'} sin subir a la nube. Quedan guardados en '
          'este equipo y suben cuando vuelvas a entrar con esta cuenta.';
}
