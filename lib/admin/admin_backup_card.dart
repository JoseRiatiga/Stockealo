import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/design/status_pill.dart';
import '../core/services/supabase_service.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/app_toast.dart';
import 'admin_widgets.dart';

/// Una copia diaria
class BackupRun {
  final DateTime day;
  final DateTime startedAt;
  final bool ok;
  final String by;
  final int tables;
  final int rows;
  final int bytes;
  final String? error;

  const BackupRun({
    required this.day,
    required this.startedAt,
    required this.ok,
    this.by = 'cron',
    this.tables = 0,
    this.rows = 0,
    this.bytes = 0,
    this.error,
  });

  static int _n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  factory BackupRun.fromJson(Map<String, dynamic> j) => BackupRun(
        day: DateTime.tryParse('${j['day']}') ?? DateTime.now(),
        startedAt: DateTime.tryParse('${j['started_at']}')?.toLocal() ?? DateTime.now(),
        ok: j['ok'] == true,
        by: '${j['by'] ?? 'cron'}',
        tables: _n(j['tables']),
        rows: _n(j['rows']),
        bytes: _n(j['bytes']),
        error: j['error'] as String?,
      );

  String get size => bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB' : '${(bytes / 1024).round()} KB';
}

/// Panel › Mantenimiento: la copia diaria (0.16.0, fase 5). La última, si quedó completa
/// y «Hacer copia ahora».
class AdminBackupCard extends StatefulWidget {
  /// Para las pruebas
  final Future<List<BackupRun>> Function()? loader;
  final DateTime? now;
  const AdminBackupCard({super.key, this.loader, this.now});

  @override
  State<AdminBackupCard> createState() => _AdminBackupCardState();
}

class _AdminBackupCardState extends State<AdminBackupCard> {
  List<BackupRun>? _runs;
  String? _error;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<BackupRun>> _fetch() async {
    final client = SupabaseService.instance.client;
    if (client == null) return const [];
    final rows = await client.rpc('admin_backup_status');
    return [for (final r in rows as List) BackupRun.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  Future<void> _load() async {
    try {
      final runs = await (widget.loader ?? _fetch)();
      if (mounted) setState(() => (_runs = runs, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.contains('PGRST202') ? 'Actualiza la nube para ver las copias.' : 'No se pudieron cargar las copias.');
    }
  }

  Future<void> _runNow() async {
    setState(() => _running = true);
    try {
      final res = await SupabaseService.instance.client!.functions.invoke('daily-backup', body: const {});
      final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
      if (!mounted) return;
      AppToast.show(
        context,
        message: data['ok'] == true ? 'Copia lista: ${data['tables']} tablas, ${data['rows']} filas.' : 'La copia quedó incompleta: revisa el detalle.',
        type: data['ok'] == true ? ToastType.success : ToastType.warning,
      );
    } catch (e) {
      if (mounted) AppToast.show(context, message: 'No se pudo hacer la copia: $e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _running = false);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final runs = _runs;
    final last = runs == null || runs.isEmpty ? null : runs.first;
    final now = widget.now ?? DateTime.now();
    // Sin copia en más de un día y medio: algo pasa con la tarea programada
    final late = last != null && now.difference(last.startedAt).inHours > 36;
    final fmt = DateFormat("d 'de' MMM, h:mm a", 'es_CO');
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.backup_outlined, color: c.accent),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text('Copia diaria', style: AppText.title(context))),
              if (last != null)
                StatusPill(
                  late ? 'Atrasada' : (last.ok ? 'Completa' : 'Incompleta'),
                  tone: late || !last.ok ? AppTone.danger : AppTone.success,
                  dot: true,
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          if (_error != null)
            Text(_error!, style: AppText.body(context, color: c.danger))
          else if (runs == null)
            const LinearProgressIndicator()
          else if (last == null)
            Text('Todavía no hay copias. La primera sale esta noche a las 3 a. m., o hazla ahora.', style: AppText.body(context, color: c.inkMuted))
          else ...[
            Text(
              'Última: ${fmt.format(last.startedAt)} · ${last.tables} tablas · ${last.rows} filas · ${last.size}',
              style: AppText.body(context),
            ),
            if (last.error != null) ...[
              const SizedBox(height: AppSpace.xs),
              Text(last.error!, style: AppText.small(context, color: c.danger)),
            ],
            const SizedBox(height: AppSpace.xs),
            Text(
              'Se guarda cada noche a las 3 a. m. en un almacenamiento privado y se verifica contando las filas. Quedan las de los últimos 14 días.',
              style: AppText.small(context, color: c.inkMuted),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _running ? null : _runNow,
              icon: _running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.backup_outlined, size: 18),
              label: Text(_running ? 'Copiando…' : 'Hacer copia ahora'),
            ),
          ),
        ],
      ),
    );
  }
}
