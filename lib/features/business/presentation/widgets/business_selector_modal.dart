import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/currency_options.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../legal/presentation/screens/legal_document_screen.dart';
import '../../../products/presentation/screens/barcode_scanner_screen.dart';
import '../../../team/data/team_repository.dart';
import '../../data/business_repository.dart';
import '../../models/business.dart';

class BusinessSelectorModal extends StatefulWidget {
  final String userId;
  final VoidCallback? onLogout;

  const BusinessSelectorModal({
    super.key,
    required this.userId,
    this.onLogout,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String userId,
    VoidCallback? onLogout,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BusinessSelectorModal(
        userId: userId,
        onLogout: onLogout,
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
  Business? _currentBusiness;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBusinesses();
  }

  Future<void> _loadBusinesses() async {
    final list = await _businessRepo.getAllBusinesses(widget.userId);
    final active = await _businessRepo.getActiveBusiness(widget.userId);
    final deleted = await _businessRepo.getDeletedBusinesses(widget.userId);
    if (mounted) {
      setState(() {
        _businesses = list;
        _currentBusiness = active;
        _deletedBusinesses = deleted;
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
            title: const Text('Crear Nueva Empresa'),
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
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.trim().isNotEmpty) {
                    Navigator.pop(ctx, {
                      'name': nameController.text.trim(),
                      'currency': selectedCurrency,
                    });
                  }
                },
                child: const Text('Crear y Entrar'),
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
                    prefixIcon: const Icon(Icons.pin, color: Color(0xFF64748B)),
                    suffixIcon: codeController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              codeController.clear();
                              setDialogState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setDialogState(() {}),
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
                      setDialogState(() => isSubmitting = true);
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
                        setDialogState(() => isSubmitting = false);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(e.toString().replaceAll('Exception: ', '')),
                            backgroundColor: Colors.red,
                          ),
                        );
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
              .or('user_id.eq.${widget.userId},email.ilike.$userEmail');
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
    final nameController = TextEditingController(text: biz.name);
    String selectedCurrency = biz.currency;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) => AlertDialog(
            title: const Text('Editar Empresa'),
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
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.trim().isNotEmpty) {
                    Navigator.pop(ctx, {
                      'name': nameController.text.trim(),
                      'currency': selectedCurrency,
                    });
                  }
                },
                child: const Text('Guardar'),
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
                                  icon: const Icon(Icons.restore, size: 16),
                                  label: const Text('Restaurar'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF059669),
                                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
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

          // Botones de acción principales (Unirse y Crear Empresa)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showJoinBusinessDialog,
                  icon: const Icon(Icons.group_add_outlined, size: 18),
                  label: const Text('Unirme'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF93C5FD),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showCreateBusinessDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Crear Empresa'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
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
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
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
                          ? (isDark ? const Color(0xFF064E3B).withOpacity(0.5) : const Color(0xFFECFDF5))
                          : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? (isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
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
                                        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
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
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                biz.name,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                  color: isSelected
                                                      ? (isDark ? const Color(0xFF34D399) : const Color(0xFF065F46))
                                                      : (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B)),
                                                ),
                                              ),
                                            ),
                                            if (isSelected)
                                              Container(
                                                margin: const EdgeInsets.only(left: 6),
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
                                            Container(
                                              margin: const EdgeInsets.only(left: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: biz.userId == widget.userId
                                                    ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5))
                                                    : (isDark ? const Color(0xFF1E3A8A).withOpacity(0.4) : const Color(0xFFEFF6FF)),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: biz.userId == widget.userId
                                                      ? const Color(0xFF059669)
                                                      : const Color(0xFF2563EB),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(
                                                biz.userId == widget.userId ? '👑 Dueño' : '👥 Equipo',
                                                style: TextStyle(
                                                  color: biz.userId == widget.userId
                                                      ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                                      : (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB)),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Moneda: ${getCurrencyLabel(biz.currency)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                          ),
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
                          itemBuilder: (ctx) => [
                            if (biz.userId == widget.userId) ...[
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
                            ] else ...[
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
                            ],
                          ],
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

          Divider(height: 1, color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
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
