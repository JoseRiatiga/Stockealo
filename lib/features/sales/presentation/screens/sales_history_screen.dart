import '../widgets/sales_summary_card.dart';
import '../widgets/quotations_list_modal.dart';
import '../../../../core/design/app_pagination.dart';
import '../../../../core/design/primary_action_button.dart';
import '../../../../core/design/quick_access_row.dart';
import '../../../../core/design/skeleton.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../cash/data/cash_register_repository.dart';
import '../../../cash/models/cash_session.dart';
import '../widgets/sale_card.dart';
import '../../../business/presentation/active_business_scope.dart';
import '../../../../core/services/data_events.dart';
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
import '../../../../core/services/supabase_service.dart';
import '../../../team/data/team_repository.dart';
import '../../../../core/widgets/stocky_empty_state.dart';
import '../../../cash/presentation/screens/cash_register_screen.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/screens/modules_screen.dart';

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

  /// Caja abierta del negocio (si usa el arqueo)
  CashSession? _openCash;
  static const int _pageSize = 10;
  final ScrollController _scrollController = ScrollController();

  /// Cambia de página y vuelve al inicio de la pantalla para ver la lista desde arriba
  void _goToPage(int page) {
    setState(() => _currentPage = page);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  void initState() {
    super.initState();
    NotificationService.instance.remoteSalesVersion.addListener(_onRemoteSales);
    DataEvents.instance.salesVersion.addListener(_onRemoteSales);
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
    DataEvents.instance.salesVersion.removeListener(_onRemoteSales);
    _scrollController.dispose();
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
    // Estado de la caja, solo si el negocio usa el arqueo
    CashSession? openCash;
    if (mounted && ActiveBusinessScope.read(context)?.cashRegisterEnabled == true) {
      openCash = await CashRegisterRepository.instance.getOpenSession(bizId);
    }

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
        _openCash = openCash;
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
    if (mounted) _loadSales();
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
    final c = context.colors;
    final isDesktop = MediaQuery.of(context).size.width >= 850;
    final business = ActiveBusinessScope.of(context);
    final filtered = _filteredSales;
    final totalPages = filtered.isEmpty ? 1 : ((filtered.length - 1) ~/ _pageSize) + 1;
    final currentPageClamped = _currentPage.clamp(1, totalPages);
    final pagedSales = filtered.skip((currentPageClamped - 1) * _pageSize).take(_pageSize).toList();

    return Scaffold(
      appBar: isDesktop ? null : AppBar(title: const Text('Ventas')),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double hPadding = math.max(AppSpace.lg, (constraints.maxWidth - 1000) / 2);
            final columns = constraints.maxWidth >= 900 ? 2 : 1;

            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                if (isDesktop)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(hPadding, AppSpace.lg, hPadding, 0),
                      child: Row(
                        children: [
                          Text('Ventas', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.ink)),
                          const Spacer(),
                          PrimaryActionButton(label: 'Nueva venta', onPressed: _openQuickSale),
                        ],
                      ),
                    ),
                  ),

                // Resumen de hoy
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.md, hPadding, 0),
                    child: SalesSummaryCard(summary: _summary, sales: _sales, showProfit: canViewCosts),
                  ),
                ),

                // Accesos rápidos
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.md, hPadding, 0),
                    child: QuickAccessRow(
                      items: [
                        QuickAccessItem(
                          icon: Icons.people_alt_outlined,
                          label: 'Clientes y fiados',
                          caption: 'Deudas y abonos',
                          onTap: _navigateToCustomers,
                        ),
                        QuickAccessItem(
                          icon: Icons.request_quote_outlined,
                          label: 'Cotizaciones',
                          caption: 'Proformas',
                          onTap: _openQuotations,
                        ),
                        // Caja siempre visible: si está apagada explica y lleva a Módulos
                        QuickAccessItem(
                          icon: Icons.point_of_sale_rounded,
                          label: 'Caja',
                          caption: business?.cashRegisterEnabled != true
                              ? 'Apagada'
                              : (_openCash == null
                                  ? 'Cerrada'
                                  : 'Abierta desde ${DateFormat('h:mm a', 'es_CO').format(_openCash!.openedAt)}'),
                          onTap: business?.cashRegisterEnabled == true ? _openCashRegister : () => _explainCash(business),
                        ),
                      ],
                    ),
                  ),
                ),

                // Filtros
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.lg, hPadding, 0),
                    child: _buildFiltersBar(),
                  ),
                ),

                // Encabezado de la lista con la paginación compacta
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPadding + AppSpace.xs, AppSpace.md, hPadding, AppSpace.xs),
                    child: Row(
                      children: [
                        Text('Ventas registradas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
                        const SizedBox(width: AppSpace.sm),
                        Text('${filtered.length}', style: AppText.amount(context, size: 14, weight: FontWeight.w500, color: c.inkMuted)),
                        const Spacer(),
                        AppPagination(
                          currentPage: currentPageClamped,
                          totalPages: totalPages,
                          onPageChanged: _goToPage,
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                ),

                if (_isLoading)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.sm, hPadding, 0),
                    sliver: SliverList.separated(
                      itemCount: 5,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
                      itemBuilder: (_, __) => const SkeletonListTile(),
                    ),
                  )
                else if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: StockyEmptyState(
                      title: _sales.isEmpty ? 'Aún no hay ventas' : 'Sin ventas con estos filtros',
                      message: _sales.isEmpty
                          ? 'Tus ventas aparecerán aquí apenas registres la primera.'
                          : 'Prueba con otras fechas u otro método de pago.',
                      actionLabel: _sales.isNotEmpty ? 'Quitar filtros' : null,
                      onAction: _sales.isNotEmpty ? _clearFilters : null,
                    ),
                  )
                else if (columns == 1)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    sliver: SliverList.separated(
                      itemCount: pagedSales.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
                      itemBuilder: (_, i) => _saleCard(pagedSales[i]),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: AppSpace.sm,
                        mainAxisSpacing: AppSpace.sm,
                        mainAxisExtent: 70,
                      ),
                      delegate: SliverChildBuilderDelegate((_, i) => _saleCard(pagedSales[i]), childCount: pagedSales.length),
                    ),
                  ),

                // Paginación completa abajo; espacio para el botón principal y Stocky
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.md, hPadding, MediaQuery.of(context).padding.bottom + 150),
                    child: _isLoading
                        ? const SizedBox.shrink()
                        : AppPagination(currentPage: currentPageClamped, totalPages: totalPages, onPageChanged: _goToPage),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: isDesktop
          ? null
          : Padding(
              // A la altura de la pastilla de Stocky en Inicio, justo encima de la barra
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
              child: PrimaryActionButton(label: 'Nueva venta', onPressed: _openQuickSale),
            ),
    );
  }

  SaleCard _saleCard(Sale sale) => SaleCard(
        sale: sale,
        showProfit: canViewCosts,
        onCancel: canCancelSale ? () => _cancelSale(sale) : null,
      );

  void _clearFilters() {
    setState(() {
      _selectedDateFilter = 'all';
      _selectedPaymentMethod = 'ALL';
      _customDateRange = null;
      _currentPage = 1;
    });
  }

  Future<void> _openQuotations() async {
    final bizId = widget.businessId ?? ActiveBusinessScope.read(context)?.id;
    if (bizId == null) return;
    await QuotationsListModal.show(context, businessId: bizId);
    if (mounted) _loadSales();
  }

  /// La caja está apagada: qué hace y dónde se enciende (Ajustes › Módulos)
  Future<void> _explainCash(Business? business) async {
    if (business == null) return;
    final canEdit = (_userRole ?? widget.userRole) != 'CASHIER';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Caja (arqueo)'),
        content: Text(
          'Abre el turno con una base, registra entradas y salidas y cierra contando el dinero para saber si cuadra.\n\n'
          '${canEdit ? 'Se enciende en Ajustes › Módulos.' : 'El dueño o un administrador la enciende en Ajustes › Módulos.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cerrar')),
          if (canEdit) FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ir a Módulos')),
        ],
      ),
    );
    if (go == true && mounted) {
      await ModulesScreen.open(context, business: business, canEdit: canEdit);
      if (mounted) _loadSales();
    }
  }



  String get _dateLabel => switch (_selectedDateFilter) {
        'today' => 'Hoy',
        '7days' => 'Últimos 7 días',
        'month' => 'Este mes',
        'custom' => _customDateRange != null
            ? '${DateFormat('dd/MM').format(_customDateRange!.start)} – ${DateFormat('dd/MM').format(_customDateRange!.end)}'
            : 'Rango',
        _ => 'Todas las fechas',
      };

  String get _methodLabel => _selectedPaymentMethod == 'ALL' ? 'Todos los pagos' : paymentMethodLabel(_selectedPaymentMethod);

  /// Lista de opciones en una hoja inferior; devuelve la clave elegida
  Future<String?> _pickOption(String title, Map<String, String> options, String selected) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.sm),
              child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.colors.ink)),
            ),
            for (final entry in options.entries)
              ListTile(
                title: Text(entry.value),
                trailing: entry.key == selected ? Icon(Icons.check_rounded, color: ctx.colors.accent) : null,
                onTap: () => Navigator.pop(ctx, entry.key),
              ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersBar() {
    final c = context.colors;
    Widget button(String label, bool active, VoidCallback onTap) => Expanded(
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 12),
              side: BorderSide(color: active ? c.accent : c.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: active ? c.accent : c.ink),
                  ),
                ),
                Icon(Icons.expand_more_rounded, size: 20, color: active ? c.accent : c.inkMuted),
              ],
            ),
          ),
        );

    return Row(
      children: [
        button(_dateLabel, _selectedDateFilter != 'all', () async {
          final picked = await _pickOption(
            'Fechas',
            const {
              'all': 'Todas las fechas',
              'today': 'Hoy',
              '7days': 'Últimos 7 días',
              'month': 'Este mes',
              'custom': 'Elegir rango…',
            },
            _selectedDateFilter,
          );
          if (picked == null) return;
          if (picked == 'custom') {
            await _pickCustomDateRange();
          } else {
            setState(() {
              _selectedDateFilter = picked;
              _currentPage = 1;
            });
          }
        }),
        const SizedBox(width: AppSpace.sm),
        button(_methodLabel, _selectedPaymentMethod != 'ALL', () async {
          final picked = await _pickOption(
            'Método de pago',
            const {
              'ALL': 'Todos los pagos',
              'EFECTIVO': 'Efectivo',
              'TRANSFERENCIA': 'Transferencia',
              'FIADO': 'Fiado',
            },
            _selectedPaymentMethod,
          );
          if (picked == null) return;
          setState(() {
            _selectedPaymentMethod = picked;
            _currentPage = 1;
          });
        }),
      ],
    );
  }
}
