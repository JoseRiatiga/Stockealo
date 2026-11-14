import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_tokens.dart';
import '../core/widgets/app_toast.dart';
import '../core/design/status_pill.dart';

/// Piezas comunes de las secciones del panel de administrador

String adminDate(DateTime? d) => d == null ? '—' : DateFormat('dd/MM/yyyy').format(d);
String adminDateTime(DateTime? d) => d == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(d);

Future<void> adminCopy(BuildContext context, String text, String label) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) AppToast.show(context, message: '$label copiado', type: ToastType.success);
}

/// Contenido de una sección: título, acciones y lista centrada en pantallas anchas
class AdminPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  const AdminPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.children,
    this.onRefresh,
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
        constraints: BoxConstraints(maxWidth: width > 1100 ? 1200 : double.infinity),
        child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list),
      ),
    );
  }
}

/// Tarjeta blanca de V1
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

  const AdminLoadState({
    super.key,
    required this.loading,
    required this.error,
    required this.empty,
    required this.emptyText,
    this.onRetry,
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
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          children: [
            Text(error!, textAlign: TextAlign.center, style: TextStyle(color: c.danger)),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Text(emptyText, textAlign: TextAlign.center, style: TextStyle(color: c.inkMuted)),
    );
  }
}

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
