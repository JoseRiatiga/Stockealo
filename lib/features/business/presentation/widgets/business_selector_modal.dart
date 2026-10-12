import 'package:flutter/material.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../../core/utils/currency_options.dart';
import '../../../legal/presentation/screens/legal_document_screen.dart';
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tus Empresas / Negocios',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                ),
              ),
              TextButton.icon(
                onPressed: _showCreateBusinessDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nueva'),
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Text(
            'Los productos y ventas de cada empresa están 100% aislados.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),

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
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _showCreateBusinessDialog,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Crear Empresa'),
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
                            }
                          },
                          itemBuilder: (ctx) => [
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
            title: const Text('Términos y Privacidad', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
