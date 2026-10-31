import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';

class DashboardRepository {
  static final DashboardRepository instance = DashboardRepository._internal();
  DashboardRepository._internal();

  final AppDatabase _dbProvider = AppDatabase.instance;

  Future<Map<String, dynamic>> getDashboardSummary(
    String businessId, {
    String period = 'today',
  }) async {
    final db = await _dbProvider.database;
    final now = DateTime.now();

    // 1. Configuración de filtros según el periodo seleccionado
    String periodWhereSql = '';
    final List<dynamic> periodArgs = [businessId];
    String compareWhereSql = '';
    final List<dynamic> compareArgs = [businessId];
    String trendLabel = 'vs ayer';

    final todayPrefix = "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}%";
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayPrefix = "${yesterday.year.toString().padLeft(4, '0')}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}%";

    if (period == 'today') {
      periodWhereSql = 'AND s.date LIKE ?';
      periodArgs.add(todayPrefix);

      compareWhereSql = 'AND date LIKE ?';
      compareArgs.add(yesterdayPrefix);
      trendLabel = 'vs ayer';
    } else if (period == 'week') {
      final sevenDaysAgo = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      final sevenDaysIso = "${sevenDaysAgo.year.toString().padLeft(4, '0')}-${sevenDaysAgo.month.toString().padLeft(2, '0')}-${sevenDaysAgo.day.toString().padLeft(2, '0')}T00:00:00";
      final fourteenDaysAgo = sevenDaysAgo.subtract(const Duration(days: 7));
      final fourteenDaysIso = "${fourteenDaysAgo.year.toString().padLeft(4, '0')}-${fourteenDaysAgo.month.toString().padLeft(2, '0')}-${fourteenDaysAgo.day.toString().padLeft(2, '0')}T00:00:00";

      periodWhereSql = 'AND s.date >= ?';
      periodArgs.add(sevenDaysIso);

      compareWhereSql = 'AND date >= ? AND date < ?';
      compareArgs.addAll([fourteenDaysIso, sevenDaysIso]);
      trendLabel = 'vs 7 días previos';
    } else if (period == 'month') {
      final monthPrefix = "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}%";
      periodWhereSql = 'AND s.date LIKE ?';
      periodArgs.add(monthPrefix);

      final prevMonthYear = now.month == 1 ? now.year - 1 : now.year;
      final prevMonthNum = now.month == 1 ? 12 : now.month - 1;
      final prevMonthPrefix = "${prevMonthYear.toString().padLeft(4, '0')}-${prevMonthNum.toString().padLeft(2, '0')}%";

      compareWhereSql = 'AND date LIKE ?';
      compareArgs.add(prevMonthPrefix);
      trendLabel = 'vs mes anterior';
    } else {
      // 'all' -> Sin filtro de fecha
      periodWhereSql = '';
      compareWhereSql = '';
      trendLabel = 'total histórico';
    }

    // 2. Ventas y ganancias del periodo
    final salesRes = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        COALESCE(SUM(s.total), 0.0) as total_amount,
        COALESCE(SUM(s.net_profit), 0.0) as net_profit,
        COALESCE(SUM(s.quantity), 0) as units_sold
      FROM sales s
      WHERE s.business_id = ? $periodWhereSql
    ''', periodArgs);

    final periodSales = salesRes.isNotEmpty ? salesRes.first : {};
    final double periodTotal = (periodSales['total_amount'] as num?)?.toDouble() ?? 0.0;
    final double periodProfit = (periodSales['net_profit'] as num?)?.toDouble() ?? 0.0;
    final int periodUnits = (periodSales['units_sold'] as num?)?.toInt() ?? 0;
    final int periodCount = (periodSales['count'] as num?)?.toInt() ?? 0;

    final double averageTicket = periodCount > 0 ? (periodTotal / periodCount) : 0.0;
    final double profitMargin = periodTotal > 0 ? (periodProfit / periodTotal) * 100 : 0.0;

    // Ventas del periodo anterior para comparativa
    double compareTotal = 0.0;
    if (compareWhereSql.isNotEmpty) {
      final compRes = await db.rawQuery('''
        SELECT COALESCE(SUM(total), 0.0) as total_amount 
        FROM sales 
        WHERE business_id = ? $compareWhereSql
      ''', compareArgs);
      if (compRes.isNotEmpty) {
        compareTotal = (compRes.first['total_amount'] as num?)?.toDouble() ?? 0.0;
      }
    }

    // Referencia para el medidor de ventas: hoy se compara con el promedio diario de los
    // 7 días anteriores (un solo "ayer" puede ser atípico); los demás, con el periodo anterior
    double? salesReference;
    String? salesReferenceLabel;
    if (period == 'today') {
      final today0 = DateTime(now.year, now.month, now.day);
      final weekRes = await db.rawQuery('''
        SELECT COALESCE(SUM(total), 0.0) AS total_amount FROM sales
        WHERE business_id = ? AND date >= ? AND date < ?
      ''', [businessId, today0.subtract(const Duration(days: 7)).toIso8601String(), today0.toIso8601String()]);
      final weekTotal = (weekRes.first['total_amount'] as num?)?.toDouble() ?? 0.0;
      if (weekTotal > 0) {
        salesReference = weekTotal / 7;
        salesReferenceLabel = 'de tu día normal';
      }
    } else if (compareTotal > 0) {
      salesReference = compareTotal;
      salesReferenceLabel = period == 'week' ? 'de los 7 días previos' : 'del mes anterior';
    }

    // Abonos de fiados recibidos este mes (medidor de fiados)
    final monthStart = DateTime(now.year, now.month);
    final collectedRes = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0.0) AS amount FROM customer_payments
      WHERE business_id = ? AND date >= ?
    ''', [businessId, monthStart.toIso8601String()]);
    final double debtCollectedMonth = (collectedRes.first['amount'] as num?)?.toDouble() ?? 0.0;

    double? trendPercent;
    bool trendIsPositive = true;
    if (compareTotal > 0) {
      final diff = ((periodTotal - compareTotal) / compareTotal) * 100;
      trendPercent = diff;
      trendIsPositive = diff >= 0;
    } else if (periodTotal > 0 && compareWhereSql.isNotEmpty) {
      trendPercent = 100.0;
      trendIsPositive = true;
    }

    // Consulta específica de ventas de ayer para retrocompatibilidad
    final yesterdayRes = await db.rawQuery('''
      SELECT COALESCE(SUM(total), 0.0) as total_amount 
      FROM sales 
      WHERE business_id = ? AND date LIKE ?
    ''', [businessId, yesterdayPrefix]);
    final double yesterdayTotal = (yesterdayRes.first['total_amount'] as num?)?.toDouble() ?? 0.0;

    // 3. Deuda total pendiente por cobrar (Fiados)
    final debtRes = await db.rawQuery('''
      SELECT COALESCE(SUM(debt_balance), 0.0) as total_debt 
      FROM customers 
      WHERE business_id = ? AND debt_balance > 0
    ''', [businessId]);
    final double totalDebt = (debtRes.first['total_debt'] as num?)?.toDouble() ?? 0.0;

    // 4. Estado del stock y alertas
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

    // 5. Timeline de ventas dinámico según el periodo seleccionado (Hoy, 7 Días, Este Mes, Histórico)
    final List<Map<String, dynamic>> periodTimelineSales = [];
    final List<Map<String, dynamic>> weeklySales = [];
    final dayNames = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];

    if (period == 'today') {
      // 6 bloques horarios del día actual
      final todayDateStr = "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final timeSlots = [
        {'label': '6-9h', 'start': '06:00:00', 'end': '09:59:59'},
        {'label': '10-12h', 'start': '10:00:00', 'end': '12:59:59'},
        {'label': '13-15h', 'start': '13:00:00', 'end': '15:59:59'},
        {'label': '16-18h', 'start': '16:00:00', 'end': '18:59:59'},
        {'label': '19-21h', 'start': '19:00:00', 'end': '21:59:59'},
        {'label': '22h+', 'start': '22:00:00', 'end': '23:59:59'},
      ];

      for (final slot in timeSlots) {
        final startIso = "${todayDateStr}T${slot['start']}";
        final endIso = "${todayDateStr}T${slot['end']}";
        final slotRes = await db.rawQuery('''
          SELECT COALESCE(SUM(total), 0.0) as slot_total 
          FROM sales 
          WHERE business_id = ? AND date >= ? AND date <= ?
        ''', [businessId, startIso, endIso]);
        final slotTotal = (slotRes.first['slot_total'] as num?)?.toDouble() ?? 0.0;
        periodTimelineSales.add({
          'day': slot['label'] as String,
          'total': slotTotal,
        });
      }
    } else if (period == 'month') {
      // 4 semanas del mes actual
      final firstDayOfMonth = DateTime(now.year, now.month, 1);
      for (int w = 0; w < 4; w++) {
        final startDay = firstDayOfMonth.add(Duration(days: w * 7));
        final endDay = w == 3
            ? DateTime(now.year, now.month + 1, 0, 23, 59, 59)
            : startDay.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

        final startIso = "${startDay.year.toString().padLeft(4, '0')}-${startDay.month.toString().padLeft(2, '0')}-${startDay.day.toString().padLeft(2, '0')}T00:00:00";
        final endIso = "${endDay.year.toString().padLeft(4, '0')}-${endDay.month.toString().padLeft(2, '0')}-${endDay.day.toString().padLeft(2, '0')}T23:59:59";

        final weekRes = await db.rawQuery('''
          SELECT COALESCE(SUM(total), 0.0) as week_total 
          FROM sales 
          WHERE business_id = ? AND date >= ? AND date <= ?
        ''', [businessId, startIso, endIso]);
        final weekTotal = (weekRes.first['week_total'] as num?)?.toDouble() ?? 0.0;
        periodTimelineSales.add({
          'day': 'Sem ${w + 1}',
          'total': weekTotal,
        });
      }
    } else if (period == 'all') {
      // Últimos 6 meses
      final monthNames = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
      for (int m = 5; m >= 0; m--) {
        final targetMonthDate = DateTime(now.year, now.month - m, 1);
        final prefix = "${targetMonthDate.year.toString().padLeft(4, '0')}-${targetMonthDate.month.toString().padLeft(2, '0')}%";
        final mRes = await db.rawQuery('''
          SELECT COALESCE(SUM(total), 0.0) as m_total 
          FROM sales 
          WHERE business_id = ? AND date LIKE ?
        ''', [businessId, prefix]);
        final mTotal = (mRes.first['m_total'] as num?)?.toDouble() ?? 0.0;
        periodTimelineSales.add({
          'day': monthNames[targetMonthDate.month],
          'total': mTotal,
        });
      }
    } else {
      // Default / 'week': Últimos 7 días
      for (int i = 6; i >= 0; i--) {
        final dayDate = now.subtract(Duration(days: i));
        final datePattern = "${dayDate.year.toString().padLeft(4, '0')}-${dayDate.month.toString().padLeft(2, '0')}-${dayDate.day.toString().padLeft(2, '0')}%";

        final dayRes = await db.rawQuery('''
          SELECT COALESCE(SUM(total), 0.0) as day_total 
          FROM sales 
          WHERE business_id = ? AND date LIKE ?
        ''', [businessId, datePattern]);

        final dayTotal = (dayRes.first['day_total'] as num?)?.toDouble() ?? 0.0;
        final item = {
          'day': dayNames[dayDate.weekday % 7],
          'total': dayTotal,
          'date': dayDate,
        };
        periodTimelineSales.add(item);
        weeklySales.add(item);
      }
    }

    if (weeklySales.isEmpty) {
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
    }

    // 6. Distribución de ventas por Categoría (Para Gráfico de Pastel / Donut)
    final categorySalesRes = await db.rawQuery('''
      SELECT 
        COALESCE(p.category, 'General') as category_name,
        COALESCE(SUM(s.total), 0.0) as total_amount,
        COALESCE(SUM(s.quantity), 0) as units_sold
      FROM sales s
      LEFT JOIN products p ON s.product_id = p.id
      WHERE s.business_id = ? $periodWhereSql
      GROUP BY category_name
      ORDER BY total_amount DESC
    ''', periodArgs);

    final List<Map<String, dynamic>> categorySales = [];
    for (final row in categorySalesRes) {
      final double catTotal = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
      final int catUnits = (row['units_sold'] as num?)?.toInt() ?? 0;
      String catName = (row['category_name'] as String?)?.trim() ?? 'General';
      if (catName.isEmpty) catName = 'General';
      final double pct = periodTotal > 0 ? (catTotal / periodTotal) * 100 : 0.0;

      categorySales.add({
        'name': catName,
        'total': catTotal,
        'units': catUnits,
        'percentage': pct,
      });
    }

    // 7. Top 5 productos más vendidos en el periodo
    final topProductsRes = await db.rawQuery('''
      SELECT 
        s.product_name, 
        SUM(s.quantity) as qty, 
        SUM(s.total) as revenue 
      FROM sales s
      WHERE s.business_id = ? $periodWhereSql
      GROUP BY s.product_name 
      ORDER BY qty DESC 
      LIMIT 5
    ''', periodArgs);

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

    // 8. Últimas 5 transacciones registradas (para Bento feed de actividad)
    final recentSalesRes = await db.rawQuery('''
      SELECT 
        s.id,
        s.product_name,
        COALESCE(s.customer_name, 'Cliente sin registrar') as customer_name,
        s.quantity,
        s.total,
        s.payment_method,
        s.date
      FROM sales s
      WHERE s.business_id = ?
      ORDER BY s.date DESC
      LIMIT 5
    ''', [businessId]);

    final List<Map<String, dynamic>> recentTransactions = recentSalesRes.map((r) {
      return {
        'id': r['id'] as String,
        'title': r['product_name'] as String,
        'subtitle': "${r['quantity']} un. • ${r['customer_name']}",
        'amount': (r['total'] as num).toDouble(),
        'payment_method': r['payment_method'] as String? ?? 'EFECTIVO',
        'date': r['date'] as String,
      };
    }).toList();

    return {
      'period': period,
      'periodTotal': periodTotal,
      'periodProfit': periodProfit,
      'periodUnits': periodUnits,
      'periodCount': periodCount,
      'todayTotal': periodTotal,
      'todayProfit': periodProfit,
      'todayUnits': periodUnits,
      'todayCount': periodCount,
      'averageTicket': averageTicket,
      'profitMargin': profitMargin,
      'compareTotal': compareTotal,
      'trendPercent': trendPercent,
      'trendIsPositive': trendIsPositive,
      'trendLabel': trendLabel,
      'yesterdayTotal': yesterdayTotal,
      'totalDebt': totalDebt,
      'debtCollectedMonth': debtCollectedMonth,
      'salesReference': salesReference,
      'salesReferenceLabel': salesReferenceLabel,
      'outOfStock': outOfStock,
      'lowStock': lowStock,
      'totalProducts': totalProducts,
      'weeklySales': weeklySales,
      'periodTimelineSales': periodTimelineSales,
      'categorySales': categorySales,
      'topProducts': topProducts,
      'recentTransactions': recentTransactions,
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
