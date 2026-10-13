import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../data/sales_repository.dart';
import '../../../business/data/business_repository.dart';
import '../../../auth/data/auth_repository.dart';
import '../../models/sale.dart';
import '../widgets/digital_ticket_modal.dart';
import '../../../customers/presentation/screens/customers_screen.dart';
import '../../../reports/data/excel_export_service.dart';
import '../../../../core/services/supabase_service.dart';

class SalesHistoryScreen extends StatefulWidget {
  final String? businessId;

  const SalesHistoryScreen({super.key, this.businessId});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final _salesRepo = SalesRepository();
  final _businessRepo = BusinessRepository.instance;

  List<Sale> _sales = [];
  Map<String, dynamic> _summary = {};
  bool _isLoading = true;

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Venta anulada y stock devuelto al catálogo'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportToExcel() async {
    final biz = _businessRepo.currentActiveBusiness;
    if (biz == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay una empresa activa seleccionada.'), backgroundColor: Colors.orange),
      );
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
    } catch (e) {
      closeDialog();
      if (mounted) {
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Ventas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: 'Clientes y Fiados',
            onPressed: () async {
              var bizId = widget.businessId ?? _businessRepo.currentActiveBusiness?.id;
              if (bizId == null) {
                final user = AuthRepository.instance.currentUser;
                if (user != null) {
                  final biz = await _businessRepo.getActiveBusiness(user.id, user.email);
                  bizId = biz?.id;
                }
              }
              if (bizId != null && context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CustomersScreen(businessId: bizId!),
                  ),
                ).then((_) => _loadSales());
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: 'Exportar a Excel (.xlsx)',
            onPressed: _exportToExcel,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFF059669),
        child: CustomScrollView(
          slivers: [
            // Resumen de Métricas de Ventas de Hoy
            SliverToBoxAdapter(
              child: _buildSummaryCard(),
            ),

            // Encabezado de la lista
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Registro de Transacciones',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      '${_sales.length} ventas',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Lista de ventas
            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_sales.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF064E3B)
                                : const Color(0xFFECFDF5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.receipt_long_outlined,
                            size: 48,
                            color: Color(0xFF059669),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Aún no hay ventas registradas',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFFF8FAFC)
                                : const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Cuando descuentes productos de stock por venta, aparecerán detallados aquí.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final sale = _sales[index];
                    return _buildSaleCard(sale);
                  },
                  childCount: _sales.length,
                ),
              ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 30),
            ),
          ],
        ),
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
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
              ),
            ],
          ),
          Divider(height: 24, color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),

          // Desglose por Método de Pago
          Row(
            children: [
              _buildPaymentPill('💵 Efectivo', CurrencyFormatter.format(efectivo), const Color(0xFF059669)),
              const SizedBox(width: 8),
              _buildPaymentPill('📱 Transf.', CurrencyFormatter.format(transf), const Color(0xFF2563EB)),
              const SizedBox(width: 8),
              _buildPaymentPill('📝 Fiado', CurrencyFormatter.format(fiado), const Color(0xFFD97706)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentPill(String title, String amount, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
            ),
            const SizedBox(height: 2),
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
        ? DateFormat('hh:mm a').format(sale.date)
        : DateFormat('dd/MM hh:mm a').format(sale.date);

    Color methodColor;
    String methodLabel;

    switch (sale.paymentMethod) {
      case 'TRANSFERENCIA':
        methodColor = const Color(0xFF2563EB);
        methodLabel = '📱 Transferencia';
        break;
      case 'FIADO':
        methodColor = const Color(0xFFD97706);
        methodLabel = '📝 Fiado${sale.customerName != null ? ' (${sale.customerName})' : ''}';
        break;
      default:
        methodColor = const Color(0xFF059669);
        methodLabel = '💵 Efectivo';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 0,
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fila 1: Hora/Fecha, Nombre de producto y Total
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sale.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  CurrencyFormatter.format(sale.totalAmount),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Fila 2: Método de pago, Cantidad, Ganancia y Acciones
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: methodColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      methodLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: methodColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'x${sale.quantity} unid.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '+${CurrencyFormatter.format(sale.netProfit)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF059669),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(Icons.receipt_long, size: 20, color: Color(0xFF059669)),
                  tooltip: 'Ver / Compartir Ticket',
                  onPressed: () => DigitalTicketModal.show(context, sale: sale),
                ),
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(Icons.undo, size: 18, color: Color(0xFF94A3B8)),
                  tooltip: 'Anular Venta',
                  onPressed: () => _cancelSale(sale),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
