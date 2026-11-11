import 'package:flutter/material.dart';

import '../design/app_dialog.dart';
import '../theme/app_tokens.dart';
import '../services/update_service.dart';
import 'formatted_changelog_view.dart';

/// Aviso de versión nueva del APK: qué trae, cuánto pesa, y la descarga con su avance.
class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
  });

  static Future<void> show(BuildContext context, AppUpdateInfo updateInfo) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateDialog(updateInfo: updateInfo),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '';
  String? _errorMessage;

  void _startDownload() {
    if (widget.updateInfo.downloadUrl == null) return;

    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusText = 'Empezando la descarga…';
      _errorMessage = null;
    });

    UpdateService.instance.downloadAndInstallApk(
      downloadUrl: widget.updateInfo.downloadUrl!,
      onProgress: (progress, received, total) {
        if (!mounted) return;
        setState(() {
          _progress = progress;
          if (progress >= 1.0) {
            _statusText = 'Abriendo el instalador…';
          } else {
            final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
            final totMb = (total / (1024 * 1024)).toStringAsFixed(1);
            final pct = (progress * 100).toInt();
            _statusText = 'Descargando: $pct % ($recMb de $totMb MB)';
          }
        });
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _errorMessage = msg;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final notes = widget.updateInfo.releaseNotes?.trim().isNotEmpty == true
        ? widget.updateInfo.releaseNotes!.trim()
        : '- Mejoras de rendimiento y estabilidad.';
    return AppDialog(
      icon: Icons.system_update_outlined,
      title: 'Hay una versión nueva',
      subtitle: 'Versión ${widget.updateInfo.latestVersion} · tienes la ${widget.updateInfo.currentVersion}',
      showCloseButton: !_isDownloading,
      maxWidth: 480,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Qué trae', style: AppText.body(context, weight: FontWeight.w600)),
          const SizedBox(height: AppSpace.sm),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(AppSpace.md + 2),
            decoration: BoxDecoration(
              color: c.paper,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: c.line),
            ),
            child: SingleChildScrollView(child: FormattedChangelogView(rawChangelog: notes)),
          ),
          if (widget.updateInfo.formattedSize.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text('Pesa unos ${widget.updateInfo.formattedSize}', style: AppText.caption(context)),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpace.md),
            Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
              child: Text(_errorMessage!, style: AppText.small(context, color: c.danger)),
            ),
          ],
          if (_isDownloading) ...[
            const SizedBox(height: AppSpace.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 8),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(_statusText, textAlign: TextAlign.center, style: AppText.small(context, weight: FontWeight.w600, color: c.ink)),
            const SizedBox(height: AppSpace.xs),
            Text('Tus datos y ventas de este equipo no se tocan.', textAlign: TextAlign.center, style: AppText.caption(context)),
          ],
        ],
      ),
      actions: _isDownloading
          ? [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar'))]
          : [
              OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Más tarde')),
              FilledButton.icon(
                onPressed: _startDownload,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Actualizar ahora'),
              ),
            ],
    );
  }
}
