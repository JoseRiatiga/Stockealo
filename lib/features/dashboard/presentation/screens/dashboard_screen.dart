import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/data/business_repository.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/screens/business_info_screen.dart';
import '../../../business/presentation/widgets/business_selector_modal.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/presentation/screens/barcode_scanner_screen.dart';
import '../../../products/presentation/screens/product_form_screen.dart';
import '../../../reports/data/excel_export_service.dart';
import '../../../sales/presentation/widgets/quick_sale_dialog.dart';
import '../../../team/data/team_repository.dart';
import '../../../team/presentation/screens/employees_screen.dart';
import '../../../customers/presentation/screens/customers_screen.dart';
import '../../../products/presentation/widgets/restock_order_modal.dart';
import '../../../products/presentation/widgets/catalog_generator_modal.dart';
import '../../data/dashboard_repository.dart';
import '../../../../core/services/supabase_service.dart';
import '../widgets/radial_gauge_card.dart';
import '../widgets/spline_area_chart.dart';
import '../widgets/segmented_progress_card.dart';
import '../widgets/recent_transactions_card.dart';

class QuickActionDef {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  const QuickActionDef({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });
}

const List<QuickActionDef> kAvailableQuickActions = [
  QuickActionDef(
    id: 'sell',
    label: 'Vender',
    description: 'Escanear código de barras para venta rápida',
    icon: Icons.qr_code_scanner,
    color: Color(0xFF059669),
  ),
  QuickActionDef(
    id: 'add_product',
    label: 'Producto',
    description: 'Crear un nuevo producto en catálogo',
    icon: Icons.add_box_outlined,
    color: Color(0xFF2563EB),
  ),
  QuickActionDef(
    id: 'customers',
    label: 'Clientes',
    description: 'Gestionar clientes y cuentas por cobrar (fiados)',
    icon: Icons.people_outline_rounded,
    color: Color(0xFFD97706),
  ),
  QuickActionDef(
    id: 'alerts',
    label: 'Alertas',
    description: 'Productos agotados o con bajo inventario',
    icon: Icons.warning_amber_rounded,
    color: Color(0xFFDC2626),
  ),
  QuickActionDef(
    id: 'inventory',
    label: 'Inventario',
    description: 'Ir directo al catálogo completo de stock',
    icon: Icons.inventory_2_outlined,
    color: Color(0xFF0284C7),
  ),
  QuickActionDef(
    id: 'sales_history',
    label: 'Ventas',
    description: 'Historial detallado y recibos',
    icon: Icons.receipt_long_outlined,
    color: Color(0xFF0D9488),
  ),
  QuickActionDef(
    id: 'excel_export',
    label: 'Excel',
    description: 'Exportar catálogo, ventas y clientes en .xlsx',
    icon: Icons.file_download_outlined,
    color: Color(0xFF16A34A),
  ),
  QuickActionDef(
    id: 'catalog_pdf',
    label: 'Catálogo',
    description: 'Generar catálogo PDF de productos en stock',
    icon: Icons.picture_as_pdf_outlined,
    color: Color(0xFFDC2626),
  ),
  QuickActionDef(
    id: 'team',
    label: 'Equipo',
    description: 'Administrar colaboradores y roles',
    icon: Icons.group_outlined,
    color: Color(0xFF7C3AED),
  ),
  QuickActionDef(
    id: 'biz_info',
    label: 'Mi Negocio',
    description: 'Información general y métricas del comercio',
    icon: Icons.storefront_outlined,
    color: Color(0xFF475569),
  ),
];

class DashboardScreen extends StatefulWidget {
  final String userId;
  final VoidCallback onNavigateToInventory;
  final VoidCallback onNavigateToSales;
  final VoidCallback onLogout;

  const DashboardScreen({
    super.key,
    required this.userId,
    required this.onNavigateToInventory,
    required this.onNavigateToSales,
    required this.onLogout,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _dashboardRepo = DashboardRepository.instance;
  final _businessRepo = BusinessRepository.instance;
  final _authRepo = AuthRepository.instance;
  final _teamRepo = TeamRepository.instance;
  final _productRepo = ProductRepository();

  Business? _activeBusiness;
  Map<String, dynamic> _summary = {};
  List<String> _quickActionIds = List.from(DashboardRepository.defaultQuickActions);
  String _userRole = 'OWNER';
  bool _isLoading = true;
  String _selectedPeriod = 'today'; // 'today' | 'week' | 'month' | 'all'

  @override
  void initState() {
    super.initState();
    _loadData();
    _businessRepo.activeBusinessNotifier.addListener(_onBusinessChanged);
    _syncSilently();
  }

  void _onBusinessChanged() {
    if (mounted) {
      _loadData();
      _syncSilently();
    }
  }

  Future<void> _syncSilently() async {
    try {
      if (await SupabaseService.instance.isCloudSyncEnabled()) {
        final currentUser = _authRepo.currentUser;
        if (currentUser != null) {
          await SupabaseService.instance.syncFromCloud(widget.userId, currentUser.email);
          if (mounted) {
            _loadData();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _handleRefresh() async {
    try {
      if (await SupabaseService.instance.isCloudSyncEnabled()) {
        final currentUser = _authRepo.currentUser;
        if (currentUser != null) {
          await SupabaseService.instance.syncFromCloud(widget.userId, currentUser.email);
        }
      }
    } catch (e) {
      debugPrint('Error sincronizando dashboard: $e');
    }
    await _loadData();
  }

  @override
  void dispose() {
    _businessRepo.activeBusinessNotifier.removeListener(_onBusinessChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final currentUser = _authRepo.currentUser;
    _activeBusiness = await _businessRepo.getActiveBusiness(
      widget.userId,
      currentUser?.email,
    );

    if (_activeBusiness != null) {
      if (currentUser != null) {
        _userRole = await _teamRepo.getUserRoleInBusiness(
          businessId: _activeBusiness!.id,
          userId: currentUser.id,
          userEmail: currentUser.email,
        );
      }
      final data = await _dashboardRepo.getDashboardSummary(
        _activeBusiness!.id,
        period: _selectedPeriod,
      );
      final quickActions = await _dashboardRepo.getQuickActions(_activeBusiness!.id);
      if (mounted) {
        setState(() {
          _summary = data;
          _quickActionIds = quickActions;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get canViewProfits => _userRole == 'OWNER' || _userRole == 'ADMIN';

  Future<void> _exportExcelDirectly() async {
    if (_activeBusiness == null) return;
    final user = _authRepo.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF059669)),
                SizedBox(height: 18),
                Text('Generando reporte Excel (.xlsx)...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );

    bool dialogClosed = false;
    void closeDialog() {
      if (!dialogClosed && mounted) {
        dialogClosed = true;
        Navigator.pop(context);
      }
    }

    try {
      await ExcelExportService.instance.exportBusinessData(
        business: _activeBusiness!,
        userId: user.id,
        userEmail: user.email,
        onGenerated: closeDialog,
      );
      closeDialog();
      if (mounted) {
        AppToast.show(
          context,
          message: 'Reporte Excel generado y compartido con éxito',
          type: ToastType.success,
        );
      }
    } catch (e) {
      closeDialog();
      if (mounted) {
        AppToast.show(
          context,
          message: 'Error al exportar: $e',
          type: ToastType.error,
        );
      }
    }
  }

  Future<void> _executeQuickAction(String actionId) async {
    final int lowStock = _summary['lowStock'] ?? 0;
    final int outOfStock = _summary['outOfStock'] ?? 0;
    final int alertTotal = lowStock + outOfStock;

    switch (actionId) {
      case 'sell':
        _scanToSell();
        break;
      case 'add_product':
        if (_activeBusiness == null) return;
        final created = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ProductFormScreen(businessId: _activeBusiness!.id),
          ),
        );
        if (created == true) _loadData();
        break;
      case 'customers':
        if (_activeBusiness == null) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomersScreen(businessId: _activeBusiness!.id),
          ),
        );
        _loadData();
        break;
      case 'alerts':
        if (_activeBusiness != null && alertTotal > 0) {
          final user = _authRepo.currentUser;
          RestockOrderModal.show(
            context,
            business: _activeBusiness!,
            userName: user?.displayName,
          );
        } else {
          widget.onNavigateToInventory();
        }
        break;
      case 'inventory':
        widget.onNavigateToInventory();
        break;
      case 'sales_history':
        widget.onNavigateToSales();
        break;
      case 'excel_export':
        _exportExcelDirectly();
        break;
      case 'catalog_pdf':
        if (_activeBusiness != null) {
          CatalogGeneratorModal.show(
            context: context,
            business: _activeBusiness!,
          );
        }
        break;
      case 'team':
        if (_activeBusiness == null) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EmployeesScreen(business: _activeBusiness!),
          ),
        );
        _loadData();
        break;
      case 'biz_info':
        if (_activeBusiness == null) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BusinessInfoScreen(
              business: _activeBusiness!,
              onLogout: widget.onLogout,
            ),
          ),
        );
        _loadData();
        break;
    }
  }

  Future<void> _openCustomizeQuickActionsModal() async {
    if (_activeBusiness == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedIds = List<String>.from(_quickActionIds);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final availableToAdd = kAvailableQuickActions
                .where((a) => !selectedIds.contains(a.id))
                .toList();

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.82,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(ctx).padding.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Personalizar y Ordenar',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Arrastra con ☰ para fijar el orden que prefieras',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: selectedIds.length >= 2 && selectedIds.length <= 5
                              ? const Color(0xFFECFDF5)
                              : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selectedIds.length >= 2 && selectedIds.length <= 5
                                ? const Color(0xFF10B981)
                                : Colors.red,
                          ),
                        ),
                        child: Text(
                          '${selectedIds.length} / 5',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: selectedIds.length >= 2 && selectedIds.length <= 5
                                ? const Color(0xFF059669)
                                : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'ACCIONES ACTIVAS EN TU INICIO (ARRASTRA PARA ORDENAR)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Lista reordenable
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: selectedIds.length,
                            onReorder: (oldIndex, newIndex) {
                              setModalState(() {
                                if (oldIndex < newIndex) {
                                  newIndex -= 1;
                                }
                                final item = selectedIds.removeAt(oldIndex);
                                selectedIds.insert(newIndex, item);
                              });
                            },
                            itemBuilder: (context, index) {
                              final actionId = selectedIds[index];
                              final action = kAvailableQuickActions.firstWhere(
                                (a) => a.id == actionId,
                                orElse: () => kAvailableQuickActions.first,
                              );

                              return Container(
                                key: ValueKey(action.id),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF059669).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '#${index + 1}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF059669),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: action.color.withOpacity(0.12),
                                      child: Icon(action.icon, color: action.color, size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            action.label,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                          ),
                                          Text(
                                            action.description,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                                      tooltip: 'Quitar de accesos activos',
                                      onPressed: () {
                                        if (selectedIds.length > 2) {
                                          setModalState(() => selectedIds.removeAt(index));
                                        } else {
                                          AppToast.show(
                                            ctx,
                                            message: 'Debes mantener al menos 2 accesos activos',
                                            type: ToastType.warning,
                                          );
                                        }
                                      },
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 4),
                                        child: Icon(Icons.drag_handle_rounded, color: Color(0xFF64748B)),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          if (availableToAdd.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'DISPONIBLES PARA AGREGAR (+)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: availableToAdd.map((action) {
                                return ActionChip(
                                  avatar: Icon(action.icon, size: 16, color: action.color),
                                  label: Text(
                                    '+ ${action.label}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                  side: BorderSide(
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                  ),
                                  onPressed: () {
                                    setModalState(() {
                                      if (selectedIds.length < 5) {
                                        selectedIds.add(action.id);
                                      } else {
                                        AppToast.show(
                                          ctx,
                                          message: 'Máximo 5 acciones para mantener la pantalla ordenada',
                                          type: ToastType.warning,
                                        );
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx, true);
                      },
                      child: const Text('Guardar Orden y Accesos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved == true && _activeBusiness != null) {
      await _dashboardRepo.saveQuickActions(_activeBusiness!.id, selectedIds);
      setState(() {
        _quickActionIds = selectedIds;
      });
      if (mounted) {
        AppToast.show(
          context,
          message: 'Acciones rápidas guardadas con éxito',
          type: ToastType.success,
        );
      }
    }
  }

  Future<void> _scanToSell() async {
    if (_activeBusiness == null) return;
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code != null && code.isNotEmpty) {
      final product = await _productRepo.getProductByCode(code, _activeBusiness!.id);
      if (product != null && mounted) {
        final sold = await QuickSaleDialog.show(context, product);
        if (sold == true) {
          _loadData();
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se encontró ningún producto con el código "$code"'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authRepo.currentUser;
    final userName = user?.displayName ?? 'Comerciante';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 850;

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
        title: InkWell(
          onTap: () async {
            final changed = await BusinessSelectorModal.show(
              context,
              userId: widget.userId,
              onLogout: widget.onLogout,
            );
            if (changed == true) {
              _loadData();
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storefront, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _activeBusiness?.name ?? 'Stockealo',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.white),
              ],
            ),
          ),
        ),
        actions: const [],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFF059669),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
            : LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 900;
                  final double hPadding = math.max(16.0, (constraints.maxWidth - 1200) / 2);

                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      hPadding,
                      16,
                      hPadding,
                      MediaQuery.of(context).padding.bottom + 28,
                    ),
                    children: [
                      // Saludo al comerciante
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '¡Hola, $userName!',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Resumen operativo ${_selectedPeriod == "today" ? "de hoy" : (_selectedPeriod == "week" ? "de 7 días" : (_selectedPeriod == "month" ? "del mes" : "histórico"))}',
                                style: TextStyle(fontSize: 13, color: textSecondary),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.circle, color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669), size: 8),
                                const SizedBox(width: 6),
                                Text(
                                  _userRole == 'OWNER' ? 'Dueño' : (_userRole == 'ADMIN' ? 'Admin' : 'Cajero'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Selector horizontal de Periodo (Hoy, 7 Días, Este Mes, Histórico)
                      _buildPeriodSelector(),
                      const SizedBox(height: 14),

                      // Banner de Tendencia y Comparativa del Periodo
                      _buildFinancialTrendBanner(),
                      const SizedBox(height: 14),

                      // Tarjetas de Métricas del Periodo (2x2 Grid Enriquecido)
                      _buildMetricsGrid(),
                      const SizedBox(height: 20),

                      // Acciones Rápidas Personalizables
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Acciones Rápidas',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _openCustomizeQuickActionsModal,
                            icon: const Icon(Icons.tune_rounded, size: 16, color: Color(0xFF059669)),
                            label: const Text(
                              'Personalizar',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildQuickActions(),
                      const SizedBox(height: 24),

                      // Gráfico de Rendimiento (Lado a lado en Desktop, Toggle en Móvil)
                      if (isDesktop)
                        _buildDesktopCharts(isDark)
                      else
                        _buildSalesPerformanceChart(),
                      const SizedBox(height: 24),

                      // Feed de Últimas Transacciones (Nuxt Style)
                      _buildRecentTransactionsSection(),
                      const SizedBox(height: 24),

                      // Top 5 Productos Más Vendidos en el Periodo
                      _buildTopProductsSection(),
                      const SizedBox(height: 20),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final periods = [
      {'id': 'today', 'label': 'Hoy', 'icon': Icons.wb_sunny_outlined},
      {'id': 'week', 'label': '7 Días', 'icon': Icons.calendar_view_week_rounded},
      {'id': 'month', 'label': 'Este Mes', 'icon': Icons.calendar_month_rounded},
      {'id': 'all', 'label': 'Histórico', 'icon': Icons.all_inclusive_rounded},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: periods.map((p) {
          final isSelected = _selectedPeriod == p['id'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                if (_selectedPeriod != p['id']) {
                  setState(() => _selectedPeriod = p['id'] as String);
                  _loadData();
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF059669)
                      : (isDark ? const Color(0xFF1E293B) : Colors.white),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF059669)
                        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF059669).withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      p['icon'] as IconData,
                      size: 15,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      p['label'] as String,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? const Color(0xFFF1F5F9) : const Color(0xFF334155)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFinancialTrendBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double periodTotal = _summary['periodTotal'] ?? _summary['todayTotal'] ?? 0.0;
    final double? trendPercent = _summary['trendPercent'] as double?;
    final bool trendIsPositive = _summary['trendIsPositive'] == true;
    final String trendLabel = _summary['trendLabel'] ?? 'vs anterior';
    final double compareTotal = (_summary['compareTotal'] as num?)?.toDouble() ?? 0.0;

    String trendText;
    Color trendColor;
    IconData trendIcon;

    if (trendPercent != null) {
      if (trendIsPositive) {
        trendText = '+${trendPercent.toStringAsFixed(1)}% de ventas $trendLabel';
        trendColor = const Color(0xFF059669);
        trendIcon = Icons.trending_up_rounded;
      } else {
        trendText = '${trendPercent.toStringAsFixed(1)}% de ventas $trendLabel';
        trendColor = const Color(0xFFD97706);
        trendIcon = Icons.trending_down_rounded;
      }
    } else if (periodTotal > 0) {
      trendText = 'Actividad comercial registrada en este periodo';
      trendColor = const Color(0xFF059669);
      trendIcon = Icons.local_fire_department_rounded;
    } else {
      trendText = 'Sin ventas registradas en el periodo seleccionado';
      trendColor = const Color(0xFF64748B);
      trendIcon = Icons.storefront_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Icon(trendIcon, size: 18, color: trendColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              trendText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: trendColor,
              ),
            ),
          ),
          if (compareTotal > 0)
            Text(
              'Previo: ${CurrencyFormatter.format(compareTotal)}',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid() {
    final double periodTotal = _summary['periodTotal'] ?? _summary['todayTotal'] ?? 0.0;
    final double periodProfit = _summary['periodProfit'] ?? _summary['todayProfit'] ?? 0.0;
    final double profitMargin = _summary['profitMargin'] ?? 0.0;
    final double averageTicket = _summary['averageTicket'] ?? 0.0;
    final double totalDebt = _summary['totalDebt'] ?? 0.0;
    final int periodCount = _summary['periodCount'] ?? _summary['todayCount'] ?? 0;

    String salesTitle = 'Ventas de Hoy';
    String profitTitle = 'Ganancia de Hoy';
    if (_selectedPeriod == 'week') {
      salesTitle = 'Ventas (7 Días)';
      profitTitle = 'Ganancia (7 Días)';
    } else if (_selectedPeriod == 'month') {
      salesTitle = 'Ventas del Mes';
      profitTitle = 'Ganancia del Mes';
    } else if (_selectedPeriod == 'all') {
      salesTitle = 'Ventas Totales';
      profitTitle = 'Ganancia Total';
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    final int totalProducts = _summary['totalProducts'] ?? 0;
    final int lowStock = _summary['lowStock'] ?? 0;
    final int outOfStock = _summary['outOfStock'] ?? 0;
    final int alertTotal = lowStock + outOfStock;
    final double? trendPercent = _summary['trendPercent'] as double?;

    // Progreso dinámico para medidores radiales
    final salesProgress = trendPercent != null
        ? ((50 + trendPercent / 2) / 100).clamp(0.12, 1.0)
        : (periodTotal > 0 ? 0.75 : 0.08);

    final profitProgress = canViewProfits
        ? (profitMargin / 100.0).clamp(0.08, 1.0)
        : 0.5;

    final stockHealthProgress = totalProducts > 0
        ? ((totalProducts - alertTotal) / totalProducts).clamp(0.05, 1.0)
        : 1.0;

    final cardVentas = RadialGaugeCard(
      title: salesTitle,
      value: CurrencyFormatter.format(periodTotal),
      subtitle: '$periodCount ${periodCount == 1 ? "venta" : "ventas"} en periodo',
      progress: salesProgress,
      gradientColors: const [Color(0xFF06B6D4), Color(0xFF10B981)],
      icon: Icons.payments_rounded,
    );

    final cardGanancia = RadialGaugeCard(
      title: profitTitle,
      value: canViewProfits ? CurrencyFormatter.format(periodProfit) : '••••••',
      subtitle: canViewProfits
          ? (periodTotal > 0 ? 'Margen neto: ${profitMargin.toStringAsFixed(1)}%' : 'Margen neto estimado')
          : 'Restringido para cajeros',
      progress: profitProgress,
      gradientColors: const [Color(0xFFEC4899), Color(0xFF8B5CF6)],
      icon: Icons.trending_up_rounded,
    );

    final cardStock = RadialGaugeCard(
      title: 'Inventario Activo',
      value: '$totalProducts Prod.',
      subtitle: alertTotal > 0 ? '$alertTotal con stock crítico' : 'Existencias 100% al día',
      progress: stockHealthProgress,
      gradientColors: alertTotal > 0
          ? const [Color(0xFFF59E0B), Color(0xFFEF4444)]
          : const [Color(0xFF84CC16), Color(0xFF10B981)],
      icon: Icons.inventory_2_rounded,
      onTap: widget.onNavigateToInventory,
    );

    final cardCartera = SegmentedProgressCard(
      title: 'CARTERA Y TICKET',
      subtitle: 'Comportamiento comercial',
      items: [
        SegmentedBarItem(
          label: 'Ticket Promedio',
          valueText: CurrencyFormatter.format(averageTicket),
          percentage: averageTicket > 0 ? (averageTicket / (periodTotal > 0 ? periodTotal : 100000)).clamp(0.2, 0.95) : 0.1,
          color: const Color(0xFF06B6D4),
        ),
        SegmentedBarItem(
          label: 'Por Cobrar (Fiados)',
          valueText: CurrencyFormatter.format(totalDebt),
          percentage: totalDebt > 0 ? 0.65 : 0.05,
          color: const Color(0xFFF59E0B),
        ),
      ],
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: cardVentas),
          const SizedBox(width: 14),
          Expanded(child: cardGanancia),
          const SizedBox(width: 14),
          Expanded(child: cardStock),
          const SizedBox(width: 14),
          Expanded(child: cardCartera),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cardVentas),
            const SizedBox(width: 12),
            Expanded(child: cardGanancia),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: cardStock),
            const SizedBox(width: 12),
            Expanded(child: cardCartera),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    final int lowStock = _summary['lowStock'] ?? 0;
    final int outOfStock = _summary['outOfStock'] ?? 0;
    final int alertTotal = lowStock + outOfStock;

    // Filtra las definiciones que el usuario eligió y están activas en _quickActionIds
    final List<QuickActionDef> activeDefs = [];
    for (final id in _quickActionIds) {
      final found = kAvailableQuickActions.firstWhere(
        (a) => a.id == id,
        orElse: () => kAvailableQuickActions.first,
      );
      if (!activeDefs.any((a) => a.id == found.id)) {
        activeDefs.add(found);
      }
    }

    if (activeDefs.isEmpty) {
      activeDefs.addAll(kAvailableQuickActions.take(4));
    }

    return Row(
      children: activeDefs.map((action) {
        String? badge;
        if (action.id == 'alerts' && alertTotal > 0) {
          badge = '$alertTotal';
        }

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _buildActionBtn(
              label: action.label,
              icon: action.icon,
              color: action.color,
              badge: badge,
              onTap: () => _executeQuickAction(action.id),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? badge,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? color.withOpacity(0.2)
                : const Color(0xFFE2E8F0),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.15 : 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 24),
                if (badge != null)
                  Positioned(
                    right: -8,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF334155),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesPerformanceChart() {
    final List<dynamic> timelineSales = _summary['periodTimelineSales'] ?? _summary['weeklySales'] ?? [];
    final List<dynamic> categorySales = _summary['categorySales'] ?? [];

    String timelineTitle = 'Ventas de la Semana (7 días)';
    if (_selectedPeriod == 'today') {
      timelineTitle = 'Ventas de Hoy por Horario';
    } else if (_selectedPeriod == 'month') {
      timelineTitle = 'Ventas del Mes por Semanas';
    } else if (_selectedPeriod == 'all') {
      timelineTitle = 'Ventas Históricas por Meses';
    }

    final splineData = timelineSales.map((item) {
      return {
        'label': item['day'] as String,
        'value': (item['total'] as num).toDouble(),
      };
    }).toList();

    final categoryItems = categorySales.take(4).map((cat) {
      final colors = [
        const Color(0xFF06B6D4),
        const Color(0xFFEC4899),
        const Color(0xFF10B981),
        const Color(0xFFF59E0B),
      ];
      final idx = categorySales.indexOf(cat) % colors.length;
      final pct = (cat['percentage'] as num?)?.toDouble() ?? 0.0;
      return SegmentedBarItem(
        label: cat['name'] as String,
        valueText: '${pct.toStringAsFixed(1)}%',
        percentage: pct / 100.0,
        color: colors[idx],
      );
    }).toList();

    return Column(
      children: [
        SplineAreaChart(
          title: timelineTitle,
          subtitle: 'Curva continua de rendimiento operativo',
          data: splineData,
          height: 160,
          primaryColor: const Color(0xFF06B6D4),
          secondaryColor: const Color(0xFFEC4899),
        ),
        const SizedBox(height: 16),
        SegmentedProgressCard(
          title: 'PARTICIPACIÓN POR CATEGORÍA',
          subtitle: 'Distribución en el periodo',
          items: categoryItems.isNotEmpty
              ? categoryItems
              : [
                  const SegmentedBarItem(
                    label: 'General',
                    valueText: '100%',
                    percentage: 1.0,
                    color: Color(0xFF10B981),
                  )
                ],
        ),
      ],
    );
  }

  Widget _buildDesktopCharts(bool isDark) {
    final List<dynamic> timelineSales = _summary['periodTimelineSales'] ?? _summary['weeklySales'] ?? [];
    final List<dynamic> categorySales = _summary['categorySales'] ?? [];

    String timelineTitle = 'Ventas de la Semana (7 días)';
    if (_selectedPeriod == 'today') {
      timelineTitle = 'Ventas de Hoy por Horario';
    } else if (_selectedPeriod == 'month') {
      timelineTitle = 'Ventas del Mes por Semanas';
    } else if (_selectedPeriod == 'all') {
      timelineTitle = 'Ventas Históricas por Meses';
    }

    final splineData = timelineSales.map((item) {
      return {
        'label': item['day'] as String,
        'value': (item['total'] as num).toDouble(),
      };
    }).toList();

    final categoryItems = categorySales.take(5).map((cat) {
      final colors = [
        const Color(0xFF06B6D4),
        const Color(0xFFEC4899),
        const Color(0xFF10B981),
        const Color(0xFFF59E0B),
        const Color(0xFF8B5CF6),
      ];
      final idx = categorySales.indexOf(cat) % colors.length;
      final pct = (cat['percentage'] as num?)?.toDouble() ?? 0.0;
      return SegmentedBarItem(
        label: cat['name'] as String,
        valueText: '${pct.toStringAsFixed(1)}%',
        percentage: pct / 100.0,
        color: colors[idx],
      );
    }).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: SplineAreaChart(
            title: timelineTitle,
            subtitle: 'Curva continua de rendimiento operativo',
            data: splineData,
            height: 190,
            primaryColor: const Color(0xFF06B6D4),
            secondaryColor: const Color(0xFFEC4899),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 4,
          child: SegmentedProgressCard(
            title: 'PARTICIPACIÓN POR CATEGORÍA',
            subtitle: 'Distribución porcentual en el periodo',
            items: categoryItems.isNotEmpty
                ? categoryItems
                : [
                    const SegmentedBarItem(
                      label: 'General',
                      valueText: '100%',
                      percentage: 1.0,
                      color: Color(0xFF10B981),
                    )
                  ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentTransactionsSection() {
    final List<dynamic> rawTxs = _summary['recentTransactions'] ?? [];
    final List<TransactionItem> items = rawTxs.map((t) {
      DateTime dt;
      try {
        dt = DateTime.parse(t['date']);
      } catch (_) {
        dt = DateTime.now();
      }
      return TransactionItem(
        id: t['id'] as String? ?? '',
        title: t['title'] as String? ?? 'Venta',
        subtitle: t['subtitle'] as String? ?? '',
        amount: (t['amount'] as num?)?.toDouble() ?? 0.0,
        paymentMethod: t['payment_method'] as String? ?? 'EFECTIVO',
        date: dt,
      );
    }).toList();

    return RecentTransactionsCard(
      transactions: items,
      onSeeAll: widget.onNavigateToSales,
    );
  }

  Widget _buildTopProductsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<dynamic> topProducts = _summary['topProducts'] ?? [];

    if (topProducts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
        child: const Center(
          child: Text(
            'Aún no hay ventas registradas para generar el Top de productos.',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Top 5 Productos Más Vendidos',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                ),
              ),
              Text(
                'Ventas & Ingresos',
                style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...topProducts.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final share = (item['share'] as num?)?.toDouble() ?? 0.0;
            final revenue = (item['revenue'] as num?)?.toDouble() ?? 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildRankingBadge(idx, isDark),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item['name'] as String,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${item['qty']} un.',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${CurrencyFormatter.format(revenue)})',
                        style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: share.clamp(0.05, 1.0),
                      minHeight: 5,
                      backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRankingBadge(int rank, bool isDark) {
    Color badgeColor;
    Widget child;

    switch (rank) {
      case 0: // 1er Lugar - Oro
        badgeColor = const Color(0xFFF59E0B);
        child = const Icon(Icons.emoji_events_rounded, size: 13, color: Colors.white);
        break;
      case 1: // 2do Lugar - Plata
        badgeColor = const Color(0xFF94A3B8);
        child = const Icon(Icons.military_tech_rounded, size: 14, color: Colors.white);
        break;
      case 2: // 3er Lugar - Bronce
        badgeColor = const Color(0xFFD97706);
        child = const Icon(Icons.military_tech_outlined, size: 14, color: Colors.white);
        break;
      default: // 4to y 5to
        badgeColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
        final textColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
        child = Text(
          '#${rank + 1}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        );
    }

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: badgeColor,
        shape: BoxShape.circle,
        boxShadow: rank < 3
            ? [
                BoxShadow(
                  color: badgeColor.withOpacity(0.35),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                )
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

