import '../widgets/sales_summary_card.dart';
import '../widgets/quotations_list_modal.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/app_pagination.dart';
import '../../../../core/design/quick_access_row.dart';
import '../../../../core/design/skeleton.dart';
import '../../../../core/theme/app_tokens.dart';
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
import '../../../../core/services/supabase_service.dart';
import '../../../team/data/team_repository.dart';
import '../../../../core/widgets/stocky_empty_state.dart';
import '../../../sales/models/payment_method.dart';
import '../widgets/digital_ticket_modal.dart';
import '../../../../core/codes/code_reader.dart';

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
  /// 'ALL', un código de [PaymentMethod] o [_voided]
  String _selectedPaymentMethod = 'ALL';
  static const _voided = 'ANULADAS';
  int _currentPage = 1;

  /// Caja abierta del negocio (si usa el arqueo)
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

  /// Anular sin borrar: se pide el motivo y la venta queda en el historial como «Anulada»
  Future<void> _cancelSale(Sale sale) async {
    const reasons = ['Se equivocó de producto', 'El cliente devolvió', 'Cobro repetido', 'Prueba'];
    final other = TextEditingController();
    String? picked;
    final reason = await AppSheet.show<String>(
      context: context,
      title: 'Anular esta venta',
      subtitle: 'El stock vuelve al inventario y deja de contar en los totales, la caja y los reportes. '
          'La venta queda en el historial como «Anulada».',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('¿Por qué la anulas?', style: AppText.body(ctx, weight: FontWeight.w600)),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final r in reasons)
                  ChoiceChip(label: Text(r), selected: picked == r, showCheckmark: false, onSelected: (_) => setLocal(() => picked = r)),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: other,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setLocal(() => picked = null),
              decoration: const InputDecoration(labelText: 'Otro motivo'),
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ctx.colors.danger, foregroundColor: ctx.colors.onAccent),
              onPressed: (picked ?? other.text.trim()).isEmpty ? null : () => Navigator.pop(ctx, picked ?? other.text.trim()),
              child: const Text('Anular venta'),
            ),
          ],
        ),
      ),
    );
    other.dispose();
    if (reason == null) return;
    await _salesRepo.voidSale(sale, reason: reason);
    await _loadSales();
    if (mounted) AppToast.showSuccess(context, 'Venta anulada. El stock volvió al inventario.');
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
      // Filtro de forma de pago (o solo las anuladas)
      if (_selectedPaymentMethod == _voided) {
        if (!sale.isVoided) return false;
      } else if (_selectedPaymentMethod != 'ALL') {
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
    final filtered = _filteredSales;
    final totalPages = filtered.isEmpty ? 1 : ((filtered.length - 1) ~/ _pageSize) + 1;
    final currentPageClamped = _currentPage.clamp(1, totalPages);
    final pagedSales = filtered.skip((currentPageClamped - 1) * _pageSize).take(_pageSize).toList();

    return Scaffold(
      // Sin barra propia ni «Nueva venta»: los pone el encabezado único (re-diseño 0.13.0)
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double hPadding = math.max(AppSpace.lg, (constraints.maxWidth - 1000) / 2);
            final columns = constraints.maxWidth >= 900 ? 2 : 1;

            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                // Resumen de hoy
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.md, hPadding, 0),
                    child: SalesSummaryCard(summary: _summary, sales: _sales, showProfit: canViewCosts),
                  ),
                ),

                // Cotizaciones vive en Ventas; Clientes y Caja tienen su propio lugar en el menú
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.md, hPadding, 0),
                    child: QuickAccessRow(
                      items: [
                        QuickAccessItem(
                          icon: Icons.request_quote_outlined,
                          label: 'Cotizaciones',
                          caption: 'Proformas para tus clientes',
                          onTap: _openQuotations,
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
                        Text('Ventas registradas', style: AppText.title(context)),
                        const SizedBox(width: AppSpace.sm),
                        Text('${filtered.length}', style: AppText.amount(context, size: AppText.sizeBody, weight: FontWeight.w500, color: c.inkMuted)),
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
    );
  }

  SaleCard _saleCard(Sale sale) => SaleCard(
        sale: sale,
        showProfit: canViewCosts,
        onCancel: canCancelSale ? () => _cancelSale(sale) : null,
      );

  /// Lee el código de barras de un tiquete (su número) y abre esa venta
  Future<void> _scanTicket() async {
    final code = await CodeReader.scan(context, title: 'Escanear un tiquete', caption: 'Ventas');
    if (code == null || !mounted) return;
    final clean = code.trim().replaceFirst('#', '').toUpperCase();
    final match = _sales.where((s) => (s.invoiceNumber ?? '').replaceFirst('#', '').toUpperCase() == clean).toList();
    if (match.isEmpty) {
      AppToast.showWarning(context, 'No hay ninguna venta con el número $clean.');
      return;
    }
    await DigitalTicketModal.show(context, salesList: match);
  }

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



  String get _dateLabel => switch (_selectedDateFilter) {
        'today' => 'Hoy',
        '7days' => 'Últimos 7 días',
        'month' => 'Este mes',
        'custom' => _customDateRange != null
            ? '${DateFormat('dd/MM').format(_customDateRange!.start)} – ${DateFormat('dd/MM').format(_customDateRange!.end)}'
            : 'Rango',
        _ => 'Todas las fechas',
      };

  String get _methodLabel => switch (_selectedPaymentMethod) {
        'ALL' => 'Todos los pagos',
        _voided => 'Anuladas',
        final m => PaymentMethod.label(m),
      };

  /// Lista de opciones en una hoja inferior; devuelve la clave elegida
  Future<String?> _pickOption(String title, Map<String, String> options, String selected) {
    return AppSheet.show<String>(
      context: context,
      title: title,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in options.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.value, style: AppText.body(ctx)),
              trailing: entry.key == selected ? Icon(Icons.check_outlined, color: ctx.colors.accent) : null,
              onTap: () => Navigator.pop(ctx, entry.key),
            ),
        ],
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
                    style: AppText.body(context, color: active ? c.accent : c.ink),
                  ),
                ),
                Icon(Icons.expand_more_outlined, size: 20, color: active ? c.accent : c.inkMuted),
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
        // Escanear el código de un tiquete abre esa venta
        IconButton.outlined(
          tooltip: 'Escanear un tiquete',
          onPressed: _scanTicket,
          icon: const Icon(Icons.qr_code_scanner_outlined, size: 20),
        ),
        const SizedBox(width: AppSpace.sm),
        button(_methodLabel, _selectedPaymentMethod != 'ALL', () async {
          final picked = await _pickOption(
            'Forma de pago',
            {
              'ALL': 'Todos los pagos',
              for (final m in PaymentMethod.forSale) m: PaymentMethod.label(m),
              _voided: 'Anuladas',
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
