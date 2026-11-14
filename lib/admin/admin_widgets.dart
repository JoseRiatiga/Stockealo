import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_tokens.dart';
import '../core/widgets/app_toast.dart';

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
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xxl),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: AppText.sizeHeading, fontWeight: FontWeight.w700, color: c.ink)),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
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
        constraints: BoxConstraints(maxWidth: width > 1100 ? 960 : double.infinity),
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (tone) {
      AdminTone.good => (c.successSoft, c.success),
      AdminTone.warn => (c.warningSoft, c.warning),
      AdminTone.bad => (c.dangerSoft, c.danger),
      AdminTone.neutral => (c.surfaceMuted, c.inkMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(text, style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w600, color: fg)),
    );
  }
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
