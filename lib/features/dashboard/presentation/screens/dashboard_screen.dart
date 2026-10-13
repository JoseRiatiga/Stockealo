import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/data/business_repository.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/widgets/business_selector_modal.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/presentation/screens/barcode_scanner_screen.dart';
import '../../../products/presentation/screens/product_form_screen.dart';
import '../../../sales/presentation/widgets/quick_sale_dialog.dart';
import '../../../team/data/team_repository.dart';
import '../../../team/presentation/screens/employees_screen.dart';
import '../../../customers/presentation/screens/customers_screen.dart';
import '../../../products/presentation/widgets/restock_order_modal.dart';
import '../../data/dashboard_repository.dart';
import '../../../../core/services/supabase_service.dart';

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
  String _userRole = 'OWNER';
  bool _isLoading = true;

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
      final data = await _dashboardRepo.getDashboardSummary(_activeBusiness!.id);
      if (mounted) {
        setState(() {
          _summary = data;
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

    return Scaffold(
      appBar: AppBar(
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
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Escanear para Vender',
            onPressed: _scanToSell,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFF059669),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Saludo al comerciante
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '¡Hola, $userName! 👋',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Resumen operativo de hoy',
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
                  const SizedBox(height: 18),

                  // Tarjetas de Métricas de Hoy (2x2 Grid)
                  _buildMetricsGrid(),
                  const SizedBox(height: 20),

                  // Acciones Rápidas (Estilo POS)
                  Text(
                    'Acciones Rápidas',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActions(),
                  const SizedBox(height: 24),

                  // Gráfico de Ventas de los últimos 7 días
                  _buildWeeklySalesChart(),
                  const SizedBox(height: 24),

                  // Top Productos Más Vendidos
                  _buildTopProductsSection(),
                  const SizedBox(height: 20),
                ],
              ),
      ),
    );
  }

  Widget _buildMetricsGrid() {
    final double todayTotal = _summary['todayTotal'] ?? 0.0;
    final double todayProfit = _summary['todayProfit'] ?? 0.0;
    final int todayUnits = _summary['todayUnits'] ?? 0;
    final double totalDebt = _summary['totalDebt'] ?? 0.0;

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.35,
      children: [
        // Ventas de hoy
        _buildMetricCard(
          title: 'Ventas de Hoy',
          value: CurrencyFormatter.format(todayTotal),
          subtitle: '${_summary['todayCount'] ?? 0} ventas registradas',
          icon: Icons.payments_outlined,
          color: const Color(0xFF059669),
          bg: const Color(0xFFECFDF5),
        ),

        // Ganancia Neta de hoy (oculta para Cajeros)
        _buildMetricCard(
          title: 'Ganancia Neta Hoy',
          value: canViewProfits ? CurrencyFormatter.format(todayProfit) : '••••••',
          subtitle: canViewProfits ? 'Margen de utilidad neto' : 'Restringido para cajeros',
          icon: Icons.trending_up,
          color: const Color(0xFF0D9488),
          bg: const Color(0xFFF0FDFA),
        ),

        // Unidades vendidas
        _buildMetricCard(
          title: 'Unidades Vendidas',
          value: '$todayUnits unid.',
          subtitle: 'Despachadas hoy',
          icon: Icons.inventory_2_outlined,
          color: const Color(0xFF2563EB),
          bg: const Color(0xFFEFF6FF),
        ),

        // Cuentas por Cobrar (Fiados)
        _buildMetricCard(
          title: 'Por Cobrar (Fiado)',
          value: CurrencyFormatter.format(totalDebt),
          subtitle: 'Deudas pendientes',
          icon: Icons.receipt_long_outlined,
          color: const Color(0xFFD97706),
          bg: const Color(0xFFFEF3C7),
          onTap: () {
            if (_activeBusiness != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CustomersScreen(businessId: _activeBusiness!.id),
                ),
              ).then((_) => _loadData());
            }
          },
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bg,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ),
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isDark ? bg.withOpacity(0.15) : bg,
                  child: Icon(icon, size: 16, color: color),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    final int lowStock = _summary['lowStock'] ?? 0;
    final int outOfStock = _summary['outOfStock'] ?? 0;
    final int alertTotal = lowStock + outOfStock;

    return Row(
      children: [
        // Botón Venta Rápida
        Expanded(
          child: _buildActionBtn(
            label: 'Vender',
            icon: Icons.qr_code_scanner,
            color: const Color(0xFF059669),
            onTap: _scanToSell,
          ),
        ),
        const SizedBox(width: 8),

        // Botón Nuevo Producto
        Expanded(
          child: _buildActionBtn(
            label: 'Producto',
            icon: Icons.add_box_outlined,
            color: const Color(0xFF2563EB),
            onTap: () async {
              if (_activeBusiness == null) return;
              final created = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => ProductFormScreen(businessId: _activeBusiness!.id),
                ),
              );
              if (created == true) _loadData();
            },
          ),
        ),
        const SizedBox(width: 8),

        // Alertas de Stock
        Expanded(
          child: _buildActionBtn(
            label: 'Alertas',
            icon: Icons.warning_amber_rounded,
            color: alertTotal > 0 ? const Color(0xFFDC2626) : const Color(0xFF64748B),
            badge: alertTotal > 0 ? '$alertTotal' : null,
            onTap: () {
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
            },
          ),
        ),
        const SizedBox(width: 8),

        // Equipo
        Expanded(
          child: _buildActionBtn(
            label: 'Equipo',
            icon: Icons.group_outlined,
            color: const Color(0xFF7C3AED),
            onTap: () async {
              if (_activeBusiness == null) return;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EmployeesScreen(business: _activeBusiness!),
                ),
              );
              _loadData();
            },
          ),
        ),
      ],
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklySalesChart() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<dynamic> weeklySales = _summary['weeklySales'] ?? [];
    double maxAmount = 1000.0;
    for (final item in weeklySales) {
      final total = (item['total'] as num).toDouble();
      if (total > maxAmount) maxAmount = total;
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
                'Ventas de la Semana (Últimos 7 días)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                ),
              ),
              InkWell(
                onTap: widget.onNavigateToSales,
                child: const Text(
                  'Ver historial',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Barras
          SizedBox(
            height: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: weeklySales.map((item) {
                final day = item['day'] as String;
                final total = (item['total'] as num).toDouble();
                final heightFactor = (total / maxAmount).clamp(0.08, 1.0);

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (total > 0)
                      Text(
                        '${(total / 1000).toStringAsFixed(0)}k',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                      ),
                    const SizedBox(height: 4),
                    Container(
                      width: 22,
                      height: 70 * heightFactor,
                      decoration: BoxDecoration(
                        color: total > 0
                            ? const Color(0xFF059669)
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      day,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
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

    final medalIcons = ['🥇', '🥈', '🥉'];

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
          Text(
            'Productos Más Vendidos',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          ...topProducts.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final medal = idx < medalIcons.length ? medalIcons[idx] : '•';

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(medal, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item['name'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  Text(
                    '${item['qty']} vendidos',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
