import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/widgets/app_toast.dart';

/// Sección de Ajustes: título pequeño en mayúscula y una tarjeta con sus filas
class SettingsGroup extends StatelessWidget {
  final String? label;
  final List<Widget> children;

  const SettingsGroup({super.key, this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, indent: 64, color: c.line));
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpace.lg, bottom: AppSpace.sm),
              child: Text(
                label!.toUpperCase(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.inkFaint),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }
}

/// Sección con título a la izquierda, valor actual a la derecha y contenido libre
/// (círculos de color, tamaños de letra…)
class SettingsPanel extends StatelessWidget {
  final String label;
  final String? value;
  final Widget child;

  const SettingsPanel({super.key, required this.label, this.value, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.inkFaint),
                  ),
                ),
                if (value != null)
                  Text(value!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.accent)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.line),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Ícono dentro de un cuadro suave del color de acento
class SettingsIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;

  const SettingsIcon(this.icon, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.colors.accent;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: tint.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 19, color: tint),
    );
  }
}

/// Fila de Ajustes: ícono, título, valor actual debajo y flecha o interruptor
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Para acciones peligrosas (borrar, cerrar sesión)
  final bool danger;
  final Color? iconColor;

  /// Reemplaza el ícono (por ejemplo, el logo del negocio)
  final Widget? leading;

  const SettingsRow({
    super.key,
    this.icon = Icons.circle_outlined,
    this.leading,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.danger = false,
    this.iconColor,
  });

  /// Fila con interruptor; tocar en cualquier parte lo cambia
  factory SettingsRow.toggle({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) =>
      SettingsRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = danger ? c.danger : null;
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.md, AppSpace.md),
          child: Row(
            children: [
              leading ?? SettingsIcon(icon, color: color ?? iconColor),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: color ?? c.ink)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              trailing ?? (onTap != null ? Icon(Icons.chevron_right_rounded, color: c.inkFaint) : const SizedBox()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Subpantalla de Ajustes: botón atrás redondo, título centrado y la barra de
/// cambios pendientes abajo
class SettingsSubpage extends StatelessWidget {
  final String title;
  final List<Widget> children;

  /// Se reconstruye cuando cambia el estado de la pantalla de Ajustes
  final Listenable? refresh;

  const SettingsSubpage({super.key, required this.title, required this.children, this.refresh});

  static Future<void> open(BuildContext context,
      {required String title, required List<Widget> Function() children, Listenable? refresh}) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => refresh == null
          ? SettingsSubpage(title: title, children: children())
          : ListenableBuilder(
              listenable: refresh,
              builder: (_, __) => SettingsSubpage(title: title, refresh: refresh, children: children()),
            ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md),
              child: Row(
                children: [
                  _BackButton(onTap: () => Navigator.pop(context)),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, 120),
                    children: children,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const PendingChangesBar(),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Atrás',
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle, border: Border.all(color: c.line)),
          child: Icon(Icons.chevron_left_rounded, color: c.ink),
        ),
      ),
    );
  }
}

/// Barra "N cambios · Descartar · Revisar" de las preferencias sin guardar
class PendingChangesBar extends StatelessWidget {
  /// false cuando ya va encima de otra barra que respeta el borde inferior
  final bool useSafeArea;

  const PendingChangesBar({super.key, this.useSafeArea = true});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance;
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) {
        final count = theme.pendingChanges.length;
        final c = context.colors;
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: count == 0
              ? const SizedBox(width: double.infinity)
              : SafeArea(
                  top: false,
                  bottom: useSafeArea,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
                    padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.sm, AppSpace.sm),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: c.line),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(
                            count == 1 ? '1 cambio' : '$count cambios',
                            style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
                          ),
                        ),
                        TextButton(
                          onPressed: theme.discardChanges,
                          style: TextButton.styleFrom(foregroundColor: c.inkMuted),
                          child: const Text('Descartar'),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        FilledButton(
                          onPressed: () => ReviewChangesSheet.show(context),
                          child: const Text('Revisar'),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Hoja con cada cambio (antes → después) y el botón para guardarlos
class ReviewChangesSheet extends StatelessWidget {
  final VoidCallback? onSaved;

  const ReviewChangesSheet({super.key, this.onSaved});

  /// El aviso "Guardado" sale en la pantalla que abrió la hoja
  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => ReviewChangesSheet(
          onSaved: () {
            if (context.mounted) AppToast.show(context, message: 'Guardado', type: ToastType.success);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = ThemeController.instance;
    final changes = theme.pendingChanges;
    return Container(
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: c.lineStrong, borderRadius: BorderRadius.circular(AppRadius.pill)),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Text('Revisar cambios', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
              Text(
                changes.length == 1 ? '1 cambio listo para aplicar' : '${changes.length} cambios listos para aplicar',
                style: TextStyle(fontSize: 13, color: c.inkMuted),
              ),
              const SizedBox(height: AppSpace.md),
              for (final change in changes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(change.label, style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                      ),
                      Flexible(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '${change.before} → ', style: TextStyle(color: c.inkMuted)),
                            TextSpan(
                              text: change.after,
                              style: TextStyle(fontWeight: FontWeight.w700, color: c.accent),
                            ),
                          ]),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpace.md),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () async {
                  Navigator.pop(context);
                  await theme.saveChanges();
                  onSaved?.call();
                },
                child: const Text('Guardar cambios'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
