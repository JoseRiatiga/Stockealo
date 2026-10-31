import '../../../../core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../products/presentation/screens/barcode_scanner_screen.dart';
import '../../../team/data/team_repository.dart';

/// Unirse a un negocio con el código de invitación o su QR.
class JoinBusinessDialog {
  static Future<void> show(BuildContext context, {required String userId}) async {
    final codeController = TextEditingController();
    bool isSubmitting = false;
    // Se muestra dentro del diálogo: un SnackBar quedaría oculto tras él y la hoja de negocios
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.group_add_outlined, color: context.colors.accent),
              const SizedBox(width: 10),
              const Text('Unirse a Empresa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ingresa como colaborador escaneando el código QR o escribiendo el código de invitación.',
                  style: TextStyle(fontSize: 13, color: context.colors.inkMuted),
                ),
                const SizedBox(height: 18),

                // Botón Cámara QR
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    label: const Text('Escanear Código QR', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final scanned = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
                            );
                            if (scanned != null && scanned.trim().isNotEmpty) {
                              codeController.text = scanned.trim();
                              setDialogState(() {});
                            }
                          },
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'O escribe el código',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? context.colors.inkMuted
                              : context.colors.inkMuted,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),

                // Campo Código de Invitación
                TextField(
                  controller: codeController,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                    color: context.colors.accent,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Código de Invitación',
                    hintText: 'Ej. 6CC1-4831',
                    errorText: errorText,
                    errorMaxLines: 3,
                    prefixIcon: Icon(Icons.pin, color: context.colors.inkMuted),
                    suffixIcon: codeController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              codeController.clear();
                              setDialogState(() => errorText = null);
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setDialogState(() => errorText = null),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.accent,
                foregroundColor: Colors.white,
              ),
              onPressed: isSubmitting || codeController.text.trim().isEmpty
                  ? null
                  : () async {
                      setDialogState(() {
                        isSubmitting = true;
                        errorText = null;
                      });
                      try {
                        final user = AuthRepository.instance.currentUser;
                        final userEmail = user?.email ?? '';
                        final userName = user?.name;

                        final joinedBiz = await TeamRepository.instance.joinBusinessByCode(
                          codeOrId: codeController.text.trim(),
                          userId: userId,
                          userEmail: userEmail,
                          userName: userName,
                        );

                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('¡Te has unido exitosamente a "${joinedBiz.name}"!'),
                            backgroundColor: context.colors.accent,
                          ),
                        );
                        Navigator.pop(context, true);
                      } catch (e) {
                        if (!dialogCtx.mounted) return;
                        setDialogState(() {
                          isSubmitting = false;
                          errorText = e.toString().replaceAll('Exception: ', '');
                        });
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Unirme'),
            ),
          ],
        ),
      ),
    );
  }
}
