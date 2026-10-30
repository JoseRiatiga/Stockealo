import 'join_business_dialog.dart';
import 'business_trash.dart';
import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/currency_options.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../legal/presentation/screens/legal_document_screen.dart';
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
                  onPressed: () => JoinBusinessDialog.show(context, userId: widget.userId),
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
                onTap: () => BusinessTrash.show(context, userId: widget.userId, onChanged: _loadBusinesses),
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
