import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/currency_options.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../legal/presentation/screens/legal_document_screen.dart';
import '../../../products/presentation/screens/barcode_scanner_screen.dart';
import '../../../team/data/team_repository.dart';
import '../../data/business_repository.dart';
import '../../models/business.dart';

class BusinessSelectorModal extends StatefulWidget {
  final String userId;
  final VoidCallback? onLogout;
  final bool isDialog;

  const BusinessSelectorModal({
    super.key,
    required this.userId,
    this.onLogout,
    this.isDialog = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String userId,
    VoidCallback? onLogout,
  }) {
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    if (isDesktop) {
      return showDialog<bool>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BusinessSelectorModal(
                userId: userId,
                onLogout: onLogout,
                isDialog: true,
              ),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BusinessSelectorModal(
        userId: userId,
        onLogout: onLogout,
        isDialog: false,
      ),
    );
  }

  @override
  State<BusinessSelectorModal> createState() => _BusinessSelectorModalState();
}

class _BusinessSelectorModalState extends State<BusinessSelectorModal> {
  final _businessRepo = BusinessRepository.instance;
  List<Business> _businesses = [];
  List<Business> _deletedBusinesses = [];
  Map<String, String> _rolesByBusinessId = {};
  Business? _currentBusiness;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBusinesses();
  }

  Future<void> _loadBusinesses() async {
    final user = AuthRepository.instance.currentUser;
    final userEmail = user?.email ?? '';
    final list = await _businessRepo.getAllBusinesses(widget.userId, userEmail);
    final active = await _businessRepo.getActiveBusiness(widget.userId, userEmail);
    final deleted = await _businessRepo.getDeletedBusinesses(widget.userId);

    final Map<String, String> roles = {};
    for (final biz in list) {
      roles[biz.id] = await TeamRepository.instance.getUserRoleInBusiness(
        businessId: biz.id,
        userId: widget.userId,
        userEmail: userEmail,
      );
    }

    if (mounted) {
      setState(() {
        _businesses = list;
        _currentBusiness = active;
        _deletedBusinesses = deleted;
        _rolesByBusinessId = roles;
        _isLoading = false;
      });
    }
  }

  Future<void> _showCreateBusinessDialog() async {
    final nameController = TextEditingController();
    String selectedCurrency = 'COP';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) => AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.storefront_rounded, color: Color(0xFF10B981), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Crear Nueva Empresa', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      Text(
                        'Ingresa el nombre y moneda de tu sede',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la Empresa o Tienda',
                      hintText: 'Ej. Minimarket Central, Ropa & Moda...',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedCurrency,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Moneda Principal',
                      prefixIcon: Icon(Icons.monetization_on_outlined),
                    ),
                    items: kAvailableCurrencies.map((c) {
                      return DropdownMenuItem(
                        value: c.code,
                        child: Text(c.label),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedCurrency = val);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                onPressed: () {
                  if (nameController.text.trim().isNotEmpty) {
                    Navigator.pop(ctx, {
                      'name': nameController.text.trim(),
                      'currency': selectedCurrency,
                    });
                  }
                },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Crear y Entrar'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null && result['name']!.isNotEmpty) {
      final newBiz = await _businessRepo.createBusiness(
        name: result['name']!,
        userId: widget.userId,
        currency: result['currency'] ?? 'COP',
      );
      _businessRepo.setActiveBusiness(newBiz);
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  Future<void> _showJoinBusinessDialog() async {
    final codeController = TextEditingController();
    bool isSubmitting = false;
    // Se muestra dentro del diálogo: un SnackBar quedaría oculto tras él y la hoja de negocios
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.group_add_outlined, color: Color(0xFF059669)),
              SizedBox(width: 10),
              Text('Unirse a Empresa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ingresa como colaborador escaneando el código QR o escribiendo el código de invitación.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 18),

                // Botón Cámara QR
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
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
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                    color: Color(0xFF059669),
                  ),
                  decoration: InputDecoration(
                    labelText: 'Código de Invitación',
                    hintText: 'Ej. 6CC1-4831',
                    errorText: errorText,
                    errorMaxLines: 3,
                    prefixIcon: const Icon(Icons.pin, color: Color(0xFF64748B)),
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
                backgroundColor: const Color(0xFF059669),
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
                          userId: widget.userId,
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
                            backgroundColor: const Color(0xFF059669),
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

  Future<void> _confirmLeaveBusiness(Business biz) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir de este equipo?'),
        content: Text('Ya no tendrás acceso a los productos ni ventas de "${biz.name}". Puedes volver a unirte con el código de invitación.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir del equipo'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final user = AuthRepository.instance.currentUser;
      final userEmail = user?.email ?? '';
      final db = await AppDatabase.instance.database;

      // Eliminar membresía local
      await db.delete(
        'business_members',
        where: 'business_id = ? AND (user_id = ? OR LOWER(email) = ?)',
        whereArgs: [biz.id, widget.userId, userEmail.toLowerCase()],
      );

      // Eliminar de Supabase
      try {
        final client = SupabaseService.instance.client;
        if (client != null) {
          await client
              .from('business_members')
              .delete()
              .eq('business_id', biz.id)
              .eq('user_email', userEmail.toLowerCase());
        }
      } catch (_) {}

      // Si era la empresa activa, cambiar a otra
      if (_currentBusiness?.id == biz.id) {
        final otherBusinesses = _businesses.where((b) => b.id != biz.id).toList();
        if (otherBusinesses.isNotEmpty) {
          _businessRepo.setActiveBusiness(otherBusinesses.first);
        } else {
          _businessRepo.setActiveBusiness(null);
        }
      }

      await _loadBusinesses();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Has salido del equipo de "${biz.name}"')),
        );
      }
    }
  }

  Future<void> _showEditBusinessDialog(Business biz) async {
    final role = _rolesByBusinessId[biz.id] ?? 'CASHIER';
    if (role == 'CASHIER') {
      if (mounted) {
        AppToast.showPermission(
          context,
          'Solo el dueño o administradores pueden cambiar los datos de la empresa.',
        );
      }
      return;
    }

    final nameController = TextEditingController(text: biz.name);
    String selectedCurrency = biz.currency;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) => AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.edit_note_rounded, color: Color(0xFF10B981), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Editar Empresa', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      Text(
                        'Modifica el nombre o moneda principal',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la Empresa',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedCurrency,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Moneda Principal',
                      prefixIcon: Icon(Icons.monetization_on_outlined),
                    ),
                    items: kAvailableCurrencies.map((c) {
                      return DropdownMenuItem(
                        value: c.code,
                        child: Text(c.label),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedCurrency = val);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                onPressed: () {
                  if (nameController.text.trim().isNotEmpty) {
                    Navigator.pop(ctx, {
                      'name': nameController.text.trim(),
                      'currency': selectedCurrency,
                    });
                  }
                },
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Guardar'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null && result['name']!.isNotEmpty) {
      await _businessRepo.updateBusiness(
        id: biz.id,
        name: result['name']!,
        currency: result['currency'] ?? 'COP',
      );
      await _loadBusinesses();
    }
  }

  Future<void> _confirmDeleteBusiness(Business biz) async {
    final typedController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final isMatch = typedController.text.trim() == biz.name.trim();
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                  SizedBox(width: 8),
                  Expanded(child: Text('¿Mover a papelera?')),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'La empresa "${biz.name}" se moverá a la papelera. Tendrás 7 días para restaurarla antes de su eliminación definitiva.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Para confirmar, escribe exactamente el nombre de la empresa:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? const Color(0xFF0F172A)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(ctx).brightness == Brightness.dark
                            ? const Color(0xFF334155)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: SelectableText(
                      biz.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(ctx).brightness == Brightness.dark
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF0F172A),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: typedController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Escribe aquí para confirmar',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: isMatch ? const Color(0xFF059669) : Colors.red,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isMatch ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade500,
                  ),
                  child: const Text('Eliminar y mover a papelera'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      await _businessRepo.softDeleteBusiness(biz.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Empresa "${biz.name}" movida a la papelera (conservada por 7 días)'),
          backgroundColor: const Color(0xFF334155),
        ),
      );
      await _loadBusinesses();
      if (_currentBusiness == null || _currentBusiness?.id == biz.id) {
        if (_businesses.isNotEmpty) {
          _businessRepo.setActiveBusiness(_businesses.first);
        }
      }
    }
  }

  Future<void> _showPermanentDeleteDialog(
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

                        await _businessRepo.deleteBusinessPermanently(biz.id);
                        if (trashCtx.mounted) {
                          setTrashState(() {
                            deleted.removeWhere((b) => b.id == biz.id);
                          });
                        }
                        await _loadBusinesses();

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

  Future<void> _showEmptyTrashDialog(
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

                        await _businessRepo.emptyTrash(widget.userId);
                        if (trashCtx.mounted) {
                          setTrashState(() {
                            deleted.clear();
                          });
                        }
                        await _loadBusinesses();

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

  Future<void> _showTrashModal() async {
    final deleted = await _businessRepo.getDeletedBusinesses(widget.userId);
    if (!mounted) return;

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
                          onPressed: () => _showEmptyTrashDialog(trashCtx, setTrashState, deleted),
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
                                        await _businessRepo.restoreBusiness(biz.id);
                                        setTrashState(() {
                                          deleted.removeWhere((b) => b.id == biz.id);
                                        });
                                        await _loadBusinesses();
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
                                      onPressed: () => _showPermanentDeleteDialog(trashCtx, biz, setTrashState, deleted),
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
    await _loadBusinesses();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF131126) : Colors.white;
    final borderColor = isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0);

    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        widget.isDialog ? 24 : MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: widget.isDialog
            ? BorderRadius.circular(24)
            : const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isDialog)
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF332D5C) : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Tus Empresas / Negocios',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Los productos y ventas de cada empresa están 100% aislados.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),

          // Botones de acción principales (Unirse y Crear Negocio)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showJoinBusinessDialog,
                  icon: const Icon(Icons.group_add_outlined, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Unirme a Negocio',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF2563EB) : const Color(0xFF93C5FD),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showCreateBusinessDialog,
                  icon: const Icon(Icons.add_business_outlined, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Crear Negocio',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else if (_businesses.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF18152F) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.storefront_outlined, size: 40, color: Color(0xFF94A3B8)),
                    const SizedBox(height: 8),
                    Text(
                      'No tienes empresas activas.',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Usa los botones de arriba para unirte a un equipo o crear tu negocio.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _businesses.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final biz = _businesses[index];
                  final isSelected = _currentBusiness?.id == biz.id;

                  return Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDark ? const Color(0xFF0F2D24) : const Color(0xFFECFDF5))
                          : (isDark ? const Color(0xFF18152F) : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF10B981)
                            : (isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0)),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              _businessRepo.setActiveBusiness(biz);
                              Navigator.pop(context, true);
                            },
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isSelected
                                        ? const Color(0xFF059669)
                                        : (isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0)),
                                    foregroundColor: isSelected
                                        ? Colors.white
                                        : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                    child: const Icon(Icons.storefront, size: 20),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Nombre del negocio en su propia fila completa
                                        Text(
                                          biz.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                            color: isSelected
                                                ? (isDark ? const Color(0xFF34D399) : const Color(0xFF065F46))
                                                : (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B)),
                                          ),
                                        ),
                                        const SizedBox(height: 4),

                                        // Etiquetas de estado, rol y moneda
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            if (isSelected)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF059669),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'ACTIVA',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            Builder(
                                              builder: (_) {
                                                final role = _rolesByBusinessId[biz.id] ?? 'CASHIER';
                                                final isOwner = role == 'OWNER';
                                                final roleLabel = isOwner
                                                    ? 'Dueño'
                                                    : (role == 'ADMIN' ? 'Admin' : 'Cajero');
                                                final roleIcon = isOwner
                                                    ? Icons.workspace_premium_rounded
                                                    : (role == 'ADMIN' ? Icons.shield_outlined : Icons.point_of_sale_outlined);
                                                final roleColor = isOwner
                                                    ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                                    : (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB));
                                                return Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: isOwner
                                                        ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5))
                                                        : (isDark ? const Color(0xFF1E3A8A).withOpacity(0.4) : const Color(0xFFEFF6FF)),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: isOwner
                                                          ? const Color(0xFF059669)
                                                          : const Color(0xFF2563EB),
                                                      width: 0.8,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(roleIcon, size: 10, color: roleColor),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        roleLabel,
                                                        style: TextStyle(
                                                          color: roleColor,
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                            Text(
                                              '• ${getCurrencyLabel(biz.currency)}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 22, color: Color(0xFF64748B)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onSelected: (action) {
                            if (action == 'edit') {
                              _showEditBusinessDialog(biz);
                            } else if (action == 'delete') {
                              _confirmDeleteBusiness(biz);
                            } else if (action == 'leave') {
                              _confirmLeaveBusiness(biz);
                            }
                          },
                          itemBuilder: (ctx) {
                            final role = _rolesByBusinessId[biz.id] ?? 'CASHIER';
                            final isOwner = role == 'OWNER';
                            final isAdmin = role == 'ADMIN';
                            final canManage = isOwner || isAdmin;
                            return [
                              if (canManage)
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                        color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('Editar negocio'),
                                    ],
                                  ),
                                ),
                              if (isOwner)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Mover a papelera', style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              if (!isOwner)
                                const PopupMenuItem(
                                  value: 'leave',
                                  child: Row(
                                    children: [
                                      Icon(Icons.exit_to_app, size: 18, color: Colors.orange),
                                      SizedBox(width: 8),
                                      Text('Salir del equipo', style: TextStyle(color: Colors.orange)),
                                    ],
                                  ),
                                ),
                            ];
                          },
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),

          // Papelera de Empresas (si existen empresas eliminadas)
          if (_deletedBusinesses.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF450A0A).withOpacity(0.4) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA),
                ),
              ),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFDC2626), size: 22),
                title: Text(
                  'Papelera (${_deletedBusinesses.length} ${_deletedBusinesses.length == 1 ? "empresa" : "empresas"})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                  ),
                ),
                subtitle: Text(
                  'Recupera empresas antes de 7 días',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20, color: Color(0xFFDC2626)),
                onTap: _showTrashModal,
              ),
            ),

          Divider(height: 1, color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0)),
          const SizedBox(height: 4),

          // Términos y Privacidad
          ListTile(
            leading: Icon(
              Icons.shield_outlined,
              color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
            ),
            title: Text(
              'Términos y Privacidad',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
              ),
            ),
            trailing: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF94A3B8)),
            onTap: () {
              Navigator.pop(context);
              LegalDocumentScreen.show(context);
            },
          ),

          // Botón de Cerrar Sesión
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              AuthRepository.instance.logout();
              BusinessRepository.instance.setActiveBusiness(null);
              widget.onLogout?.call();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
