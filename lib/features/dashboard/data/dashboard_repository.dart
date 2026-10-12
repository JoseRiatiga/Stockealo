import '../../../core/database/app_database.dart';

class DashboardRepository {
  static final DashboardRepository instance = DashboardRepository._internal();
  DashboardRepository._internal();

  final AppDatabase _dbProvider = AppDatabase.instance;

  Future<Map<String, dynamic>> getDashboardSummary(String businessId) async {
    final db = await _dbProvider.database;
    final now = DateTime.now();
    final todayPrefix = "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}%";

    // 1. Ventas y ganancias de hoy
    final todaySalesRes = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        COALESCE(SUM(total), 0.0) as total_amount,
        COALESCE(SUM(net_profit), 0.0) as net_profit,
        COALESCE(SUM(quantity), 0) as units_sold
      FROM sales 
      WHERE business_id = ? AND date LIKE ?
    ''', [businessId, todayPrefix]);

    final todaySales = todaySalesRes.isNotEmpty ? todaySalesRes.first : {};
    final double todayTotal = (todaySales['total_amount'] as num?)?.toDouble() ?? 0.0;
    final double todayProfit = (todaySales['net_profit'] as num?)?.toDouble() ?? 0.0;
    final int todayUnits = (todaySales['units_sold'] as num?)?.toInt() ?? 0;
    final int todayCount = (todaySales['count'] as num?)?.toInt() ?? 0;

    // 2. Deuda total pendiente por cobrar (Fiados)
    final debtRes = await db.rawQuery('''
      SELECT COALESCE(SUM(debt_balance), 0.0) as total_debt 
      FROM customers 
      WHERE business_id = ? AND debt_balance > 0
    ''', [businessId]);
    final double totalDebt = (debtRes.first['total_debt'] as num?)?.toDouble() ?? 0.0;

    // 3. Estado del stock y alertas
    final stockRes = await db.rawQuery('''
      SELECT 
        COUNT(*) as total,
        COALESCE(SUM(CASE WHEN stock <= 0 THEN 1 ELSE 0 END), 0) as out_of_stock,
        COALESCE(SUM(CASE WHEN stock > 0 AND stock <= min_stock THEN 1 ELSE 0 END), 0) as low_stock
      FROM products 
      WHERE business_id = ? AND is_active = 1
    ''', [businessId]);

    final stockRow = stockRes.isNotEmpty ? stockRes.first : {};
    final int outOfStock = (stockRow['out_of_stock'] as num?)?.toInt() ?? 0;
    final int lowStock = (stockRow['low_stock'] as num?)?.toInt() ?? 0;
    final int totalProducts = (stockRow['total'] as num?)?.toInt() ?? 0;

    // 4. Ventas de los últimos 7 días para gráfico de barras
    final List<Map<String, dynamic>> weeklySales = [];
    final dayNames = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];

    for (int i = 6; i >= 0; i--) {
      final dayDate = now.subtract(Duration(days: i));
      final datePattern = "${dayDate.year.toString().padLeft(4, '0')}-${dayDate.month.toString().padLeft(2, '0')}-${dayDate.day.toString().padLeft(2, '0')}%";

      final dayRes = await db.rawQuery('''
        SELECT COALESCE(SUM(total), 0.0) as day_total 
        FROM sales 
        WHERE business_id = ? AND date LIKE ?
      ''', [businessId, datePattern]);

      final dayTotal = (dayRes.first['day_total'] as num?)?.toDouble() ?? 0.0;
      weeklySales.add({
        'day': dayNames[dayDate.weekday % 7],
        'total': dayTotal,
        'date': dayDate,
      });
    }

    // 5. Top 3 productos más vendidos
    final topProductsRes = await db.rawQuery('''
      SELECT 
        product_name, 
        SUM(quantity) as qty, 
        SUM(total) as revenue 
      FROM sales 
      WHERE business_id = ? 
      GROUP BY product_name 
      ORDER BY qty DESC 
      LIMIT 3
    ''', [businessId]);

    final topProducts = topProductsRes.map((r) => {
      'name': r['product_name'] as String,
      'qty': (r['qty'] as num).toInt(),
      'revenue': (r['revenue'] as num).toDouble(),
    }).toList();

    return {
      'todayTotal': todayTotal,
      'todayProfit': todayProfit,
      'todayUnits': todayUnits,
      'todayCount': todayCount,
      'totalDebt': totalDebt,
      'outOfStock': outOfStock,
      'lowStock': lowStock,
      'totalProducts': totalProducts,
      'weeklySales': weeklySales,
      'topProducts': topProducts,
    };
  }
}
