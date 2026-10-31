import '../../../../core/design/skeleton.dart';
import '../../../reports/presentation/screens/profit_report_screen.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../business/presentation/business_identity.dart';
import '../widgets/quick_actions_customizer.dart';
import '../widgets/dashboard_desktop_charts.dart';
import '../widgets/top_products_section.dart';
import '../widgets/dashboard_metrics_grid.dart';
import '../widgets/quick_actions_catalog.dart';
import '../../../business/presentation/active_business_scope.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
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
import '../widgets/spline_area_chart.dart';
import '../widgets/segmented_progress_card.dart';
import '../widgets/recent_transactions_card.dart';
import '../../../../core/services/data_events.dart';
import '../../../../core/services/notification_service.dart';
import '../../../home/presentation/widgets/notifications_modal.dart';

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

class _DashboardScreenState extends State<DashboardScreen> with ActiveBusinessAware {
  @override
  void onActiveBusinessChanged() => _onBusinessChanged();

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
    NotificationService.instance.remoteSalesVersion.addListener(_onRemoteSales);
    DataEvents.instance.salesVersion.addListener(_onRemoteSales);
    _syncSilently();
  }

  /// Ventas hechas en otro dispositivo, ya descargadas: solo recargar
  void _onRemoteSales() {
    if (mounted) _loadData();
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
    NotificationService.instance.remoteSalesVersion.removeListener(_onRemoteSales);
    DataEvents.instance.salesVersion.removeListener(_onRemoteSales);
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

  Future<void> _openCustomizeQuickActionsModal() async {
    if (_activeBusiness == null) return;
    final selectedIds = await QuickActionsCustomizer.show(context, current: _quickActionIds);
    if (selectedIds != null && _activeBusiness != null) {
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

  Future<void> _executeQuickAction(String actionId) async {
    final int lowStock = _summary['lowStock'] ?? 0;
    final int outOfStock = _summary['outOfStock'] ?? 0;
    final int alertTotal = lowStock + outOfStock;

    switch (actionId) {
      case 'sell':
        _openQuickSale();
        break;
      case 'scan':
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
      case 'profit_report':
        // Muestra costos y márgenes: el cajero no lo ve
        if (!canViewProfits) {
          AppToast.showPermission(context, 'Los reportes de ganancias solo los ven el dueño y los administradores.');
        } else if (_activeBusiness != null) {
          ProfitReportScreen.open(context, _activeBusiness!);
        }
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

  Future<void> _openQuickSale() async {
    final sold = await QuickSaleDialog.show(context);
    if (sold == true) {
      _loadData();
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
    final c = context.colors;
    final user = _authRepo.currentUser;
    final userName = user?.displayName ?? 'Comerciante';
    final isDesktop = MediaQuery.of(context).size.width >= 850;

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
                  if (changed == true) _loadData();
                },
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_activeBusiness != null) ...[
                        BusinessAvatar(business: _activeBusiness!, size: 26),
                        const SizedBox(width: AppSpace.sm),
                      ],
                      Flexible(
                        child: Text(
                          _activeBusiness?.name ?? 'Stockealo',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                        ),
                      ),
                      const Icon(Icons.expand_more_rounded),
                    ],
                  ),
                ),
              ),
              actions: [
                AnimatedBuilder(
                  animation: NotificationService.instance,
                  builder: (context, _) {
                    final unread = NotificationService.instance.unreadCount;
                    return IconButton(
                      tooltip: 'Notificaciones',
                      onPressed: () => NotificationsModal.show(
                        context: context,
                        onNavigateToTab: (index) {
                          if (index == 1) widget.onNavigateToInventory();
                          if (index == 2) widget.onNavigateToSales();
                        },
                      ),
                      icon: Badge(
                        isLabelVisible: unread > 0,
                        label: Text('$unread'),
                        backgroundColor: c.danger,
                        child: const Icon(Icons.notifications_none_rounded),
                      ),
                    );
                  },
                ),
                const SizedBox(width: AppSpace.xs),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final double hPadding = math.max(AppSpace.lg, (constraints.maxWidth - 1200) / 2);

            if (_isLoading) {
              return ListView(
                padding: EdgeInsets.fromLTRB(hPadding, AppSpace.lg, hPadding, 0),
                children: const [
                  SkeletonBox(width: 180, height: 22),
                  SizedBox(height: AppSpace.lg),
                  SkeletonBox(height: 40, radius: 20),
                  SizedBox(height: AppSpace.lg),
                  SkeletonBox(height: 120, radius: 16),
                  SizedBox(height: AppSpace.md),
                  SkeletonBox(height: 120, radius: 16),
                ],
              );
            }

            return ListView(
              padding: EdgeInsets.fromLTRB(hPadding, AppSpace.lg, hPadding, MediaQuery.of(context).padding.bottom + 120),
              children: [
                // Saludo
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hola, $userName', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.ink)),
                          const SizedBox(height: 2),
                          Text(_trendText(), style: TextStyle(fontSize: 13.5, color: _trendColor())),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Text(
                        _userRole == 'OWNER' ? 'Dueño' : (_userRole == 'ADMIN' ? 'Administrador' : 'Cajero'),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.inkMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),

                _buildPeriodSelector(),
                const SizedBox(height: AppSpace.lg),

                DashboardMetricsGrid(
                  summary: _summary,
                  period: _selectedPeriod,
                  showProfit: canViewProfits,
                  onInventoryTap: widget.onNavigateToInventory,
                  onDebtsTap: () => _executeQuickAction('customers'),
                ),
                const SizedBox(height: AppSpace.xl),

                // Acciones rápidas personalizables
                Row(
                  children: [
                    Expanded(child: Text('Acciones rápidas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink))),
                    TextButton.icon(
                      onPressed: _openCustomizeQuickActionsModal,
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Personalizar'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                _buildQuickActions(),
                const SizedBox(height: AppSpace.xl),

                if (isWide)
                  DashboardDesktopCharts(summary: _summary, period: _selectedPeriod)
                else
                  _buildSalesPerformanceChart(),
                const SizedBox(height: AppSpace.xl),

                _buildRecentTransactionsSection(),
                const SizedBox(height: AppSpace.xl),

                TopProductsSection(summary: _summary),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Comparación con el periodo anterior, en una frase
  String _trendText() {
    final double periodTotal = _summary['periodTotal'] ?? _summary['todayTotal'] ?? 0.0;
    final double? trendPercent = _summary['trendPercent'] as double?;
    final String trendLabel = _summary['trendLabel'] ?? 'vs anterior';
    if (trendPercent != null) {
      final sign = trendPercent > 0 ? '+' : '';
      return '$sign${trendPercent.toStringAsFixed(0)}% en ventas $trendLabel';
    }
    return periodTotal > 0 ? 'Así va tu negocio' : 'Aún no hay ventas en este periodo';
  }

  Color _trendColor() {
    final c = context.colors;
    final double? trendPercent = _summary['trendPercent'] as double?;
    if (trendPercent == null) return c.inkMuted;
    return _summary['trendIsPositive'] == true ? c.success : c.warning;
  }

  Widget _buildPeriodSelector() {
    final c = context.colors;
    const periods = {'today': 'Hoy', 'week': '7 días', 'month': 'Este mes', 'all': 'Todo'};
    return SegmentedButton<String>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: c.accent,
        selectedForegroundColor: c.onAccent,
        backgroundColor: c.surface,
        foregroundColor: c.ink,
        side: BorderSide(color: c.line),
      ),
      segments: [
        for (final entry in periods.entries) ButtonSegment(value: entry.key, label: Text(entry.value)),
      ],
      selected: {_selectedPeriod},
      onSelectionChanged: (s) {
        if (s.first == _selectedPeriod) return;
        setState(() => _selectedPeriod = s.first);
        _loadData();
      },
    );
  }

  Widget _buildQuickActions() {
    final c = context.colors;
    final int alertTotal = (_summary['lowStock'] ?? 0) + (_summary['outOfStock'] ?? 0);

    final List<QuickActionDef> activeDefs = [];
    for (final id in _quickActionIds) {
      final found = kAvailableQuickActions.firstWhere((a) => a.id == id, orElse: () => kAvailableQuickActions.first);
      if (!activeDefs.any((a) => a.id == found.id)) activeDefs.add(found);
    }
    if (activeDefs.isEmpty) activeDefs.addAll(kAvailableQuickActions.take(4));

    return Row(
      children: [
        for (final action in activeDefs)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Material(
                color: c.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  side: BorderSide(color: c.line),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  onTap: () => _executeQuickAction(action.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.md, horizontal: AppSpace.xs),
                    child: Column(
                      children: [
                        Badge(
                          isLabelVisible: action.id == 'alerts' && alertTotal > 0,
                          label: Text('$alertTotal'),
                          backgroundColor: c.danger,
                          child: Icon(action.icon, color: c.accent, size: 24),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          action.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.ink),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSalesPerformanceChart() {
    final List<dynamic> timelineSales = _summary['periodTimelineSales'] ?? _summary['weeklySales'] ?? [];
    final List<dynamic> categorySales = _summary['categorySales'] ?? [];

    String timelineTitle = 'Ventas de los últimos 7 días';
    if (_selectedPeriod == 'today') {
      timelineTitle = 'Ventas de hoy por hora';
    } else if (_selectedPeriod == 'month') {
      timelineTitle = 'Ventas del mes por semana';
    } else if (_selectedPeriod == 'all') {
      timelineTitle = 'Ventas por mes';
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
          subtitle: 'Cómo se reparten tus ventas en el tiempo',
          data: splineData,
          height: 160,
          primaryColor: context.colors.accent,
          secondaryColor: context.colors.info,
        ),
        const SizedBox(height: 16),
        SegmentedProgressCard(
          title: 'Ventas por categoría',
          subtitle: 'Qué categorías venden más',
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

}

