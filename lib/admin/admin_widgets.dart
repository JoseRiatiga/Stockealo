import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/design/app_dialog.dart';
import '../core/design/status_pill.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/clock_text.dart';
import '../core/widgets/app_toast.dart';

/// Piezas comunes de las secciones del panel de administrador

String adminDate(DateTime? d) => d == null ? '—' : DateFormat('dd/MM/yyyy').format(d);

/// «23/11/2026 · 11:26 p. m.»: la hora en 12 h, como en toda la app (re-diseño del panel)
String adminDateTime(DateTime? d) => d == null ? '—' : '${DateFormat('dd/MM/yyyy').format(d)} · ${clockText(d)}';

/// «hoy 11:26 p. m.», «ayer 9:02 a. m.» o «23/11/2026»
String adminWhen(DateTime? d, {DateTime? now}) {
  if (d == null) return '—';
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'hoy ${clockText(d)}';
  if (day == today.subtract(const Duration(days: 1))) return 'ayer ${clockText(d)}';
  return adminDate(d);
}

/// «Hoy», «Ayer» o «lunes 23 de noviembre», para agrupar listas por día
String adminDayTitle(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Hoy';
  if (day == today.subtract(const Duration(days: 1))) return 'Ayer';
  const days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  const months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  final base = '${days[d.weekday - 1]} ${d.day} de ${months[d.month - 1]}';
  return d.year == n.year ? base : '$base de ${d.year}';
}

/// «JR» de «Jose Riatiga», o la primera letra del correo
String adminInitials(String? name, String email) {
  final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return email.isEmpty ? '?' : email[0].toUpperCase();
  return (words.first[0] + (words.length > 1 ? words.last[0] : '')).toUpperCase();
}

Future<void> adminCopy(BuildContext context, String text, String label) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) AppToast.show(context, message: '$label copiado', type: ToastType.success);
}

/// Qué tan ancha es una sección en el computador (re-diseño del panel: antes todo se
/// estiraba hasta 1200 px y los botones quedaban lejos de su renglón)
enum AdminWidth {
  /// Listas de renglones (pagos, suscripciones, usuarios…)
  list(880),

  /// Formularios (códigos, configuración, mantenimiento)
  form(720),

  /// Pantallas con columnas o tarjetas (Resumen, Negocios)
  full(1240);

  final double max;
  const AdminWidth(this.max);
}

/// Contenido de una sección: título, acciones y lista centrada en pantallas anchas
class AdminPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final AdminWidth width;

  const AdminPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.children,
    this.onRefresh,
    this.width = AdminWidth.list,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final width = MediaQuery.of(context).size.width;
    final list = ListView(
      padding: EdgeInsets.fromLTRB(width >= 900 ? AppSpace.xl : AppSpace.lg, AppSpace.xl, width >= 900 ? AppSpace.xl : AppSpace.lg, AppSpace.xxl),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.page(context)),
                  if (subtitle != null) Text(subtitle!, style: AppText.small(context)),
                ],
              ),
            ),
            ...actions,
            if (onRefresh != null)
              IconButton(
                tooltip: 'Actualizar',
                onPressed: onRefresh,
                icon: Icon(Icons.refresh_outlined, color: c.inkMuted),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        ...children,
      ],
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: this.width.max),
        child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list),
      ),
    );
  }
}

/// Tarjeta del panel
class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AdminCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpace.lg)});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}

/// Etiqueta de estado (verde, ámbar, gris)
class AdminBadge extends StatelessWidget {
  final String text;
  final AdminTone tone;

  const AdminBadge(this.text, {super.key, this.tone = AdminTone.neutral});

  /// La misma pastilla de estado de la app (`StatusPill`)
  @override
  Widget build(BuildContext context) => StatusPill(
        text,
        tone: switch (tone) {
          AdminTone.good => AppTone.success,
          AdminTone.warn => AppTone.warning,
          AdminTone.bad => AppTone.danger,
          AdminTone.neutral => AppTone.neutral,
        },
        compact: true,
      );
}

enum AdminTone { good, warn, bad, neutral }

/// Carga, error o vacío, con el mismo aspecto en todas las secciones
class AdminLoadState extends StatelessWidget {
  final bool loading;
  final String? error;
  final bool empty;
  final String emptyText;
  final VoidCallback? onRetry;

  /// Pantalla vacía (re-diseño): ícono y qué aparecerá aquí
  final IconData emptyIcon;
  final String? emptyDetail;

  const AdminLoadState({
    super.key,
    required this.loading,
    required this.error,
    required this.empty,
    required this.emptyText,
    this.onRetry,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyDetail,
  });

  /// true si hay algo que mostrar en vez de la lista
  bool get blocking => loading || error != null || empty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (loading) {
      return const Padding(padding: EdgeInsets.all(AppSpace.xxl), child: Center(child: CircularProgressIndicator()));
    }
    if (error != null) {
      return AdminCard(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          children: [
            Icon(Icons.cloud_off_outlined, size: 28, color: c.danger),
            const SizedBox(height: AppSpace.sm),
            Text('No se pudo cargar', style: AppText.body(context, weight: FontWeight.w600)),
            Text(error!, textAlign: TextAlign.center, style: AppText.small(context, color: c.inkMuted)),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    return AdminEmpty(icon: emptyIcon, title: emptyText, detail: emptyDetail);
  }
}

/// Pantalla vacía del panel (re-diseño): ícono, qué pasa y qué aparecerá aquí
class AdminEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;

  const AdminEmpty({super.key, this.icon = Icons.inbox_outlined, required this.title, this.detail});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AdminCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
      child: Column(
        children: [
          Icon(icon, size: 28, color: c.inkFaint),
          const SizedBox(height: AppSpace.sm),
          Text(title, textAlign: TextAlign.center, style: AppText.body(context, weight: FontWeight.w600)),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(detail!, textAlign: TextAlign.center, style: AppText.small(context, color: c.inkMuted)),
          ],
        ],
      ),
    );
  }
}

/// Un bloque con título dentro de una ficha («Negocios · 3», «Historial de Pro»)
class AdminBlock extends StatelessWidget {
  final String title;
  final int? count;
  final String? note;
  final List<Widget> children;

  const AdminBlock({super.key, required this.title, this.count, this.note, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(count == null ? title : '$title · $count', style: AppText.small(context, weight: FontWeight.w700, color: c.ink)),
          if (note != null) Text(note!, style: AppText.caption(context, color: c.inkFaint)),
          const SizedBox(height: AppSpace.sm),
          ...children,
        ],
      ),
    );
  }
}

/// Un dato con ícono: «Correo ........ ana@x.com»
class AdminInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const AdminInfoRow({super.key, required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c.inkMuted),
          const SizedBox(width: AppSpace.sm),
          // Ancho para «Última entrada» en una sola línea (con 92 se partía en dos)
          SizedBox(
            width: 120,
            child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis,
                style: AppText.small(context, color: c.inkMuted)),
          ),
          Expanded(
            child: Text(value, textAlign: TextAlign.right, style: AppText.small(context, color: valueColor ?? c.ink)),
          ),
        ],
      ),
    );
  }
}

/// Un renglón de historial con un punto de color: activo, terminado o por revisar
class AdminTimelineRow extends StatelessWidget {
  final AdminTone tone;
  final String text;
  final String? trailing;

  const AdminTimelineRow({super.key, required this.tone, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dot = switch (tone) {
      AdminTone.good => c.success,
      AdminTone.warn => c.warning,
      AdminTone.bad => c.danger,
      AdminTone.neutral => c.inkFaint,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(text, style: AppText.small(context, color: c.ink))),
          if (trailing != null) ...[
            const SizedBox(width: AppSpace.sm),
            Text(trailing!, style: AppText.caption(context, color: c.inkMuted)),
          ],
        ],
      ),
    );
  }
}

/// Círculo con iniciales
class AdminAvatar extends StatelessWidget {
  final String initials;
  final double size;
  const AdminAvatar(this.initials, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final t = ToneColors.of(context, AppTone.success);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.soft, shape: BoxShape.circle),
      child: Text(initials, style: AppText.body(context, weight: FontWeight.w700, color: t.text)),
    );
  }
}

/// Una opción de [adminChoose]
class AdminChoice<T> {
  final T value;
  final String label;
  final String? detail;
  const AdminChoice(this.value, this.label, {this.detail});
}

/// Elegir una opción en una ventana con el diseño de la app (re-diseño del panel; antes
/// eran listas simples). [info] va arriba: lo que ya tiene el negocio, por ejemplo.
Future<T?> adminChoose<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  IconData icon = Icons.tune_outlined,
  Widget? info,
  required List<AdminChoice<T>> options,
}) =>
    AppDialog.show<T>(
      context: context,
      icon: icon,
      tone: AppTone.success,
      title: title,
      subtitle: subtitle,
      content: Builder(
        builder: (ctx) {
          final c = ctx.colors;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (info != null) ...[info, const SizedBox(height: AppSpace.md)],
              for (final o in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
                    ),
                    onPressed: () => Navigator.pop(ctx, o.value),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.label, style: AppText.body(ctx, weight: FontWeight.w600, color: c.ink)),
                        if (o.detail != null) Text(o.detail!, style: AppText.caption(ctx, color: c.inkMuted)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );

/// Buscador de las listas
class AdminSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onSubmitted;

  const AdminSearchField({super.key, required this.hint, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: TextField(
        textInputAction: TextInputAction.search,
        onSubmitted: (v) => onSubmitted(v.trim()),
        decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search_outlined)),
      ),
    );
  }
}

/// Estado de un pago para el panel. Uno que sigue «pendiente» después de 24 horas nunca
/// se terminó (la persona cerró Wompi): dice «Sin terminar», no «Pendiente» para siempre.
({String label, AdminTone tone}) adminPaymentState(String status, DateTime? createdAt, {DateTime? now}) {
  switch (status) {
    case 'APPROVED':
      return (label: 'Aprobado', tone: AdminTone.good);
    case 'DECLINED':
      return (label: 'Rechazado', tone: AdminTone.bad);
    case 'VOIDED':
      return (label: 'Anulado', tone: AdminTone.neutral);
    case 'ERROR':
      return (label: 'Con error', tone: AdminTone.bad);
  }
  final old = createdAt != null && (now ?? DateTime.now()).difference(createdAt) > const Duration(hours: 24);
  return old ? (label: 'Sin terminar', tone: AdminTone.warn) : (label: 'Pendiente', tone: AdminTone.warn);
}

/// Filtro de Pagos «Ocultar sin terminar y de prueba» (aprobado el 24 nov): se oculta
/// un pago sin terminar y uno «de prueba», que es el que hizo alguien del equipo del
/// panel ([team], correos en minúscula), aunque haya sido con plata real.
bool adminPaymentHidden(String status, DateTime? createdAt, String userEmail, Set<String> team, {DateTime? now}) =>
    team.contains(userEmail.trim().toLowerCase()) || adminPaymentState(status, createdAt, now: now).label == 'Sin terminar';
