import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/currency_options.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../team/data/team_repository.dart';
import '../../../team/models/business_member.dart';
import '../../../team/presentation/screens/employees_screen.dart';
import '../../data/business_repository.dart';
import '../../models/business.dart';
import '../widgets/business_selector_modal.dart';

class BusinessInfoScreen extends StatefulWidget {
  final Business business;
  final VoidCallback onLogout;

  const BusinessInfoScreen({
    super.key,
    required this.business,
    required this.onLogout,
  });

  @override
  State<BusinessInfoScreen> createState() => _BusinessInfoScreenState();
}

class _BusinessInfoScreenState extends State<BusinessInfoScreen> {
  late Business _business;
  final _businessRepo = BusinessRepository.instance;
  final _teamRepo = TeamRepository.instance;

  String _userRole = 'OWNER';
  bool _isLoadingMetrics = true;
  int _productsCount = 0;
  int _salesCount = 0;
  double _salesTotalAmount = 0.0;
  int _customersCount = 0;
  List<BusinessMember> _members = [];
  bool _isCloudSync = false;

  @override
  void initState() {
    super.initState();
    _business = widget.business;
    _loadAllInfo();
  }

  Future<void> _loadAllInfo() async {
    setState(() => _isLoadingMetrics = true);
    try {
      final user = AuthRepository.instance.currentUser;
      if (user != null) {
        final role = await _teamRepo.getUserRoleInBusiness(
          businessId: _business.id,
          userId: user.id,
          userEmail: user.email,
        );
        _userRole = role;
      }

      final isCloud = await SupabaseService.instance.isCloudSyncEnabled();
      final members = await _teamRepo.getMembers(_business.id);

      // Auditoría y métricas desde SQLite local
      final db = await AppDatabase.instance.database;

      final prodRes = await db.rawQuery(
        'SELECT COUNT(*) as count FROM products WHERE business_id = ? AND is_active = 1',
        [_business.id],
      );
      final productsCount = (prodRes.first['count'] as num?)?.toInt() ?? 0;

      final salesRes = await db.rawQuery(
        'SELECT COUNT(*) as count, COALESCE(SUM(total), 0) as total_sum FROM sales WHERE business_id = ?',
        [_business.id],
      );
      final salesCount = (salesRes.first['count'] as num?)?.toInt() ?? 0;
      final salesTotal = (salesRes.first['total_sum'] as num?)?.toDouble() ?? 0.0;

      final custRes = await db.rawQuery(
        'SELECT COUNT(*) as count FROM customers WHERE business_id = ?',
        [_business.id],
      );
      final customersCount = (custRes.first['count'] as num?)?.toInt() ?? 0;

      if (mounted) {
        setState(() {
          _isCloudSync = isCloud;
          _members = members;
          _productsCount = productsCount;
          _salesCount = salesCount;
          _salesTotalAmount = salesTotal;
          _customersCount = customersCount;
        });
      }
    } catch (e) {
      debugPrint('Error cargando información del negocio: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMetrics = false;
        });
      }
    }
  }

  bool get _canEdit => _userRole == 'OWNER' || _userRole == 'ADMIN';

  Future<void> _editBusinessDetails() async {
    if (!_canEdit) {
      AppToast.showPermission(
        context,
        'Solo el dueño o administradores pueden editar los datos del negocio.',
      );
      return;
    }

    final nameController = TextEditingController(text: _business.name);
    final descController = TextEditingController(text: _business.description ?? '');
    String selectedCurrency = _business.currency;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.storefront_outlined, color: Color(0xFF059669)),
                SizedBox(width: 10),
                Text('Editar Negocio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del Negocio *',
                      prefixIcon: Icon(Icons.store),
                    ),
                  ),
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 14),
                  TextField(
                    controller: descController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Descripción / Eslogan (Opcional)',
                      hintText: 'Ej. Venta de abarrotes, tecnología y artículos varios...',
                      prefixIcon: Icon(Icons.description_outlined),
                      alignLabelWithHint: true,
                    ),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  if (nameController.text.trim().isNotEmpty) {
                    Navigator.pop(ctx, {
                      'name': nameController.text.trim(),
                      'currency': selectedCurrency,
                      'description': descController.text.trim(),
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
        id: _business.id,
        name: result['name']!,
        currency: result['currency'] ?? 'COP',
        description: result['description'],
      );

      setState(() {
        _business = _business.copyWith(
          name: result['name']!,
          currency: result['currency'] ?? 'COP',
          description: result['description'],
        );
      });

      if (mounted) {
        AppToast.show(
          context,
          message: 'Datos del negocio actualizados correctamente',
          type: ToastType.success,
        );
      }
    }
  }

  void _copyInviteCode() {
    if (!_canEdit) {
      AppToast.show(
        context,
        message: 'Solo el dueño o administrador pueden ver o compartir el código de invitación.',
        type: ToastType.warning,
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: _business.inviteCode));
    AppToast.show(
      context,
      message: 'Código de invitación ${_business.inviteCode} copiado al portapapeles',
      type: ToastType.info,
    );
  }

  Future<void> _openEmployeesScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeesScreen(business: _business),
      ),
    );
    _loadAllInfo();
  }

  Future<void> _switchBusiness() async {
    final user = AuthRepository.instance.currentUser;
    if (user == null) return;
    final changed = await BusinessSelectorModal.show(
      context,
      userId: user.id,
      onLogout: widget.onLogout,
    );
    if (changed == true) {
      final active = _businessRepo.currentActiveBusiness;
      if (active != null) {
        setState(() => _business = active);
        _loadAllInfo();
      }
    }
  }

  Future<void> _handleDeleteBusiness() async {
    if (_userRole != 'OWNER') {
      AppToast.showPermission(
        context,
        'Solo el dueño fundador puede eliminar o enviar a la papelera esta empresa.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('¿Mover a la Papelera?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          'El negocio "${_business.name}" se enviará a la papelera durante 7 días. Podrás restaurarlo o se eliminará de forma definitiva al finalizar el plazo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mover a Papelera'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _businessRepo.softDeleteBusiness(_business.id);
      if (mounted) {
        AppToast.show(
          context,
          message: 'Empresa enviada a la papelera',
          type: ToastType.warning,
        );
        Navigator.pop(context, true);
      }
    }
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Widget _buildRoleBadge(String role) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (role.toUpperCase()) {
      case 'OWNER':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        label = 'Dueño Fundador';
        icon = Icons.workspace_premium_rounded;
        break;
      case 'ADMIN':
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF1D4ED8);
        label = 'Administrador';
        icon = Icons.security_rounded;
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475569);
        label = 'Cajero / Ventas';
        icon = Icons.point_of_sale_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Información de tu Negocio',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Cambiar de Empresa',
            icon: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF2563EB)),
            onPressed: _switchBusiness,
          ),
        ],
      ),
      body: _isLoadingMetrics
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                MediaQuery.of(context).padding.bottom + 24,
              ),
              children: [
                // 1. Tarjeta Principal: Identidad del Negocio
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF10B981).withOpacity(0.25),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                _business.name.isNotEmpty
                                    ? _business.name[0].toUpperCase()
                                    : 'B',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _business.name,
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Moneda: ${_business.currency}',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textMuted),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _buildRoleBadge(_userRole),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Descripción o Nota Comercial
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A).withOpacity(0.5) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.notes_rounded, size: 18, color: textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                (_business.description != null && _business.description!.isNotEmpty)
                                    ? _business.description!
                                    : 'Sin descripción asignada. Añade una nota comercial o eslogan para identificar tu empresa.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: (_business.description == null || _business.description!.isEmpty)
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  color: (_business.description != null && _business.description!.isNotEmpty)
                                      ? (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155))
                                      : textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Botón para editar negocio
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _editBusinessDetails,
                          icon: Icon(
                            _canEdit ? Icons.edit_outlined : Icons.lock_outline,
                            size: 16,
                            color: _canEdit ? const Color(0xFF059669) : textMuted,
                          ),
                          label: Text(
                            _canEdit ? 'Editar Información y Moneda' : 'Solo Dueño/Admin puede editar',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _canEdit ? const Color(0xFF059669) : textMuted,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: _canEdit ? const Color(0xFF059669) : cardBorder,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 2. Tarjeta: Código de Invitación y Resumen de Equipo
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.groups_rounded, size: 20, color: Color(0xFF2563EB)),
                              SizedBox(width: 8),
                              Text(
                                'Equipo de Trabajo',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_members.length + 1} Colaboradores',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                            ),
                          ),
                        ],
                      ),
                      if (_canEdit) ...[
                        const SizedBox(height: 12),
                        // Código de Invitación (Exclusivo Dueño / Admin)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.qr_code_2_rounded, color: Color(0xFF059669), size: 22),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Código de Empresa', style: TextStyle(fontSize: 10, color: textMuted)),
                                  Text(
                                    _business.inviteCode,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Copiar Código',
                                icon: const Icon(Icons.copy_rounded, size: 20, color: Color(0xFF059669)),
                                onPressed: _copyInviteCode,
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      // Botón a Administrar / Ver Equipo
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _openEmployeesScreen,
                          icon: Icon(
                            _canEdit ? Icons.person_add_alt_1_rounded : Icons.people_outline_rounded,
                            size: 18,
                          ),
                          label: Text(_canEdit ? 'Administrar Miembros y Permisos' : 'Ver Equipo de Trabajo'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Tarjeta: Métricas y Auditoría del Negocio
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.analytics_outlined, size: 20, color: Color(0xFF059669)),
                          SizedBox(width: 8),
                          Text(
                            'Auditoría y Métricas del Negocio',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              title: 'Catálogo',
                              value: '$_productsCount',
                              subtitle: 'Productos activos',
                              icon: Icons.inventory_2_outlined,
                              color: const Color(0xFF059669),
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildMetricTile(
                              title: 'Ventas Totales',
                              value: '$_salesCount',
                              subtitle: CurrencyFormatter.format(_salesTotalAmount),
                              icon: Icons.receipt_long_outlined,
                              color: const Color(0xFF2563EB),
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              title: 'Clientes',
                              value: '$_customersCount',
                              subtitle: 'Registrados',
                              icon: Icons.people_outline_rounded,
                              color: const Color(0xFFD97706),
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildMetricTile(
                              title: 'Respaldo',
                              value: _isCloudSync ? 'En la Nube' : 'Modo Local',
                              subtitle: _isCloudSync ? 'Sincronizado con Supabase' : 'Solo en este equipo',
                              icon: _isCloudSync ? Icons.cloud_done_rounded : Icons.phone_android_rounded,
                              color: _isCloudSync ? const Color(0xFF059669) : const Color(0xFF64748B),
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Divider(height: 1, color: cardBorder),
                      const SizedBox(height: 12),
                      // Registro de Auditoría
                      Row(
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 14, color: textMuted),
                          const SizedBox(width: 6),
                          Text('Creado el: ${_formatDate(_business.createdAt)}', style: TextStyle(fontSize: 12, color: textMuted)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.fingerprint_rounded, size: 14, color: textMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'ID Auditoría: ${_business.id}',
                              style: TextStyle(fontSize: 11, color: textMuted, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 4. Zona de Gestión / Peligro
                if (_userRole == 'OWNER') ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF450A0A).withOpacity(0.2) : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Zona de Gestión de Empresa',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Si ya no necesitas esta empresa, puedes moverla a la papelera (se conservará por 7 días por seguridad).',
                          style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B)),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _handleDeleteBusiness,
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            label: const Text('Mover Empresa a la Papelera'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
