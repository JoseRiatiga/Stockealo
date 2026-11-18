import '../widgets/sales_summary_card.dart';
import '../../../../core/design/app_date_range_picker.dart';
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
import 'package:flutter/foundation.dart';
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
import '../../../../core/services/sync_queue.dart';
import '../widgets/deliveries.dart';
import '../../../store/data/store_orders_repository.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../team/presentation/widgets/authorization_gate.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/design/filter_tabs.dart';

class SalesHistoryScreen extends StatefulWidget {
  final String? businessId;
  final String? userRole;

  const SalesHistoryScreen({super.key, this.businessId, this.userRole});

  /// Una venta = un comprobante (0.16.4). Cada devolución va en su propia tarjeta.
  static List<List<Sale>> groupByInvoice(List<Sale> lines) {
    final groups = <String, List<Sale>>{};
    for (final s in lines) {
      final invoice = s.invoiceNumber ?? '';
      final key = s.isReturn ? 'dev:${s.id}' : (invoice.isEmpty ? 'id:${s.id}' : 'inv:$invoice');
      groups.putIfAbsent(key, () => []).add(s);
    }
    return groups.values.toList();
  }

  /// «4 ventas · 1 devolución»: cuenta comprobantes y las devoluciones van aparte,
  /// sin sumarse a las ventas (0.16.6, decisión N3)
  static String countLabel(List<List<Sale>> groups) {
    final returns = groups.where((g) => g.isNotEmpty && g.first.isReturn).length;
    final sales = groups.length - returns;
    final text = '$sales ${sales == 1 ? 'venta' : 'ventas'}';
    return returns == 0 ? text : '$text · $returns ${returns == 1 ? 'devolución' : 'devoluciones'}';
  }

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> with ActiveBusinessAware {
  @override
  void onActiveBusinessChanged() => _onBusinessChanged();

  final _salesRepo = SalesRepository();
  final _businessRepo = BusinessRepository.instance;

  List<Sale> _sales = [];

  /// Ventas hechas sin conexión que todavía no suben a la nube
  Set<String> _pendingIds = const {};

  void _onUnseen() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshPending() async {
    final ids = await SyncQueue.instance.pendingIds('upsert_sale');
    if (mounted && !setEquals(ids, _pendingIds)) setState(() => _pendingIds = ids);
  }
  Map<String, dynamic> _summary = {};
  bool _isLoading = true;
  String? _userRole;

  String get _effectiveRole => widget.userRole ?? _userRole ?? 'OWNER';
  bool get canViewCosts => Permissions.can(_effectiveRole, Perm.costs);
  bool get canCancelSale => Permissions.can(_effectiveRole, Perm.voidSale);

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
    // Cuando sube lo hecho sin conexión, se quita «Pendiente de subir»
    SyncQueue.instance.status.addListener(_refreshPending);
    // Pedidos de la tienda sin ver: el número de Cotizaciones
    StoreOrdersRepository.instance.unseen.addListener(_onUnseen);
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
    SyncQueue.instance.status.removeListener(_refreshPending);
    StoreOrdersRepository.instance.unseen.removeListener(_onUnseen);
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
    await _refreshPending();

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
  /// Devolución parcial (0.15.0): cuántas, si vuelven al inventario y el motivo
  Future<void> _returnSale(Sale sale) async {
    final left = sale.quantity - await _salesRepo.returnedQuantity(sale.id);
    if (!mounted) return;
    if (left <= 0) {
      AppToast.showInfo(context, 'Ya se devolvió todo lo de esta venta.');
      return;
    }
    var qty = 1;
    var restock = true;
    // Venta mixta (0.16.4): por cuál medio se le devuelve la plata
    final refundOptions = SalesRepository.refundMethods(sale);
    var refund = SalesRepository.refundMethodFor(sale, null);
    final reason = TextEditingController();
    final ok = await AppSheet.show<bool>(
      context: context,
      title: 'Devolver',
      subtitle: '${sale.listName} · se vendieron ${sale.quantity}${left < sale.quantity ? ', quedan $left por devolver' : ''}',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final amount = sale.totalAmount / sale.quantity * qty;
          final money = CurrencyFormatter.format(amount);
          final how = switch (refund) {
            PaymentMethod.cash => 'Le devuelves $money en efectivo: sale de la caja.',
            PaymentMethod.credit => 'Su deuda baja $money.',
            _ => 'Le devuelves $money ${PaymentMethod.phrase(refund)}.',
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('¿Cuántas?', style: AppText.body(ctx, weight: FontWeight.w600))),
                  IconButton.outlined(
                    tooltip: 'Una menos',
                    onPressed: qty > 1 ? () => setLocal(() => qty--) : null,
                    icon: const Icon(Icons.remove_outlined, size: 18),
                  ),
                  SizedBox(width: 36, child: Text('$qty', textAlign: TextAlign.center, style: AppText.title(ctx))),
                  IconButton.outlined(
                    tooltip: 'Una más',
                    onPressed: qty < left ? () => setLocal(() => qty++) : null,
                    icon: const Icon(Icons.add_outlined, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              FilterTabs<bool>(
                wrap: true,
                options: const {true: 'Vuelve al inventario', false: 'Llegó dañado'},
                value: restock,
                onChanged: (v) => setLocal(() => restock = v),
              ),
              const SizedBox(height: AppSpace.md),
              if (refundOptions.length > 1) ...[
                Text('Se pagó en pago mixto. ¿Cómo le devuelves la plata?', style: AppText.body(ctx, weight: FontWeight.w600)),
                const SizedBox(height: AppSpace.sm),
                FilterTabs<String>(
                  wrap: true,
                  options: {for (final m in refundOptions) m: PaymentMethod.label(m)},
                  value: refund,
                  onChanged: (v) => setLocal(() => refund = v),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              TextField(
                controller: reason,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Motivo (opcional)', hintText: 'Ej.: talla equivocada'),
              ),
              const SizedBox(height: AppSpace.md),
              Text(how, style: AppText.body(ctx, weight: FontWeight.w600)),
              const SizedBox(height: AppSpace.md),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Devolver $qty · $money')),
            ],
          );
        },
      ),
    );
    final why = reason.text;
    reason.dispose();
    if (ok != true || !mounted) return;
    try {
      await _salesRepo.returnSale(sale, quantity: qty, restock: restock, reason: why, refundMethod: refund);
      if (!mounted) return;
      AppToast.showSuccess(context, 'Devolución registrada.');
      await _loadSales();
    } on StateError catch (e) {
      if (mounted) AppToast.showWarning(context, e.message);
    } catch (e) {
      if (mounted) AppToast.showError(context, '$e');
    }
  }

  Future<void> _cancelSale(Sale sale) async {
    // Anular solo ventas recientes (límite del rol, 0.15.0)
    final hours = Permissions.myLimit(RoleLimit.voidHours);
    final age = DateTime.now().difference(sale.date).inMinutes / 60;
    String? voidAuth;
    if (hours != null && age > hours) {
      voidAuth = await AuthorizationGate.allow(
        context,
        businessId: sale.businessId,
        action: 'Anular una venta de ${CurrencyFormatter.format(sale.totalAmount)}',
        reasons: ['La venta es de hace ${age.floor()} horas y tu rol solo anula las de las últimas ${hours.round()} horas.'],
        amount: sale.totalAmount,
      );
      if (voidAuth == null || !mounted) return;
    }
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
    if (reason == null || !mounted) return;
    // 0.14.0: si es un servicio de una orden con más cosas, se pregunta qué anular
    var onlyThis = false;
    final lines = await _salesRepo.linesOf(sale);
    if (sale.serviceId != null && lines.where((l) => !l.isVoided).length > 1 && mounted) {
      final choice = await AppDialog.show<bool>(
        context: context,
        icon: Icons.content_cut_outlined,
        tone: AppTone.danger,
        title: '¿Qué anulas?',
        subtitle: 'Este cobro tiene ${lines.length} líneas: servicios y propina.',
        content: Builder(
          builder: (ctx) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Solo «${sale.listName}»'),
              ),
              const SizedBox(height: AppSpace.sm),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Todo el cobro, con la propina'),
              ),
            ],
          ),
        ),
      );
      if (choice == null) return;
      onlyThis = choice;
    }
    await _salesRepo.voidSale(sale, reason: reason, onlyThisLine: onlyThis, voidAuthRequestId: voidAuth);
    await _loadSales();
    if (mounted) AppToast.showSuccess(context, 'Venta anulada. El stock volvió al inventario.');
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showAppDateRangePicker(
      context,
      initial: _customDateRange,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
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
    final filtered = SalesHistoryScreen.groupByInvoice(_filteredSales);
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
                          caption: 'Pedidos y proformas',
                          onTap: _openQuotations,
                          badge: StoreOrdersRepository.instance.unseen.value,
                        ),
                        // Lo cobrado que falta entregar (0.13.4)
                        QuickAccessItem(
                          icon: Icons.local_shipping_outlined,
                          label: 'Por entregar',
                          caption: 'Recoge después o envío',
                          onTap: () async {
                            final bizId = widget.businessId ?? ActiveBusinessScope.read(context)?.id;
                            if (bizId == null) return;
                            await DeliveriesSheet.show(context, businessId: bizId);
                            if (mounted) _loadSales();
                          },
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
                        Expanded(
                          child: Text(SalesHistoryScreen.countLabel(filtered),
                              overflow: TextOverflow.ellipsis,
                              style: AppText.small(context, weight: FontWeight.w500, color: c.inkMuted)),
                        ),
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

  Widget _saleCard(List<Sale> group) => group.length == 1
      ? _lineCard(group.single)
      : SaleGroupCard(
          lines: group,
          showProfit: canViewCosts,
          lineCard: _lineCard,
          onCancel: canCancelSale ? () => _cancelSale(group.first) : null,
          pendingUpload: group.any((l) => _pendingIds.contains(l.id)),
        );

  SaleCard _lineCard(Sale sale) => SaleCard(
        sale: sale,
        showProfit: canViewCosts,
        // Una devolución no se anula sola (0.16.6): si no volvió al inventario, anularla
        // restaba una unidad que nunca entró. Se anula junto con su venta.
        onCancel: canCancelSale && !sale.isReturn ? () => _cancelSale(sale) : null,
        onReturn: Permissions.can(_effectiveRole, Perm.refund) ? () => _returnSale(sale) : null,
        pendingUpload: _pendingIds.contains(sale.id),
      );

  /// Lee el código de barras de un tiquete (su número) y abre esa venta
  Future<void> _scanTicket() async {
    final code = await CodeReader.scan(context, title: 'Escanear un recibo', caption: 'Ventas');
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
          tooltip: 'Escanear un recibo',
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
