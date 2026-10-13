import 'package:sqflite/sqflite.dart';
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

    // Ticket promedio y margen porcentual
    final double averageTicket = todayCount > 0 ? (todayTotal / todayCount) : 0.0;
    final double profitMargin = todayTotal > 0 ? (todayProfit / todayTotal) * 100 : 0.0;

    // Ventas de ayer para cálculo de tendencia
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayPrefix = "${yesterday.year.toString().padLeft(4, '0')}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}%";
    final yesterdayRes = await db.rawQuery('''
      SELECT COALESCE(SUM(total), 0.0) as total_amount 
      FROM sales 
      WHERE business_id = ? AND date LIKE ?
    ''', [businessId, yesterdayPrefix]);
    final double yesterdayTotal = (yesterdayRes.first['total_amount'] as num?)?.toDouble() ?? 0.0;

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

    // 5. Top 5 productos más vendidos con porcentaje
    final topProductsRes = await db.rawQuery('''
      SELECT 
        product_name, 
        SUM(quantity) as qty, 
        SUM(total) as revenue 
      FROM sales 
      WHERE business_id = ? 
      GROUP BY product_name 
      ORDER BY qty DESC 
      LIMIT 5
    ''', [businessId]);

    double topMaxRevenue = 1.0;
    for (final r in topProductsRes) {
      final rev = (r['revenue'] as num?)?.toDouble() ?? 0.0;
      if (rev > topMaxRevenue) topMaxRevenue = rev;
    }

    final topProducts = topProductsRes.map((r) {
      final rev = (r['revenue'] as num).toDouble();
      return {
        'name': r['product_name'] as String,
        'qty': (r['qty'] as num).toInt(),
        'revenue': rev,
        'share': topMaxRevenue > 0 ? (rev / topMaxRevenue) : 0.0,
      };
    }).toList();

    return {
      'todayTotal': todayTotal,
      'todayProfit': todayProfit,
      'todayUnits': todayUnits,
      'todayCount': todayCount,
      'averageTicket': averageTicket,
      'profitMargin': profitMargin,
      'yesterdayTotal': yesterdayTotal,
      'totalDebt': totalDebt,
      'outOfStock': outOfStock,
      'lowStock': lowStock,
      'totalProducts': totalProducts,
      'weeklySales': weeklySales,
      'topProducts': topProducts,
    };
  }

  /// Lista predeterminada de acciones rápidas para el dashboard
  static const List<String> defaultQuickActions = [
    'sell',
    'add_product',
    'customers',
    'alerts',
  ];

  /// Obtiene las acciones rápidas preferidas por el usuario para una empresa
  Future<List<String>> getQuickActions(String businessId) async {
    try {
      final db = await _dbProvider.database;
      final key = 'quick_actions_$businessId';
      final res = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      if (res.isNotEmpty && res.first['value'] != null) {
        final val = res.first['value'] as String;
        final list = val.split(',').where((s) => s.trim().isNotEmpty).toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    return List.from(defaultQuickActions);
  }

  /// Guarda la personalización de acciones rápidas seleccionadas por el usuario
  Future<void> saveQuickActions(String businessId, List<String> actions) async {
    final db = await _dbProvider.database;
    final key = 'quick_actions_$businessId';
    final val = actions.join(',');
    await db.insert(
      'app_settings',
      {'key': key, 'value': val},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
