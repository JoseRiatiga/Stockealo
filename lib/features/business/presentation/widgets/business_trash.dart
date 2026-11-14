import '../../../../core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import '../../../auth/data/auth_repository.dart';
import '../../data/business_repository.dart';
import '../../models/business.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/status_pill.dart';

/// Papelera de negocios: restaurar, eliminar definitivamente o vaciarla.
class BusinessTrash {
  static Future<void> show(
    BuildContext context, {
    required String userId,
    required Future<void> Function() onChanged,
  }) async {
    final deleted = await BusinessRepository.instance.getDeletedBusinesses(userId);
    if (!context.mounted) return;


    await showModalBottomSheet(
      showDragHandle: false,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (trashCtx, setTrashState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.colors.lineStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.delete_outline_outlined, color: context.colors.danger),
                          const SizedBox(width: 8),
                          Text(
                            'Papelera de negocios',
                            style: TextStyle(
                              fontSize: AppText.sizeHeading,
                              fontWeight: FontWeight.bold,
                              color: context.colors.ink,
                            ),
                          ),
                        ],
                      ),
                      if (deleted.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _emptyTrash(context, userId, onChanged, trashCtx, setTrashState, deleted),
                          icon: Icon(Icons.delete_sweep_outlined, size: 16, color: context.colors.danger),
                          label: Text(
                            'Vaciar',
                            style: TextStyle(
                              color: context.colors.danger,
                              fontWeight: FontWeight.bold,
                              fontSize: AppText.sizeCaption,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Los negocios se conservan aquí durante 7 días antes de eliminarse de forma permanente.',
                    style: TextStyle(
                      fontSize: AppText.sizeCaption,
                      color: context.colors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (deleted.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          'No hay negocios en la papelera',
                          style: TextStyle(color: context.colors.inkMuted, fontSize: AppText.sizeBody),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: deleted.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (itemCtx, index) {
                          final biz = deleted[index];
                          final daysLeft = biz.daysRemainingInTrash;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: context.colors.dangerSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: context.colors.dangerSoft,
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: context.colors.dangerSoft,
                                  foregroundColor: context.colors.danger,
                                  child: const Icon(Icons.storefront_outlined, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        biz.name,
                                        style: TextStyle(
                                          fontSize: AppText.sizeBody,
                                          fontWeight: FontWeight.bold,
                                          color: context.colors.ink,
                                        ),
                                      ),
                                      Text(
                                        'Expira en $daysLeft ${daysLeft == 1 ? "día" : "días"}',
                                        style: TextStyle(
                                          fontSize: AppText.sizeCaption,
                                          fontWeight: FontWeight.w600,
                                          color: context.colors.danger,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () async {
                                        final messenger = ScaffoldMessenger.of(trashCtx);
                                        await BusinessRepository.instance.restoreBusiness(biz.id);
                                        setTrashState(() {
                                          deleted.removeWhere((b) => b.id == biz.id);
                                        });
                                        await onChanged();
                                        AppToast.showWith(messenger, message: 'Negocio "${biz.name}" restaurado', type: ToastType.info);
                                      },
                                      icon: const Icon(Icons.restore_outlined, size: 15),
                                      label: const Text('Restaurar'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: context.colors.accent,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppText.sizeCaption),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: Icon(Icons.delete_forever_outlined, size: 20, color: context.colors.danger),
                                      tooltip: 'Eliminar definitivamente',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _permanentDelete(context, onChanged, trashCtx, biz, setTrashState, deleted),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    await onChanged();
  }

  static Future<void> _emptyTrash(
    BuildContext context,
    String userId,
    Future<void> Function() onChanged,
    BuildContext trashCtx,
    StateSetter setTrashState,
    List<Business> deleted,
  ) async {
    final wordController = TextEditingController();
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    String? errorMessage;
    bool isDeleting = false;

    await showDialog<void>(
      context: trashCtx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isWordMatch = wordController.text.trim().toUpperCase() == 'VACIAR';
          final canSubmit = isWordMatch && passwordController.text.length >= 6 && !isDeleting;

          return AppDialog(
icon: Icons.delete_sweep_outlined,
tone: AppTone.danger,
title: '¿Vaciar toda la papelera?',
content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.colors.dangerSoft),
                    ),
                    child: Text(
                      'Se destruirán definitivamente todos los negocios de la papelera (${deleted.length} ${deleted.length == 1 ? "negocio" : "negocios"}) y todos sus datos en el teléfono y en la nube. Esta acción NO se puede deshacer.',
                      style: TextStyle(
                        fontSize: AppText.sizeCaption,
                        color: context.colors.danger,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '1. Escribe la palabra VACIAR para confirmar:',
                    style: TextStyle(
                      fontSize: AppText.sizeCaption,
                      fontWeight: FontWeight.bold,
                      color: context.colors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: wordController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'VACIAR',
                      prefixIcon: const Icon(Icons.delete_sweep_outlined),
                      errorText: wordController.text.isNotEmpty && !isWordMatch ? 'Escribe exactamente VACIAR' : null,
                    ),
                    onChanged: (_) => setDialogState(() => errorMessage = null),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '2. Ingresa tu contraseña de Dueño:',
                    style: TextStyle(
                      fontSize: AppText.sizeCaption,
                      fontWeight: FontWeight.bold,
                      color: context.colors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      hintText: 'Contraseña de tu cuenta',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                      ),
                    ),
                    onChanged: (_) => setDialogState(() => errorMessage = null),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.colors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_outlined, color: context.colors.danger, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: TextStyle(color: context.colors.danger, fontSize: AppText.sizeCaption, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.danger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                onPressed: canSubmit
                    ? () async {
                        final messenger = ScaffoldMessenger.of(trashCtx);
                        setDialogState(() {
                          isDeleting = true;
                          errorMessage = null;
                        });

                        final isPasswordValid = await AuthRepository.instance.verifyCurrentPassword(
                          passwordController.text,
                        );

                        if (!isPasswordValid) {
                          if (dialogCtx.mounted) {
                            setDialogState(() {
                              isDeleting = false;
                              errorMessage = 'Contraseña incorrecta. No se puede vaciar.';
                            });
                          }
                          return;
                        }

                        await BusinessRepository.instance.emptyTrash(userId);
                        if (trashCtx.mounted) {
                          setTrashState(() {
                            deleted.clear();
                          });
                        }
                        await onChanged();

                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }

                        AppToast.showWith(messenger, message: 'Papelera vaciada por completo.', type: ToastType.error);
                      }
                    : null,
                icon: isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Vaciar Todo'),
              ),
            ],
);
        },
      ),
    );
  }

  static Future<void> _permanentDelete(
    BuildContext context,
    Future<void> Function() onChanged,
    BuildContext trashCtx,
    Business biz,
    StateSetter setTrashState,
    List<Business> deleted,
  ) async {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    String? errorMessage;
    bool isDeleting = false;

    await showDialog<void>(
      context: trashCtx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isNameMatch = nameController.text.trim() == biz.name.trim();
          final canSubmit = isNameMatch && passwordController.text.length >= 6 && !isDeleting;

          return AppDialog(
icon: Icons.warning_amber_outlined,
tone: AppTone.danger,
title: 'Eliminar definitivamente',
content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.colors.dangerSoft),
                    ),
                    child: Text(
                      'Esta acción es IRREVERSIBLE. Se destruirán para siempre los productos, ventas, inventario, clientes y miembros de "${biz.name}" en el teléfono y en la nube.',
                      style: TextStyle(
                        fontSize: AppText.sizeCaption,
                        color: context.colors.danger,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '1. Escribe el nombre exacto del negocio:',
                    style: TextStyle(
                      fontSize: AppText.sizeCaption,
                      fontWeight: FontWeight.bold,
                      color: context.colors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.colors.lineStrong),
                    ),
                    child: SelectableText(
                      biz.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: context.colors.info,
                        fontSize: AppText.sizeSmall,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      hintText: biz.name,
                      prefixIcon: const Icon(Icons.storefront_outlined),
                      errorText: nameController.text.isNotEmpty && !isNameMatch ? 'El nombre no coincide' : null,
                    ),
                    onChanged: (_) => setDialogState(() => errorMessage = null),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '2. Ingresa tu contraseña de Dueño:',
                    style: TextStyle(
                      fontSize: AppText.sizeCaption,
                      fontWeight: FontWeight.bold,
                      color: context.colors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      hintText: 'Contraseña de tu cuenta',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                      ),
                    ),
                    onChanged: (_) => setDialogState(() => errorMessage = null),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.colors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_outlined, color: context.colors.danger, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: TextStyle(color: context.colors.danger, fontSize: AppText.sizeCaption, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.danger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                onPressed: canSubmit
                    ? () async {
                        final messenger = ScaffoldMessenger.of(trashCtx);
                        setDialogState(() {
                          isDeleting = true;
                          errorMessage = null;
                        });

                        final isPasswordValid = await AuthRepository.instance.verifyCurrentPassword(
                          passwordController.text,
                        );

                        if (!isPasswordValid) {
                          if (dialogCtx.mounted) {
                            setDialogState(() {
                              isDeleting = false;
                              errorMessage = 'Contraseña incorrecta. No se puede eliminar.';
                            });
                          }
                          return;
                        }

                        await BusinessRepository.instance.deleteBusinessPermanently(biz.id);
                        if (trashCtx.mounted) {
                          setTrashState(() {
                            deleted.removeWhere((b) => b.id == biz.id);
                          });
                        }
                        await onChanged();

                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }

                        AppToast.showWith(messenger, message: 'Negocio "${biz.name}" eliminado definitivamente.', type: ToastType.error);
                      }
                    : null,
                icon: isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.delete_forever_outlined, size: 18),
                label: const Text('Destruir Definitivamente'),
              ),
            ],
);
        },
      ),
    );
  }
}
