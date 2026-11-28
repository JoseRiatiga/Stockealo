import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../widgets/app_toast.dart';

/// LA forma de copiar al portapapeles (0.18.8). En la web el navegador a veces no
/// deja copiar (la pestaña no está al frente, permisos) y `Clipboard.setData` falla:
/// antes eso salía como error en el panel y la persona no se enteraba. Ahora avisa
/// que copie a mano. Todo botón «Copiar» de la app y del panel usa esta.
abstract final class AppClipboard {
  static const failedMessage = 'No se pudo copiar. Selecciona el texto y cópialo a mano.';

  /// Copia [text] y avisa con [message] (o [title] y [message]). Devuelve si se copió.
  static Future<bool> copy(BuildContext context, String text, {required String message, String? title}) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      if (context.mounted) AppToast.show(context, message: failedMessage, type: ToastType.warning);
      return false;
    }
    if (context.mounted) AppToast.show(context, message: message, title: title, type: ToastType.success);
    return true;
  }
}
