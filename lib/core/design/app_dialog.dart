import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'status_pill.dart';

/// LA ventana de Stockealo. Toda ventana de la app usa esta (o [AppDialog.confirm]):
/// ícono con el color de su tono, título, subtítulo, contenido y acciones abajo a la
/// derecha. Reemplaza a la ventana vieja del primer diseño y a las armadas a mano.
class AppDialog extends StatelessWidget {
  final IconData? icon;
  final AppTone tone;
  final String title;
  final String? subtitle;
  final Widget? content;
  final List<Widget>? actions;
  final double maxWidth;
  final bool showCloseButton;

  const AppDialog({
    super.key,
    this.icon,
    this.tone = AppTone.accent,
    required this.title,
    this.subtitle,
    this.content,
    this.actions,
    this.maxWidth = 440,
    this.showCloseButton = true,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    IconData? icon,
    AppTone tone = AppTone.accent,
    required String title,
    String? subtitle,
    Widget? content,
    List<Widget>? actions,
    double maxWidth = 440,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => AppDialog(
        icon: icon,
        tone: tone,
        title: title,
        subtitle: subtitle,
        content: content,
        actions: actions,
        maxWidth: maxWidth,
      ),
    );
  }

  /// Pregunta de sí o no. Devuelve true solo si la persona confirma.
  /// [destructive] pinta el botón en rojo («Borrar», «Anular»).
  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    required String message,
    IconData? icon,
    String confirmText = 'Aceptar',
    String cancelText = 'Cancelar',
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        icon: icon ?? (destructive ? Icons.warning_amber_outlined : Icons.help_outline_outlined),
        tone: destructive ? AppTone.danger : AppTone.accent,
        title: title,
        content: Text(message, style: AppText.body(ctx, color: ctx.colors.inkMuted)),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(cancelText)),
          FilledButton(
            style: destructive ? FilledButton.styleFrom(backgroundColor: ctx.colors.danger, foregroundColor: Colors.white) : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ToneColors.of(context, tone);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg + 4, vertical: AppSpace.xl),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.control)),
                      child: Icon(icon, color: t.strong, size: 22),
                    ),
                    const SizedBox(width: AppSpace.md + 2),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppText.heading(context)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: AppText.small(context)),
                        ],
                      ],
                    ),
                  ),
                  if (showCloseButton)
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_outlined, size: 20, color: c.inkMuted),
                    ),
                ],
              ),
              if (content != null) ...[
                const SizedBox(height: AppSpace.lg + 4),
                Flexible(child: SingleChildScrollView(child: content!)),
              ],
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xl),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: actions!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// LA hoja que sube desde abajo. Toda hoja usa esta: el asa la pone el tema (las
/// pantallas no dibujan la suya), título, subtítulo opcional y el contenido con su
/// margen. En pantallas anchas no pasa de [maxWidth].
class AppSheet {
  AppSheet._();

  static Future<T?> show<T>({
    required BuildContext context,
    String? title,
    String? subtitle,
    required Widget Function(BuildContext context) builder,
    double maxWidth = 640,
    bool scrollable = true,
    bool isDismissible = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      builder: (ctx) {
        final body = Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.lg + 2,
            0,
            AppSpace.lg + 2,
            AppSpace.lg + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Text(title, style: AppText.heading(ctx)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppText.small(ctx)),
                ],
                const SizedBox(height: AppSpace.lg),
              ],
              builder(ctx),
            ],
          ),
        );
        return scrollable ? SingleChildScrollView(child: body) : body;
      },
    );
  }
}

/// Panel para resolver algo sin perder de vista la pantalla: en el computador
/// entra por la derecha (como «Resolver» en el Inicio); en el celular es la hoja
/// del sistema ([AppSheet]). Lleva título, subtítulo, ✕ y el contenido.
class AppSidePanel {
  AppSidePanel._();

  /// Desde este ancho el panel va a la derecha
  static const wideFrom = 900.0;

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? subtitle,
    Widget? leading,
    required Widget Function(BuildContext context) builder,
    double width = 460,
  }) {
    if (MediaQuery.sizeOf(context).width < wideFrom) {
      return AppSheet.show<T>(context: context, title: title, subtitle: subtitle, builder: builder);
    }
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: AppMotion.of(context, AppMotion.normal),
      pageBuilder: (ctx, _, __) {
        final c = ctx.colors;
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: c.surface,
            child: SizedBox(
              width: width,
              height: double.infinity,
              child: SafeArea(
                left: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpace.xl - 2, AppSpace.xl - 2, AppSpace.lg, AppSpace.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (leading != null) ...[leading, const SizedBox(width: AppSpace.md)],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: AppText.heading(ctx)),
                                if (subtitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(subtitle, style: AppText.small(ctx)),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.of(ctx).maybePop(),
                            icon: Icon(Icons.close_outlined, size: 20, color: c.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(AppSpace.xl - 2, 0, AppSpace.xl - 2, AppSpace.xl - 2),
                        child: builder(ctx),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: AppMotion.curve)),
        child: child,
      ),
    );
  }
}
