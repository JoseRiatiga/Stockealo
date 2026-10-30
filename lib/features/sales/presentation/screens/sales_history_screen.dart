import '../widgets/sales_summary_card.dart';
import '../widgets/sales_quick_modules_bar.dart';
import '../widgets/sale_card.dart';
import '../../../business/presentation/active_business_scope.dart';
import '../../../../core/services/notification_service.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/sales_repository.dart';
import '../../../business/data/business_repository.dart';
import '../../../auth/data/auth_repository.dart';
import '../../models/sale.dart';
import '../widgets/quick_sale_dialog.dart';
import '../../../customers/presentation/screens/customers_screen.dart';
import '../../../reports/data/excel_export_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../team/data/team_repository.dart';
import '../../../../core/widgets/stocky_empty_state.dart';
import '../../../cash/presentation/screens/cash_register_screen.dart';

class SalesHistoryScreen extends StatefulWidget {
  final String? businessId;
  final String? userRole;

  const SalesHistoryScreen({super.key, this.businessId, this.userRole});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> with ActiveBusinessAware {
  @override
  void onActiveBusinessChanged() => _onBusinessChanged();

  final _salesRepo = SalesRepository();
  final _businessRepo = BusinessRepository.instance;

  List<Sale> _sales = [];
  Map<String, dynamic> _summary = {};
  bool _isLoading = true;
  String? _userRole;

  String get _effectiveRole => widget.userRole ?? _userRole ?? 'OWNER';
  bool get canViewCosts => _effectiveRole == 'OWNER' || _effectiveRole == 'ADMIN';
  bool get canCancelSale => _effectiveRole == 'OWNER' || _effectiveRole == 'ADMIN';

  // Filtros y paginación
  String _selectedDateFilter = 'all'; // 'all', 'today', '7days', 'month', 'custom'
  DateTimeRange? _customDateRange;
  String _selectedPaymentMethod = 'ALL'; // 'ALL', 'EFECTIVO', 'TRANSFERENCIA', 'FIADO'
  int _currentPage = 1;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.remoteSalesVersion.addListener(_onRemoteSales);
    _loadSales();
    _syncSilently();
  }

  /// Ventas hechas en otro dispositivo, ya descargadas: solo recargar
  void _onRemoteSales() {
    if (mounted) _loadSales();
  }

  void _onBusinessChanged() {
    if (mounted) {
      _loadSales();
      _syncSilently();
    }
  }

  Future<void> _syncSilently() async {
    try {
      if (await SupabaseService.instance.isCloudSyncEnabled()) {
        final user = AuthRepository.instance.currentUser;
        if (user != null) {
          await SupabaseService.instance.syncFromCloud(user.id, user.email);
          if (mounted) {
            _loadSales();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _handleRefresh() async {
    try {
      if (await SupabaseService.instance.isCloudSyncEnabled()) {
        final user = AuthRepository.instance.currentUser;
        if (user != null) {
          await SupabaseService.instance.syncFromCloud(user.id, user.email);
        }
      }
    } catch (e) {
      debugPrint('Error sincronizando historial de ventas: $e');
    }
    await _loadSales();
  }

  @override
  void dispose() {
    NotificationService.instance.remoteSalesVersion.removeListener(_onRemoteSales);
    super.dispose();
  }

  Future<void> _loadSales() async {
    setState(() => _isLoading = true);
    var bizId = widget.businessId ?? ActiveBusinessScope.read(context)?.id;
    if (bizId == null) {
      final user = AuthRepository.instance.currentUser;
      if (user != null) {
        final biz = await _businessRepo.getActiveBusiness(user.id, user.email);
        bizId = biz?.id;
      }
    }
    if (bizId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final sales = await _salesRepo.getSales(businessId: bizId);
    final summary = await _salesRepo.getTodaySummary(bizId);

    if (widget.userRole == null) {
      final user = AuthRepository.instance.currentUser;
      if (user != null) {
        try {
          _userRole = await TeamRepository.instance.getUserRoleInBusiness(
            businessId: bizId,
            userId: user.id,
            userEmail: user.email,
          );
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        _sales = sales;
        _summary = summary;
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelSale(Sale sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Anular esta venta?'),
        content: Text(
          'Se repondrán ${sale.quantity} unidades de "${sale.productName}" al inventario y se descontará del reporte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, mantener'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sí, anular venta'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _salesRepo.cancelSale(sale);
      _loadSales();
      if (mounted) {
        AppToast.showSuccess(
          context,
          'Venta anulada y ${sale.quantity} unid. devueltas al inventario.',
          title: 'Venta Anulada',
        );
      }
    }
  }

  Future<void> _navigateToCustomers() async {
    var bizId = widget.businessId ?? ActiveBusinessScope.read(context)?.id;
    if (bizId == null) {
      final user = AuthRepository.instance.currentUser;
      if (user != null) {
        final biz = await _businessRepo.getActiveBusiness(user.id, user.email);
        bizId = biz?.id;
      }
    }
    if (bizId != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CustomersScreen(businessId: bizId!),
        ),
      );
      _loadSales();
    }
  }

  Future<void> _exportToExcel() async {
    final biz = ActiveBusinessScope.read(context);
    if (biz == null) {
      AppToast.showWarning(context, 'No hay una empresa activa seleccionada.');
      return;
    }

    final user = AuthRepository.instance.currentUser;
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
                Text(
                  'Generando Excel (.xlsx)...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 6),
                Text(
                  'Inventario, Ventas y Clientes',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
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
        business: biz,
        userId: user.id,
        userEmail: user.email,
        onGenerated: closeDialog,
      );
      closeDialog();
      if (mounted) {
        AppToast.showSuccess(
          context,
          'El archivo Excel (.xlsx) ha sido generado y compartido.',
          title: 'Exportación Exitosa',
        );
      }
    } catch (e) {
      closeDialog();
      if (mounted) {
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        AppToast.showError(context, errorMsg);
      }
    }
  }

  Future<void> _openCashRegister() async {
    final bizId = widget.businessId ?? ActiveBusinessScope.read(context)?.id;
    if (bizId == null) return;
    final user = AuthRepository.instance.currentUser;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CashRegisterScreen(
          businessId: bizId,
          userName: user?.displayName ?? 'Vendedor',
        ),
      ),
    );
  }

  Future<void> _openQuickSale() async {
    await QuickSaleDialog.show(context);
    if (mounted) {
      _loadSales();
    }
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? const ColorScheme.dark(
                    primary: Color(0xFF8B5CF6),
                    onPrimary: Colors.white,
                    surface: Color(0xFF131126),
                    onSurface: Color(0xFFF8FAFC),
                  )
                : const ColorScheme.light(
                    primary: Color(0xFF8B5CF6),
                    onPrimary: Colors.white,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedDateFilter = 'custom';
        _currentPage = 1;
      });
    }
  }

  List<Sale> get _filteredSales {
    return _sales.where((sale) {
      // Filtro de método de pago
      if (_selectedPaymentMethod != 'ALL') {
        if (sale.paymentMethod != _selectedPaymentMethod) return false;
      }

      // Filtro de fecha
      final now = DateTime.now();
      switch (_selectedDateFilter) {
        case 'today':
          if (sale.date.year != now.year ||
              sale.date.month != now.month ||
              sale.date.day != now.day) {
            return false;
          }
          break;
        case '7days':
          final sevenDaysAgo = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));
          if (sale.date.isBefore(sevenDaysAgo)) return false;
          break;
        case 'month':
          if (sale.date.year != now.year || sale.date.month != now.month) return false;
          break;
        case 'custom':
          if (_customDateRange != null) {
            final start = DateTime(
              _customDateRange!.start.year,
              _customDateRange!.start.month,
              _customDateRange!.start.day,
            );
            final end = DateTime(
              _customDateRange!.end.year,
              _customDateRange!.end.month,
              _customDateRange!.end.day,
              23,
              59,
              59,
            );
            if (sale.date.isBefore(start) || sale.date.isAfter(end)) return false;
          }
          break;
        case 'all':
        default:
          break;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 850;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredSales;
    final totalPages = filtered.isEmpty ? 1 : ((filtered.length - 1) ~/ _pageSize) + 1;
    final currentPageClamped = _currentPage.clamp(1, totalPages);
    final pagedSales = filtered
        .skip((currentPageClamped - 1) * _pageSize)
        .take(_pageSize)
        .toList();

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: const Text('Historial de Ventas'),
              actions: [
                IconButton(
                  onPressed: _openCashRegister,
                  icon: const Icon(Icons.point_of_sale_rounded, color: Colors.white),
                  tooltip: 'Arqueo de caja',
                ),
                IconButton(
                  onPressed: _openQuickSale,
                  icon: const Icon(Icons.add_shopping_cart_rounded, color: Color(0xFF8B5CF6)),
                  tooltip: 'Registrar Venta',
                ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFF8B5CF6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double hPadding = math.max(16.0, (constraints.maxWidth - 1000) / 2);

            return CustomScrollView(
              slivers: [
                // Cabecera Pro en Desktop con botón Registrar Venta
                if (isDesktop)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(hPadding + 16, 20, hPadding + 16, 4),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Historial de Transacciones',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Monitoreo de ingresos, arqueo y detalle de ventas',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: _openCashRegister,
                            icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                            label: const Text('Arqueo de caja'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF059669),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: _openQuickSale,
                            icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                            label: const Text(
                              '+ Registrar Venta',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B5CF6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Resumen de Métricas de Ventas de Hoy
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  sliver: SliverToBoxAdapter(
                    child: SalesSummaryCard(summary: _summary, sales: _sales, showProfit: canViewCosts),
                  ),
                ),

                // Accesos Rápidos Destacados: Clientes / Fiados y Exportación Excel
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  sliver: SliverToBoxAdapter(
                    child: SalesQuickModulesBar(
                      businessId: widget.businessId,
                      onCustomers: _navigateToCustomers,
                      onExportExcel: _exportToExcel,
                    ),
                  ),
                ),

                // Barra de Filtros interactiva (Fecha y Método de Pago)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  sliver: SliverToBoxAdapter(
                    child: _buildFiltersBar(isDark),
                  ),
                ),

                // Encabezado de la lista con métrica filtrada
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hPadding + 20, 14, hPadding + 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Ventas Registradas',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF18152F) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Text(
                                '${filtered.length}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (totalPages > 1)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: currentPageClamped > 1
                                    ? () => setState(() => _currentPage--)
                                    : null,
                                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                                color: const Color(0xFF8B5CF6),
                                disabledColor: isDark ? const Color(0xFF332D63) : const Color(0xFFCBD5E1),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$currentPageClamped / $totalPages',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF8B5CF6),
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: currentPageClamped < totalPages
                                    ? () => setState(() => _currentPage++)
                                    : null,
                                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                                color: const Color(0xFF8B5CF6),
                                disabledColor: isDark ? const Color(0xFF332D63) : const Color(0xFFCBD5E1),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),

                // Lista de ventas paginada
                if (_isLoading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6))),
                  )
                else if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: StockyEmptyState(
                      title: _sales.isEmpty ? 'Aún no hay ventas registradas' : 'Sin ventas con estos filtros',
                      message: _sales.isEmpty
                          ? 'Cuando descuentes productos de stock por venta, aparecerán detallados aquí en tiempo real.'
                          : 'Prueba cambiando el rango de fechas o el método de pago seleccionado.',
                      actionLabel: _sales.isNotEmpty ? 'Limpiar Filtros' : null,
                      onAction: _sales.isNotEmpty
                          ? () {
                              setState(() {
                                _selectedDateFilter = 'all';
                                _selectedPaymentMethod = 'ALL';
                                _customDateRange = null;
                                _currentPage = 1;
                              });
                            }
                          : null,
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final sale = pagedSales[index];
                          return SaleCard(
                            sale: sale,
                            showProfit: canViewCosts,
                            onCancel: canCancelSale ? () => _cancelSale(sale) : null,
                          );
                        },
                        childCount: pagedSales.length,
                      ),
                    ),
                  ),

                  // Controles de Paginación
                  if (totalPages > 1)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(hPadding + 16, 16, hPadding + 16, 8),
                      sliver: SliverToBoxAdapter(
                        child: _buildPaginationBar(
                          isDark: isDark,
                          currentPage: currentPageClamped,
                          totalPages: totalPages,
                          totalItems: filtered.length,
                        ),
                      ),
                    ),
                ],

                SliverToBoxAdapter(
                  child: SizedBox(height: MediaQuery.of(context).padding.bottom + 30),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFiltersBar(bool isDark) {
    final bool hasActiveFilter = _selectedDateFilter != 'all' || _selectedPaymentMethod != 'ALL';

    String dateLabel;
    switch (_selectedDateFilter) {
      case 'today':
        dateLabel = 'Hoy';
        break;
      case '7days':
        dateLabel = '7 Días';
        break;
      case 'month':
        dateLabel = 'Este Mes';
        break;
      case 'custom':
        dateLabel = _customDateRange != null
            ? '${DateFormat('dd/MM').format(_customDateRange!.start)} - ${DateFormat('dd/MM').format(_customDateRange!.end)}'
            : 'Rango';
        break;
      case 'all':
      default:
        dateLabel = 'Todas las fechas';
    }

    String methodLabel;
    switch (_selectedPaymentMethod) {
      case 'EFECTIVO':
        methodLabel = '💵 Efectivo';
        break;
      case 'TRANSFERENCIA':
        methodLabel = '🏦 Transferencia';
        break;
      case 'FIADO':
        methodLabel = '📝 Fiado';
        break;
      case 'ALL':
      default:
        methodLabel = 'Todos los métodos';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131126) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          // Filtro de Fecha Popup
          Expanded(
            child: PopupMenuButton<String>(
              tooltip: 'Filtrar por fecha',
              initialValue: _selectedDateFilter,
              onSelected: (val) {
                if (val == 'custom') {
                  _pickCustomDateRange();
                } else {
                  setState(() {
                    _selectedDateFilter = val;
                    _currentPage = 1;
                  });
                }
              },
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              color: isDark ? const Color(0xFF18152F) : Colors.white,
              itemBuilder: (ctx) => [
                _buildPopupItem('all', '📅 Todas las fechas', _selectedDateFilter == 'all', isDark),
                _buildPopupItem('today', '☀️ Hoy', _selectedDateFilter == 'today', isDark),
                _buildPopupItem('7days', '⏱️ Últimos 7 días', _selectedDateFilter == '7days', isDark),
                _buildPopupItem('month', '📆 Este mes', _selectedDateFilter == 'month', isDark),
                _buildPopupItem('custom', '🗓️ Rango personalizado...', _selectedDateFilter == 'custom', isDark),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedDateFilter != 'all'
                      ? const Color(0xFF8B5CF6).withOpacity(0.12)
                      : (isDark ? const Color(0xFF18152F) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedDateFilter != 'all'
                        ? const Color(0xFF8B5CF6)
                        : (isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: _selectedDateFilter != 'all'
                          ? const Color(0xFF8B5CF6)
                          : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          dateLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _selectedDateFilter != 'all' ? FontWeight.bold : FontWeight.w500,
                            color: _selectedDateFilter != 'all'
                                ? const Color(0xFF8B5CF6)
                                : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 18,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Filtro de Método de Pago Popup
          Expanded(
            child: PopupMenuButton<String>(
              tooltip: 'Filtrar por método',
              initialValue: _selectedPaymentMethod,
              onSelected: (val) {
                setState(() {
                  _selectedPaymentMethod = val;
                  _currentPage = 1;
                });
              },
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              color: isDark ? const Color(0xFF18152F) : Colors.white,
              itemBuilder: (ctx) => [
                _buildPopupItem('ALL', '💳 Todos los métodos', _selectedPaymentMethod == 'ALL', isDark),
                _buildPopupItem('EFECTIVO', '💵 Efectivo', _selectedPaymentMethod == 'EFECTIVO', isDark),
                _buildPopupItem('TRANSFERENCIA', '🏦 Transferencia', _selectedPaymentMethod == 'TRANSFERENCIA', isDark),
                _buildPopupItem('FIADO', '📝 Venta a Fiado', _selectedPaymentMethod == 'FIADO', isDark),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedPaymentMethod != 'ALL'
                      ? const Color(0xFF059669).withOpacity(0.12)
                      : (isDark ? const Color(0xFF18152F) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedPaymentMethod != 'ALL'
                        ? const Color(0xFF059669)
                        : (isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      size: 14,
                      color: _selectedPaymentMethod != 'ALL'
                          ? const Color(0xFF059669)
                          : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          methodLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _selectedPaymentMethod != 'ALL' ? FontWeight.bold : FontWeight.w500,
                            color: _selectedPaymentMethod != 'ALL'
                                ? const Color(0xFF059669)
                                : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 18,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Botón limpiar filtros si hay alguno activo
          if (hasActiveFilter) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () {
                setState(() {
                  _selectedDateFilter = 'all';
                  _selectedPaymentMethod = 'ALL';
                  _customDateRange = null;
                  _currentPage = 1;
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFEF4444)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(String value, String text, bool isSelected, bool isDark) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? const Color(0xFF8B5CF6)
                    : (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A)),
              ),
            ),
          ),
          if (isSelected)
            const Icon(Icons.check_rounded, size: 16, color: Color(0xFF8B5CF6)),
        ],
      ),
    );
  }

  Widget _buildPaginationBar({
    required bool isDark,
    required int currentPage,
    required int totalPages,
    required int totalItems,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131126) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Página $currentPage de $totalPages ($totalItems transacciones)',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: currentPage > 1
                    ? () => setState(() => _currentPage--)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
                iconSize: 22,
                tooltip: 'Página anterior',
                color: const Color(0xFF8B5CF6),
                disabledColor: isDark ? const Color(0xFF332D63) : const Color(0xFFCBD5E1),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: currentPage < totalPages
                    ? () => setState(() => _currentPage++)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
                iconSize: 22,
                tooltip: 'Página siguiente',
                color: const Color(0xFF8B5CF6),
                disabledColor: isDark ? const Color(0xFF332D63) : const Color(0xFFCBD5E1),
              ),
            ],
          ),
        ],
      ),
    );
  }

}
