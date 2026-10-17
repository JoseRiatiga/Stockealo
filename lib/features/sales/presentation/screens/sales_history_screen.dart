import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/sales_repository.dart';
import '../../../business/data/business_repository.dart';
import '../../../auth/data/auth_repository.dart';
import '../../models/sale.dart';
import '../widgets/digital_ticket_modal.dart';
import '../widgets/quick_sale_dialog.dart';
import '../../../customers/presentation/screens/customers_screen.dart';
import '../../../reports/data/excel_export_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../../team/data/team_repository.dart';
import '../../../../core/widgets/stocky_empty_state.dart';
import '../widgets/quotations_list_modal.dart';
import '../../../dashboard/presentation/widgets/stocky_face_button.dart';

class SalesHistoryScreen extends StatefulWidget {
  final String? businessId;
  final String? userRole;

  const SalesHistoryScreen({super.key, this.businessId, this.userRole});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
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
    _businessRepo.activeBusinessNotifier.addListener(_onBusinessChanged);
    _loadSales();
    _syncSilently();
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
    _businessRepo.activeBusinessNotifier.removeListener(_onBusinessChanged);
    super.dispose();
  }

  Future<void> _loadSales() async {
    setState(() => _isLoading = true);
    var bizId = widget.businessId ?? _businessRepo.currentActiveBusiness?.id;
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
    var bizId = widget.businessId ?? _businessRepo.currentActiveBusiness?.id;
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
    final biz = _businessRepo.currentActiveBusiness;
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
                StockyFaceButton(businessId: widget.businessId ?? _businessRepo.currentActiveBusiness?.id),
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
                    child: _buildSummaryCard(),
                  ),
                ),

                // Accesos Rápidos Destacados: Clientes / Fiados y Exportación Excel
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  sliver: SliverToBoxAdapter(
                    child: _buildQuickModulesBar(),
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
                          return _buildSaleCard(sale);
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

  Widget _buildQuickModulesBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          // Tarjeta Clientes y Fiados
          Expanded(
            child: InkWell(
              onTap: _navigateToCustomers,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131127) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xFF26214A) : const Color(0xFFDBEAFE),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1F1C3B) : const Color(0xFFEFF6FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.people_alt_rounded, size: 15, color: Color(0xFF38BDF8)),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Clientes',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Fiados',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
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
          const SizedBox(width: 6),

          // Tarjeta Cotizaciones / Proformas
          Expanded(
            child: InkWell(
              onTap: () {
                final bizId = widget.businessId ?? _businessRepo.currentActiveBusiness?.id;
                if (bizId != null) {
                  QuotationsListModal.show(context, businessId: bizId);
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131127) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xFF26214A) : const Color(0xFFDDD6FE),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF26214A) : const Color(0xFFF5F3FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.description_outlined, size: 15, color: Color(0xFF8B5CF6)),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Cotizar',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Proformas',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
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
          const SizedBox(width: 6),

          // Tarjeta Exportar Excel
          Expanded(
            child: InkWell(
              onTap: _exportToExcel,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131127) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xFF26214A) : const Color(0xFFA7F3D0),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF064E3B).withOpacity(0.4) : const Color(0xFFECFDF5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.table_chart_rounded, size: 15, color: Color(0xFF059669)),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Excel',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '.xlsx',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
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
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = _summary['totalAmount'] ?? 0.0;
    final profit = _summary['netProfit'] ?? 0.0;
    final efectivo = _summary['byEfectivo'] ?? 0.0;
    final transf = _summary['byTransferencia'] ?? 0.0;
    final fiado = _summary['byFiado'] ?? 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131127) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Total e ingresos de hoy
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ventas de Hoy',
                    style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    CurrencyFormatter.format(total),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              if (canViewCosts)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Ganancia Real',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(profit),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF18152F) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? const Color(0xFF26214A) : const Color(0xFFCBD5E1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Ventas Hoy',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
                        ),
                      ),
                      Text(
                        '${_summary['salesCount'] ?? _sales.where((s) {
                          final n = DateTime.now();
                          return s.date.year == n.year && s.date.month == n.month && s.date.day == n.day;
                        }).length} reg.',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          Divider(height: 24, color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0)),

          // Desglose por Método de Pago
          Row(
            children: [
              _buildPaymentPill(Icons.payments_outlined, 'Efectivo', CurrencyFormatter.format(efectivo), const Color(0xFF059669)),
              const SizedBox(width: 8),
              _buildPaymentPill(Icons.account_balance_outlined, 'Transf.', CurrencyFormatter.format(transf), const Color(0xFF2563EB)),
              const SizedBox(width: 8),
              _buildPaymentPill(Icons.assignment_outlined, 'Fiado', CurrencyFormatter.format(fiado), const Color(0xFFD97706)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentPill(IconData icon, String title, String amount, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 3),
                Text(
                  title,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              amount,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaleCard(Sale sale) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isToday = sale.date.year == DateTime.now().year &&
        sale.date.month == DateTime.now().month &&
        sale.date.day == DateTime.now().day;
    final timeStr = isToday
        ? 'Hoy, ${DateFormat('hh:mm a').format(sale.date)}'
        : DateFormat('dd/MM/yyyy • hh:mm a').format(sale.date);

    Color methodColor;
    String methodLabel;
    IconData methodIcon;

    switch (sale.paymentMethod) {
      case 'TRANSFERENCIA':
        methodColor = const Color(0xFF2563EB);
        methodLabel = 'Transferencia';
        methodIcon = Icons.account_balance_outlined;
        break;
      case 'FIADO':
        methodColor = const Color(0xFFD97706);
        methodLabel = 'Venta a Fiado';
        methodIcon = Icons.assignment_late_outlined;
        break;
      default:
        methodColor = const Color(0xFF059669);
        methodLabel = 'Efectivo';
        methodIcon = Icons.payments_outlined;
    }

    final unitPrice = sale.quantity > 0 ? sale.totalAmount / sale.quantity : sale.totalAmount;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: isDark ? const Color(0xFF131127) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Cabecera: Fecha/Hora y Badge de Método de Pago
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: methodColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: methodColor.withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(methodIcon, size: 13, color: methodColor),
                      const SizedBox(width: 4),
                      Text(
                        methodLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: methodColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 2. Bloque del Producto: Foto + Nombre Multilínea + Cliente si es fiado
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Foto del producto
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: ProductImageView(
                      imagePath: sale.productPhotoPath,
                      width: 56,
                      height: 56,
                      iconSize: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Información textual completa del producto
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sale.productName,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                          height: 1.25,
                        ),
                        softWrap: true,
                      ),
                      if (sale.paymentMethod == 'FIADO' || (sale.customerName != null && sale.customerName!.trim().isNotEmpty)) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD97706).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFD97706).withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_rounded, size: 13, color: Color(0xFFD97706)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Cliente: ${sale.customerName ?? "Sin registrar"}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFD97706),
                                  ),
                                  softWrap: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 3. Ficha de Métricas Comerciales (Bloque en grilla / celdas)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF18152F) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                children: [
                  _buildMetricCell(
                    label: 'Cantidad',
                    value: 'x${sale.quantity} und.',
                    isDark: isDark,
                  ),
                  _buildMetricDivider(isDark),
                  _buildMetricCell(
                    label: 'Unitario',
                    value: CurrencyFormatter.format(unitPrice),
                    isDark: isDark,
                  ),
                  if (canViewCosts) ...[
                    _buildMetricDivider(isDark),
                    _buildMetricCell(
                      label: 'Ganancia',
                      value: '+${CurrencyFormatter.format(sale.netProfit)}',
                      isDark: isDark,
                      valueColor: const Color(0xFF059669),
                    ),
                  ],
                  _buildMetricDivider(isDark),
                  _buildMetricCell(
                    label: 'Total',
                    value: CurrencyFormatter.format(sale.totalAmount),
                    isDark: isDark,
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 4. Barra Inferior de Acciones Directas
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => DigitalTicketModal.show(context, sale: sale),
                    icon: const Icon(Icons.receipt_long_rounded, size: 16),
                    label: const Text(
                      'Comprobante',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF059669),
                      side: BorderSide(
                        color: isDark ? const Color(0xFF065F46) : const Color(0xFFA7F3D0),
                      ),
                      backgroundColor: isDark
                          ? const Color(0xFF064E3B).withOpacity(0.2)
                          : const Color(0xFFECFDF5),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                if (canCancelSale) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _cancelSale(sale),
                    icon: const Icon(Icons.undo_rounded, size: 15),
                    label: const Text(
                      'Anular',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCell({
    required String label,
    required String value,
    required bool isDark,
    Color? valueColor,
    bool isBold = false,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: valueColor ??
                    (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricDivider(bool isDark) {
    return Container(
      height: 24,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
    );
  }
}
