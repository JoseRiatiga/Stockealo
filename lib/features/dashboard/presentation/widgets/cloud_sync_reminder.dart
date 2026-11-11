import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';

/// Recordatorio suave en Inicio cuando la nube está apagada: los datos viven solo
/// en este celular. Aparece tras unos días de uso y, si lo cierran, no vuelve en
/// varias semanas. En la web no aplica (allá la nube va siempre encendida).
class CloudSyncReminder extends StatefulWidget {
  /// Solo el dueño o un administrador deciden dónde se guardan los datos
  final bool canManage;

  const CloudSyncReminder({super.key, required this.canManage});

  static const firstSeenKey = 'cloud_reminder_first_seen';
  static const dismissedKey = 'cloud_reminder_dismissed_at';
  static const daysBeforeFirst = 3;
  static const daysBetween = 21;

  /// Decide si toca mostrarlo ahora. Separado para poder probarlo.
  static bool shouldShow({
    required DateTime now,
    required DateTime firstSeen,
    DateTime? dismissedAt,
  }) {
    if (now.difference(firstSeen).inDays < daysBeforeFirst) return false;
    if (dismissedAt != null && now.difference(dismissedAt).inDays < daysBetween) return false;
    return true;
  }

  @override
  State<CloudSyncReminder> createState() => _CloudSyncReminderState();
}

class _CloudSyncReminderState extends State<CloudSyncReminder> {
  bool _visible = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (!widget.canManage || SupabaseService.cloudSyncForced) return;
    try {
      if (await SupabaseService.instance.isCloudSyncEnabled()) return;
      final db = AppDatabase.instance;
      final now = DateTime.now();
      var firstSeen = DateTime.tryParse(await db.getSetting(CloudSyncReminder.firstSeenKey) ?? '');
      if (firstSeen == null) {
        firstSeen = now;
        await db.setSetting(CloudSyncReminder.firstSeenKey, now.toIso8601String());
      }
      final dismissed = DateTime.tryParse(await db.getSetting(CloudSyncReminder.dismissedKey) ?? '');
      final show = CloudSyncReminder.shouldShow(now: now, firstSeen: firstSeen, dismissedAt: dismissed);
      if (mounted && show) setState(() => _visible = true);
    } catch (_) {
      // Un recordatorio nunca debe romper Inicio
    }
  }

  Future<void> _dismiss() async {
    setState(() => _visible = false);
    try {
      await AppDatabase.instance.setSetting(CloudSyncReminder.dismissedKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  Future<void> _activate() async {
    setState(() => _working = true);
    final cloud = SupabaseService.instance;
    await cloud.setCloudSyncEnabled(true);
    final result = await cloud.syncToCloud();
    if (!mounted) return;
    setState(() {
      _working = false;
      _visible = false;
    });
    if (result.success) {
      AppToast.showSuccess(context, 'Listo: tus datos quedaron guardados en la nube.');
    } else {
      AppToast.showWarning(
        context,
        'La nube quedó activada, pero no se pudo subir todo ahora. Se reintentará solo cuando haya conexión.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_off_outlined, color: c.warning),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tus datos están solo en este celular',
                        style: AppText.bodyLarge(context, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Si lo pierdes o se daña, se pierden. Con la copia en la nube también puedes '
                        'verlos desde el computador.',
                        style: AppText.small(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _working ? null : _dismiss,
                  style: TextButton.styleFrom(foregroundColor: c.inkMuted),
                  child: const Text('Ahora no'),
                ),
                const SizedBox(width: AppSpace.sm),
                FilledButton(
                  onPressed: _working ? null : _activate,
                  child: Text(_working ? 'Subiendo…' : 'Activar la nube'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
