import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/app_dialog.dart';
import '../design/status_pill.dart';
import '../services/supabase_service.dart';
import '../services/sync_queue.dart';
import '../theme/app_tokens.dart';
import 'app_toast.dart';

/// La nube siempre a la vista (0.16.0, fase 5): «Al día», «Subiendo 3», «Sin conexión ·
/// 5 por subir» o «2 no subieron». Al tocarla, qué falta y «Sincronizar ahora».
/// No se ve si la nube está apagada (los datos viven solo en el celular).
class SyncPill extends StatefulWidget {
  /// Solo el ícono con su color (la barra del celular)
  final bool iconOnly;

  /// Para las pruebas: la nube encendida o no (por defecto, el ajuste guardado)
  final bool? cloudEnabled;

  const SyncPill({super.key, this.iconOnly = false, this.cloudEnabled});

  /// Texto, tono e ícono del estado
  static ({String label, AppTone tone, IconData icon}) describe(SyncStatus s) {
    if (s.failed > 0 && !s.offline) {
      return (label: '${s.failed} no ${s.failed == 1 ? 'subió' : 'subieron'}', tone: AppTone.danger, icon: Icons.cloud_sync_outlined);
    }
    if (s.offline) {
      return (
        label: s.pending > 0 ? 'Sin conexión · ${s.pending} por subir' : 'Sin conexión',
        tone: AppTone.warning,
        icon: Icons.cloud_off_outlined,
      );
    }
    if (s.pending > 0) return (label: 'Subiendo ${s.pending}', tone: AppTone.warning, icon: Icons.cloud_upload_outlined);
    return (label: 'Al día', tone: AppTone.success, icon: Icons.cloud_done_outlined);
  }

  @override
  State<SyncPill> createState() => _SyncPillState();
}

class _SyncPillState extends State<SyncPill> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.cloudEnabled;
    if (_enabled == null) _checkCloud();
  }

  @override
  void didUpdateWidget(covariant SyncPill old) {
    super.didUpdateWidget(old);
    if (widget.cloudEnabled != null && widget.cloudEnabled != _enabled) setState(() => _enabled = widget.cloudEnabled);
  }

  /// Si no se puede saber (sin base de datos todavía), la pastilla no se muestra
  Future<void> _checkCloud() async {
    try {
      final v = await SupabaseService.instance.isCloudSyncEnabled();
      if (mounted) setState(() => _enabled = v);
    } catch (_) {}
  }

  Future<void> _details(BuildContext context) async {
    await AppSheet.show<void>(
      context: context,
      title: 'La nube',
      builder: (ctx) => ValueListenableBuilder<SyncStatus>(
        valueListenable: SyncQueue.instance.status,
        builder: (ctx, s, _) {
          final d = SyncPill.describe(s);
          final last = SyncQueue.instance.lastUpload.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [StatusPill(d.label, tone: d.tone, icon: d.icon)]),
              const SizedBox(height: AppSpace.md),
              Text(
                s.failed > 0 && !s.offline
                    ? 'La nube no aceptó ${s.failed == 1 ? 'un cambio' : '${s.failed} cambios'}. No se borran: siguen guardados en este celular.'
                    : s.offline
                        ? 'Tus ventas y cambios se guardan en este celular y suben solos cuando vuelva el internet.'
                        : s.pending > 0
                            ? 'Subiendo tus últimos cambios a la nube.'
                            : 'Todo lo de este celular ya está en la nube.',
                style: AppText.body(ctx),
              ),
              if (last != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text('Última subida: ${DateFormat("d 'de' MMM, h:mm a", 'es_CO').format(last)}',
                    style: AppText.small(ctx, color: ctx.colors.inkMuted)),
              ],
              const SizedBox(height: AppSpace.lg),
              FilledButton.icon(
                icon: const Icon(Icons.sync_outlined),
                label: const Text('Sincronizar ahora'),
                onPressed: () async {
                  if (s.failed > 0) await SyncQueue.instance.retryFailed();
                  await SupabaseService.instance.flushPendingSync();
                  final now = SyncQueue.instance.status.value;
                  if (ctx.mounted) {
                    AppToast.show(
                      ctx,
                      message: now.pending == 0 && now.failed == 0
                          ? 'Todo al día'
                          : (now.offline ? 'Sin conexión: se intentará solo' : 'Quedan ${now.pending + now.failed} por subir'),
                      type: now.pending == 0 && now.failed == 0 ? ToastType.success : ToastType.warning,
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled != true) return const SizedBox.shrink();
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: SyncQueue.instance.status,
      builder: (context, s, _) {
        final d = SyncPill.describe(s);
        final tone = ToneColors.of(context, d.tone);
        if (widget.iconOnly) {
          return IconButton(
            tooltip: 'La nube: ${d.label}',
            onPressed: () => _details(context),
            icon: Icon(d.icon, size: 20, color: tone.strong),
          );
        }
        return Tooltip(
          message: 'La nube: ${d.label}',
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: () => _details(context),
            child: StatusPill(d.label, tone: d.tone, icon: d.icon),
          ),
        );
      },
    );
  }
}
