import 'package:flutter/material.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/status_pill.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/theme/app_tokens.dart';

/// Cambio de contraseña: pide la actual (se verifica con Supabase Auth) y la nueva.
class ChangePasswordDialog {
  static Future<void> show(BuildContext context, {required String userId}) async {
    final currentPassController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AppDialog(
          icon: Icons.lock_reset_outlined,
          tone: AppTone.accent,
          title: 'Cambiar contraseña',
          subtitle: 'Actualiza tu clave de acceso de manera segura',
          maxWidth: 440,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPassController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña Actual',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: newPassController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nueva Contraseña',
                  prefixIcon: Icon(Icons.lock_reset_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: confirmPassController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar Nueva Contraseña',
                  prefixIcon: Icon(Icons.check_circle_outline_outlined),
                ),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(
                  color: context.colors.lineStrong,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: context.colors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.accent,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () async {
                if (newPassController.text != confirmPassController.text) {
                  AppToast.show(context, message: 'Las contraseñas no coinciden', type: ToastType.warning);
                  return;
                }
                try {
                  await AuthRepository.instance.changePassword(
                    userId: userId,
                    currentPassword: currentPassController.text,
                    newPassword: newPassController.text,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    AppToast.show(context, message: 'Contraseña actualizada correctamente', type: ToastType.success);
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppToast.show(context, message: e.toString().replaceAll('Exception: ', ''), type: ToastType.error);
                  }
                }
              },
              child: const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}
