import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

/// Aviso de que la app ya está en la última versión.
class UpToDateDialog {
  static void show(BuildContext context, String currentVersion) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: context.colors.line,
            width: 1.5,
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.accent.withValues(alpha: 0.15),
                  border: Border.all(
                    color: context.colors.accent.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.verified_outlined,
                  color: context.colors.accent,
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '¡Estás al día!',
                style: TextStyle(
                  fontSize: AppText.sizeHeading,
                  fontWeight: FontWeight.bold,
                  color: context.colors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: context.colors.lineStrong,
                  ),
                ),
                child: Text(
                  'Versión v$currentVersion',
                  style: TextStyle(
                    fontSize: AppText.sizeCaption,
                    fontWeight: FontWeight.w600,
                    color: context.colors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Tu aplicación cuenta con las últimas optimizaciones, correcciones y funciones disponibles.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppText.sizeSmall,
                  height: 1.4,
                  color: context.colors.inkMuted,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Entendido',
                    style: TextStyle(fontSize: AppText.sizeBody, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
