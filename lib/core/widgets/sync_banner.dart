import 'package:flutter/material.dart';

import '../design/status_pill.dart';
import '../services/supabase_service.dart';
import '../services/sync_queue.dart';
import '../theme/app_tokens.dart';

/// Aviso flotante de la subida a la nube (0.13.4):
/// - sin conexión: «Sin conexión · tus ventas se guardan y se suben solas al volver»;
/// - con cambios que la nube rechazó: «N cambios no se pudieron subir · Reintentar».
/// Cuando todo está al día no se ve.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: SyncQueue.instance.status,
      builder: (context, s, _) {
        if (!s.offline && s.failed == 0) return const SizedBox.shrink();
        final c = context.colors;
        final failed = s.failed > 0 && !s.offline;
        final tone = ToneColors.of(context, failed ? AppTone.danger : AppTone.warning);
        return Material(
          color: tone.soft,
          elevation: 2,
          shadowColor: c.ink.withValues(alpha: 0.18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            side: BorderSide(color: tone.text.withValues(alpha: 0.25)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: failed
                ? () async {
                    await SyncQueue.instance.retryFailed();
                    await SupabaseService.instance.flushPendingSync();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(failed ? Icons.cloud_sync_outlined : Icons.cloud_off_outlined, size: 18, color: tone.text),
                  const SizedBox(width: AppSpace.sm),
                  Flexible(
                    child: Text(
                      failed
                          ? '${s.failed} ${s.failed == 1 ? 'cambio no se pudo' : 'cambios no se pudieron'} subir · Reintentar'
                          : 'Sin conexión · ${s.pending > 0 ? '${s.pending} por subir. ' : ''}Tus ventas se guardan y se suben solas al volver',
                      style: AppText.small(context, weight: FontWeight.w600, color: c.ink),
                    ),
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
