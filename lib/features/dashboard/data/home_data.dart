import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../cash/data/cash_register_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../../store/data/store_orders_repository.dart';

/// Rango del gráfico de ventas del Inicio
enum HomeRange { days14, month, year }

/// Una barra del gráfico: un día (14 días o mes) o un mes (año)
class HomeBar {
  final DateTime start;
  final double total;
  final int count;

  /// Es hoy (o este mes): va en el color del negocio
  final bool current;

  const HomeBar({required this.start, required this.total, required this.count, this.current = false});
}

/// Qué pide atención en el Inicio, de lo más urgente a lo menos
enum AttentionKind { outOfStock, cashLeftOpen, overdueDebt, lowStock, storeOrders, toDeliver }

/// Un aviso de «Necesita atención». Trae lo necesario para explicar por qué pasó
/// y para resolverlo desde su panel, sin volver a consultar.
class AttentionItem {
  final AttentionKind kind;

  /// Producto, cliente o turno de caja
  final String refId;
  final String name;

  // Producto
  final int stock;
  final int minStock;
  final int soldThisWeek;
  final DateTime? lastEntry;
  final String? supplierId;

  // Cliente
  final double amount;
  final String? phone;
  final int days;
  final bool neverPaid;

  // Caja
  final DateTime? since;

  /// Pedidos de la tienda por confirmar o ventas por entregar (0.13.4)
  final int count;

  const AttentionItem({
    required this.kind,
    required this.refId,
    required this.name,
    this.stock = 0,
    this.minStock = 0,
    this.soldThisWeek = 0,
    this.lastEntry,
    this.supplierId,
    this.amount = 0,
    this.phone,
    this.days = 0,
    this.neverPaid = false,
    this.since,
    this.count = 0,
  });
}

/// Todo lo que muestra el Inicio, en una sola lectura de la base del dispositivo
class HomeData {
  final double todayTotal;
  final int todayCount;

  /// Lo vendido el mismo día de la semana pasada (null si ese día no hubo ventas)
  final double? lastWeekSameDay;

  /// Ventas de hoy por hora, de 8 a. m. a 7 p. m. (12 barras)
  final List<double> todayByHour;

  final double monthProfit;

  /// Ganancia del mes anterior en los mismos días (null si no hubo)
  final double? prevMonthProfit;

  final double debtTotal;
  final int debtCustomers;
  final int overdueCustomers;

  final int restockCount;
  final int outOfStockCount;

  final List<HomeBar> bars;
  final List<({String name, int units})> topWeek;

  /// Avisos en orden de urgencia (todos; el Inicio muestra los primeros)
  final List<AttentionItem> attention;

  const HomeData({
    this.todayTotal = 0,
    this.todayCount = 0,
    this.lastWeekSameDay,
    this.todayByHour = const [],
    this.monthProfit = 0,
    this.prevMonthProfit,
    this.debtTotal = 0,
    this.debtCustomers = 0,
    this.overdueCustomers = 0,
    this.restockCount = 0,
    this.outOfStockCount = 0,
    this.bars = const [],
    this.topWeek = const [],
    this.attention = const [],
  });

  /// Cambio en % frente a una referencia; null si no hay con qué comparar
  static double? change(double now, double? before) => before == null || before <= 0 ? null : (now - before) / before * 100;

  double? get todayChange => change(todayTotal, lastWeekSameDay);
  double? get profitChange => change(monthProfit, prevMonthProfit);
}

/// Lee los datos del Inicio. Un fiado se considera vencido después de [overdueDays].
class HomeRepository {
  HomeRepository._();
  static final HomeRepository instance = HomeRepository._();

  static const overdueDays = 30;

  /// Una venta = un número de factura (cada producto vendido es una fila)
  static const _saleKey = 'COALESCE(invoice_number, id)';

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<HomeData> load(String businessId, {HomeRange range = HomeRange.days14, DateTime? now}) async {
    final db = await AppDatabase.instance.database;
    final at = now ?? DateTime.now();
    final today = DateTime(at.year, at.month, at.day);
    final tomorrow = today.add(const Duration(days: 1));

    // Hoy y el mismo día de la semana pasada
    final todayRow = (await db.rawQuery(
      'SELECT COALESCE(SUM(total), 0) AS t, COUNT(DISTINCT $_saleKey) AS n FROM sales_ok WHERE business_id = ? AND date >= ? AND date < ?',
      [businessId, today.toIso8601String(), tomorrow.toIso8601String()],
    ))
        .first;
    final lastWeek = today.subtract(const Duration(days: 7));
    final lastWeekTotal = await _sum(db, 'total', businessId, lastWeek, lastWeek.add(const Duration(days: 1)));

    // Hoy por hora (8 a. m. a 7 p. m.)
    final hours = await db.rawQuery(
      "SELECT CAST(substr(date, 12, 2) AS INTEGER) AS h, SUM(total) AS t FROM sales_ok WHERE business_id = ? AND date >= ? AND date < ? GROUP BY h",
      [businessId, today.toIso8601String(), tomorrow.toIso8601String()],
    );
    final byHour = List<double>.filled(12, 0);
    for (final r in hours) {
      final h = (r['h'] as int?) ?? 0;
      byHour[(h - 8).clamp(0, 11)] += (r['t'] as num?)?.toDouble() ?? 0;
    }

    // Ganancia del mes frente a los mismos días del mes anterior
    final monthStart = DateTime(at.year, at.month);
    final prevStart = DateTime(at.year, at.month - 1);
    final prevEnd = DateTime(prevStart.year, prevStart.month, at.day).add(const Duration(days: 1));
    final prevMonthEnd = DateTime(at.year, at.month);
    final monthProfit = await _sum(db, 'net_profit', businessId, monthStart, tomorrow);
    final prevProfit = await _sum(db, 'net_profit', businessId, prevStart, prevEnd.isAfter(prevMonthEnd) ? prevMonthEnd : prevEnd);

    // Fiados: quién debe y desde cuándo no abona
    final debtRows = await db.rawQuery('''
      SELECT c.id, c.name, c.phone, c.debt_balance, c.created_at,
        (SELECT MAX(p.date) FROM customer_payments p WHERE p.customer_id = c.id) AS last_payment,
        (SELECT MIN(s.date) FROM sales_ok s WHERE s.customer_id = c.id AND s.payment_method = 'FIADO') AS first_credit
      FROM customers c
      WHERE c.business_id = ? AND c.debt_balance > 0
      ORDER BY c.debt_balance DESC
    ''', [businessId]);
    var debtTotal = 0.0;
    final overdue = <AttentionItem>[];
    for (final r in debtRows) {
      final amount = (r['debt_balance'] as num?)?.toDouble() ?? 0;
      debtTotal += amount;
      final lastPayment = DateTime.tryParse('${r['last_payment']}');
      final since = lastPayment ?? DateTime.tryParse('${r['first_credit']}') ?? DateTime.tryParse('${r['created_at']}');
      if (since == null) continue;
      final days = today.difference(DateTime(since.year, since.month, since.day)).inDays;
      if (days > overdueDays) {
        overdue.add(AttentionItem(
          kind: AttentionKind.overdueDebt,
          refId: '${r['id']}',
          name: '${r['name']}',
          amount: amount,
          phone: r['phone'] as String?,
          days: days,
          neverPaid: lastPayment == null,
        ));
      }
    }
    overdue.sort((a, b) => b.days.compareTo(a.days));

    // Stock: agotados (los que más se venden primero) y los que están por acabarse
    final weekAgo = today.subtract(const Duration(days: 6));
    final stockRows = await db.rawQuery('''
      SELECT p.id, p.name, p.stock, p.min_stock, p.supplier_id,
        (SELECT COALESCE(SUM(s.quantity), 0) FROM sales_ok s WHERE s.product_id = p.id AND s.date >= ?) AS sold_week,
        (SELECT MAX(m.date) FROM stock_movements m WHERE m.product_id = p.id AND m.type LIKE 'ENTRADA%') AS last_entry
      FROM products p
      WHERE p.business_id = ? AND p.is_active = 1 AND p.stock <= p.min_stock
      ORDER BY p.stock <= 0 DESC, sold_week DESC, p.stock ASC
    ''', [weekAgo.toIso8601String(), businessId]);
    final out = <AttentionItem>[];
    final low = <AttentionItem>[];
    for (final r in stockRows) {
      final item = AttentionItem(
        kind: ((r['stock'] as num?) ?? 0) <= 0 ? AttentionKind.outOfStock : AttentionKind.lowStock,
        refId: '${r['id']}',
        name: '${r['name']}',
        stock: (r['stock'] as num?)?.toInt() ?? 0,
        minStock: (r['min_stock'] as num?)?.toInt() ?? 0,
        soldThisWeek: (r['sold_week'] as num?)?.toInt() ?? 0,
        lastEntry: DateTime.tryParse('${r['last_entry']}'),
        supplierId: r['supplier_id'] as String?,
      );
      (item.kind == AttentionKind.outOfStock ? out : low).add(item);
    }

    // Caja que quedó abierta de un día anterior
    final cash = <AttentionItem>[];
    try {
      final session = await CashRegisterRepository.instance.getOpenSession(businessId);
      if (session != null && session.openedAt.isBefore(today)) {
        cash.add(AttentionItem(kind: AttentionKind.cashLeftOpen, refId: session.id, name: 'Caja', since: session.openedAt));
      }
    } catch (_) {}

    // Pedidos de la tienda por confirmar y lo cobrado que falta entregar (0.13.4)
    final orders = <AttentionItem>[];
    try {
      await StoreOrdersRepository.instance.pull(businessId);
      final pendingOrders = await StoreOrdersRepository.instance.pendingCount(businessId);
      if (pendingOrders > 0) {
        orders.add(AttentionItem(kind: AttentionKind.storeOrders, refId: 'store', name: 'Pedidos', count: pendingOrders));
      }
      final deliveries = await SalesRepository.instance.pendingDeliveries(businessId);
      if (deliveries.isNotEmpty) {
        orders.add(AttentionItem(kind: AttentionKind.toDeliver, refId: 'deliver', name: 'Entregas', count: deliveries.length));
      }
    } catch (_) {}

    // Lo más vendido en los últimos 7 días
    final top = await db.rawQuery(
      'SELECT product_name AS name, SUM(quantity) AS u FROM sales_ok WHERE business_id = ? AND date >= ? GROUP BY product_name ORDER BY u DESC LIMIT 5',
      [businessId, weekAgo.toIso8601String()],
    );

    return HomeData(
      todayTotal: (todayRow['t'] as num?)?.toDouble() ?? 0,
      todayCount: (todayRow['n'] as num?)?.toInt() ?? 0,
      lastWeekSameDay: lastWeekTotal > 0 ? lastWeekTotal : null,
      todayByHour: byHour,
      monthProfit: monthProfit,
      prevMonthProfit: prevProfit > 0 ? prevProfit : null,
      debtTotal: debtTotal,
      debtCustomers: debtRows.length,
      overdueCustomers: overdue.length,
      restockCount: stockRows.length,
      outOfStockCount: out.length,
      bars: await bars(businessId, range, now: at),
      topWeek: [for (final r in top) (name: '${r['name']}', units: (r['u'] as num?)?.toInt() ?? 0)],
      attention: [...out, ...cash, ...orders, ...overdue, ...low],
    );
  }

  /// Barras del gráfico: 14 días, los días del mes o los 12 meses del año
  Future<List<HomeBar>> bars(String businessId, HomeRange range, {DateTime? now}) async {
    final db = await AppDatabase.instance.database;
    final at = now ?? DateTime.now();
    final today = DateTime(at.year, at.month, at.day);
    final byMonth = range == HomeRange.year;
    final starts = switch (range) {
      HomeRange.days14 => [for (var i = 13; i >= 0; i--) today.subtract(Duration(days: i))],
      HomeRange.month => [for (var d = 1; d <= at.day; d++) DateTime(at.year, at.month, d)],
      HomeRange.year => [for (var m = 11; m >= 0; m--) DateTime(at.year, at.month - m)],
    };
    final keyLen = byMonth ? 7 : 10;
    final rows = await db.rawQuery(
      'SELECT substr(date, 1, $keyLen) AS k, SUM(total) AS t, COUNT(DISTINCT $_saleKey) AS n FROM sales_ok WHERE business_id = ? AND date >= ? GROUP BY k',
      [businessId, starts.first.toIso8601String()],
    );
    final map = {for (final r in rows) '${r['k']}': r};
    return [
      for (final s in starts)
        () {
          final r = map[_day(s).substring(0, keyLen)];
          return HomeBar(
            start: s,
            total: (r?['t'] as num?)?.toDouble() ?? 0,
            count: (r?['n'] as num?)?.toInt() ?? 0,
            current: byMonth ? (s.year == at.year && s.month == at.month) : s == today,
          );
        }(),
    ];
  }

  static Future<double> _sum(Database db, String column, String businessId, DateTime from, DateTime to) async {
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM($column), 0) AS v FROM sales_ok WHERE business_id = ? AND date >= ? AND date < ?',
      [businessId, from.toIso8601String(), to.toIso8601String()],
    );
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }
}
