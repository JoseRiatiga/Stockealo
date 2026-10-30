import 'package:flutter/material.dart';
import '../../../auth/data/auth_repository.dart';
import '../../data/business_repository.dart';
import '../../models/business.dart';

/// Papelera de negocios: restaurar, eliminar definitivamente o vaciarla.
class BusinessTrash {
  static Future<void> show(
    BuildContext context, {
    required String userId,
    required Future<void> Function() onChanged,
  }) async {
    final deleted = await BusinessRepository.instance.getDeletedBusinesses(userId);
    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (trashCtx, setTrashState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
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
                        color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
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
                          const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                          const SizedBox(width: 8),
                          Text(
                            'Papelera de Empresas',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                      if (deleted.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _emptyTrash(context, userId, onChanged, trashCtx, setTrashState, deleted),
                          icon: const Icon(Icons.delete_sweep, size: 16, color: Colors.red),
                          label: const Text(
                            'Vaciar',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Las empresas se conservan aquí durante 7 días antes de eliminarse de forma permanente.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (deleted.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          'No hay empresas en la papelera',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
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
                              color: isDark ? const Color(0xFF450A0A).withOpacity(0.4) : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA),
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2),
                                  foregroundColor: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626),
                                  child: const Icon(Icons.storefront, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        biz.name,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                                        ),
                                      ),
                                      Text(
                                        'Expira en $daysLeft ${daysLeft == 1 ? "día" : "días"}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626),
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
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text('Empresa "${biz.name}" restaurada con éxito'),
                                            backgroundColor: const Color(0xFF059669),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.restore, size: 15),
                                      label: const Text('Restaurar'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(0xFF059669),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.delete_forever, size: 20, color: Colors.red),
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
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final isWordMatch = wordController.text.trim().toUpperCase() == 'VACIAR';
          final canSubmit = isWordMatch && passwordController.text.length >= 6 && !isDeleting;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.delete_sweep, color: Colors.red, size: 28),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '¿Vaciar toda la papelera?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF450A0A).withOpacity(0.5) : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA)),
                    ),
                    child: Text(
                      'Se destruirán definitivamente todas las empresas en la papelera (${deleted.length} ${deleted.length == 1 ? "empresa" : "empresas"}) y todos sus datos en el teléfono y en la nube. Esta acción NO se puede deshacer.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '1. Escribe la palabra VACIAR para confirmar:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
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
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
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
                        icon: Icon(obscurePassword ? Icons.visibility : Icons.visibility_off),
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
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
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
                  backgroundColor: Colors.red,
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

                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Papelera vaciada por completo.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    : null,
                icon: isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.delete_sweep, size: 18),
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
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final isNameMatch = nameController.text.trim() == biz.name.trim();
          final canSubmit = isNameMatch && passwordController.text.length >= 6 && !isDeleting;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Eliminar definitivamente',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF450A0A).withOpacity(0.5) : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA)),
                    ),
                    child: Text(
                      'Esta acción es IRREVERSIBLE. Se destruirán para siempre los productos, ventas, inventario, clientes y miembros de "${biz.name}" en el teléfono y en la nube.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '1. Escribe el nombre exacto de la empresa:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                    ),
                    child: SelectableText(
                      biz.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                        fontSize: 13,
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
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
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
                        icon: Icon(obscurePassword ? Icons.visibility : Icons.visibility_off),
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
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
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
                  backgroundColor: Colors.red,
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

                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Empresa "${biz.name}" eliminada definitivamente.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    : null,
                icon: isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.delete_forever, size: 18),
                label: const Text('Destruir Definitivamente'),
              ),
            ],
          );
        },
      ),
    );
  }
}
