import 'package:flutter/material.dart';

import '../core/utils/app_clipboard.dart';
import '../core/design/app_dialog.dart';
import '../core/design/filter_tabs.dart';
import '../core/design/status_pill.dart';
import '../core/services/supabase_service.dart';
import '../core/theme/app_tokens.dart';
import 'admin_widgets.dart';

/// Un error agrupado: el mismo mensaje y el mismo lugar
class AppErrorGroup {
  final String fingerprint;
  final String message;
  final int count;
  final DateTime lastAt;
  final List<String> versions;
  final List<String> platforms;
  final List<String> apps;
  final String? stack;

  const AppErrorGroup({
    required this.fingerprint,
    required this.message,
    required this.count,
    required this.lastAt,
    this.versions = const [],
    this.platforms = const [],
    this.apps = const [],
    this.stack,
  });

  static List<String> _list(Object? v) => [for (final x in (v as List? ?? const [])) if (x != null) '$x'];

  factory AppErrorGroup.fromJson(Map<String, dynamic> j) => AppErrorGroup(
        fingerprint: '${j['fingerprint'] ?? ''}',
        message: '${j['message'] ?? ''}',
        count: (j['count'] is num) ? (j['count'] as num).toInt() : int.tryParse('${j['count']}') ?? 0,
        lastAt: DateTime.tryParse('${j['last_at']}')?.toLocal() ?? DateTime.now(),
        versions: _list(j['versions']),
        platforms: _list(j['platforms']),
        apps: _list(j['apps']),
        stack: j['stack'] as String?,
      );

  /// «hace 2 h», «ayer», «hace 5 días»
  static String ago(DateTime at, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(at);
    if (d.inMinutes < 60) return 'hace ${d.inMinutes < 1 ? 1 : d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    if (d.inDays == 1) return 'ayer';
    return 'hace ${d.inDays} días';
  }
}

/// Panel › Errores (0.16.0, fase 5): lo que falla en la app, la tienda y el panel,
/// agrupado. Sin datos de clientes: solo el error, la versión y el tipo de equipo.
class AdminErrorsPage extends StatefulWidget {
  /// Para las pruebas: de dónde salen los errores (por defecto, la nube)
  final Future<List<AppErrorGroup>> Function(int days)? loader;
  const AdminErrorsPage({super.key, this.loader});

  @override
  State<AdminErrorsPage> createState() => _AdminErrorsPageState();
}

class _AdminErrorsPageState extends State<AdminErrorsPage> {
  int _days = 7;
  List<AppErrorGroup> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<AppErrorGroup>> _fetch(int days) async {
    final client = SupabaseService.instance.client;
    if (client == null) return const [];
    final rows = await client.rpc('admin_error_groups', params: {'p_days': days});
    return [for (final r in rows as List) AppErrorGroup.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await (widget.loader ?? _fetch)(_days);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      final s = '$e';
      if (mounted) {
        setState(() => _error = s.contains('admin_only') || s.contains('admin_role_forbidden')
            ? 'Solo los administradores pueden ver los errores.'
            : s.contains('PGRST202')
                ? 'Actualiza la nube para ver los errores.'
                : 'No se pudieron cargar los errores. Revisa tu conexión.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(AppErrorGroup g) => AppSheet.show<void>(
        context: context,
        title: '${g.count} ${g.count == 1 ? 'vez' : 'veces'}',
        subtitle: 'Último: ${AppErrorGroup.ago(g.lastAt)} · ${g.versions.join(', ')}',
        builder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(g.message, style: AppText.body(ctx, weight: FontWeight.w600)),
            const SizedBox(height: AppSpace.sm),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final a in g.apps) StatusPill(a, compact: true),
              for (final p in g.platforms) StatusPill(p, tone: AppTone.info, compact: true),
            ]),
            if (g.stack != null) ...[
              const SizedBox(height: AppSpace.md),
              Container(
                padding: const EdgeInsets.all(AppSpace.sm),
                decoration: BoxDecoration(color: ctx.colors.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.control)),
                child: SelectableText(g.stack!, style: AppText.mono(ctx, size: AppText.sizeCaption)),
              ),
              const SizedBox(height: AppSpace.sm),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Copiar para revisarlo'),
                onPressed: () => AppClipboard.copy(ctx, '${g.message}\n\n${g.stack}', message: 'Copiado'),
              ),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AdminLoadState(
      loading: _loading,
      error: _error,
      empty: _items.isEmpty,
      emptyText: 'Sin errores en estos días',
      emptyDetail: 'Si algo falla en la app, la tienda o el panel, aparece aquí.',
      emptyIcon: Icons.check_circle_outline,
      onRetry: _load,
    );
    return AdminPage(
      title: 'Errores',
      subtitle: 'Lo que falla en la app, la tienda y el panel. Sin datos de clientes.',
      onRefresh: _load,
      children: [
        FilterTabs<int>(
          options: const {1: 'Hoy', 7: '7 días', 30: '30 días'},
          value: _days,
          onChanged: (v) {
            setState(() => _days = v);
            _load();
          },
        ),
        const SizedBox(height: AppSpace.md),
        if (state.blocking)
          state
        else
          for (final g in _items)
            AdminCard(
              child: InkWell(
                onTap: () => _open(g),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.bug_report_outlined, color: g.count >= 10 ? c.danger : c.warning),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g.message, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(context, weight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            [g.versions.join(', '), g.platforms.join(', '), 'último: ${AppErrorGroup.ago(g.lastAt)}'].where((s) => s.isNotEmpty).join(' · '),
                            style: AppText.small(context, color: c.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    StatusPill('${g.count} ${g.count == 1 ? 'vez' : 'veces'}', tone: g.count >= 10 ? AppTone.danger : AppTone.warning, compact: true),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
