import '../../../core/database/app_database.dart';

/// Periodos del reporte de ganancias
enum ReportPeriod {
  today('Hoy', 'ayer'),
  week('7 días', 'los 7 días anteriores'),
  month('Este mes', 'el mes pasado'),
  lastMonth('Mes pasado', 'el mes anterior'),
  year('Este año', 'el año pasado');

  final String label;

  /// Con qué se compara, para el texto "vs …"
  final String compareLabel;

  const ReportPeriod(this.label, this.compareLabel);

  /// Rango [desde, hasta) del periodo y del periodo anterior equivalente
  ({DateTime from, DateTime to, DateTime prevFrom, DateTime prevTo}) range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case ReportPeriod.today:
        return (
          from: today,
          to: today.add(const Duration(days: 1)),
          prevFrom: today.subtract(const Duration(days: 1)),
          prevTo: today,
        );
      case ReportPeriod.week:
        final from = today.subtract(const Duration(days: 6));
        return (
          from: from,
          to: today.add(const Duration(days: 1)),
          prevFrom: from.subtract(const Duration(days: 7)),
          prevTo: from,
        );
      case ReportPeriod.month:
        final from = DateTime(now.year, now.month);
        return (from: from, to: DateTime(now.year, now.month + 1), prevFrom: DateTime(now.year, now.month - 1), prevTo: from);
      case ReportPeriod.lastMonth:
        final from = DateTime(now.year, now.month - 1);
        return (from: from, to: DateTime(now.year, now.month), prevFrom: DateTime(now.year, now.month - 2), prevTo: from);
      case ReportPeriod.year:
        final from = DateTime(now.year);
        return (from: from, to: DateTime(now.year + 1), prevFrom: DateTime(now.year - 1), prevTo: from);
    }
  }
}

/// Un producto en el reporte: lo que dejó en el periodo
class ProductProfit {
  final String name;
  final int quantity;
  final double revenue;
  final double profit;

  const ProductProfit({required this.name, required this.quantity, required this.revenue, required this.profit});

  double get margin => revenue > 0 ? profit / revenue * 100 : 0;
}

/// Resultado del negocio en un periodo. Todo sale de las ventas y movimientos guardados
/// en el celular; los gastos fijos (arriendo, servicios) todavía no se registran en la app.
class ProfitReport {
  final double revenue;
  final double cost;
  final double discounts;
  final int salesCount;

  /// Lo que se perdió en ventas por debajo del costo
  final double belowCostLoss;

  /// Mermas: unidades que salieron del inventario sin venderse, valoradas a costo
  final double shrinkageLoss;
  final int shrinkageUnits;

  final Map<String, double> byPaymentMethod;

  /// Fiado vendido en el periodo que sigue sin pagarse
  final double creditPending;

  /// Abonos de fiados recibidos en el periodo (de ventas de este u otros periodos)
  final double debtCollected;

  final List<ProductProfit> topProducts;
  final List<ProductProfit> lowMarginProducts;

  /// Ganancia bruta del periodo anterior, para comparar
  final double previousGrossProfit;

  const ProfitReport({
    required this.revenue,
    required this.cost,
    required this.discounts,
    required this.salesCount,
    required this.belowCostLoss,
    required this.shrinkageLoss,
    required this.shrinkageUnits,
    required this.byPaymentMethod,
    required this.creditPending,
    required this.debtCollected,
    required this.topProducts,
    required this.lowMarginProducts,
    required this.previousGrossProfit,
  });

  double get grossProfit => revenue - cost;

  /// Ganancia después de descontar las mermas
  double get netProfit => grossProfit - shrinkageLoss;

  double get margin => revenue > 0 ? netProfit / revenue * 100 : 0;

  bool get isEmpty => salesCount == 0 && shrinkageUnits == 0;

  /// Cambio de la ganancia bruta frente al periodo anterior, en %. Null si no hay con qué comparar.
  double? get change {
    if (previousGrossProfit == 0) return null;
    return (grossProfit - previousGrossProfit) / previousGrossProfit.abs() * 100;
  }
}

class ProfitReportRepository {
  ProfitReportRepository._();
  static final ProfitReportRepository instance = ProfitReportRepository._();

  static String _iso(DateTime d) => d.toIso8601String();

  Future<ProfitReport> build(String businessId, ReportPeriod period, {DateTime? now}) async {
    final r = period.range(now ?? DateTime.now());
    return buildRange(businessId, r.from, r.to, prevFrom: r.prevFrom, prevTo: r.prevTo);
  }

  Future<ProfitReport> buildRange(
    String businessId,
    DateTime from,
    DateTime to, {
    required DateTime prevFrom,
    required DateTime prevTo,
  }) async {
    final db = await AppDatabase.instance.database;
    final args = [businessId, _iso(from), _iso(to)];
    const inRange = 'business_id = ? AND date >= ? AND date < ?';

    final totals = (await db.rawQuery('''
      SELECT COUNT(*) AS n,
             COALESCE(SUM(total), 0) AS revenue,
             COALESCE(SUM(total_cost), 0) AS cost,
             COALESCE(SUM(discount_amount), 0) AS discounts,
             COALESCE(SUM(CASE WHEN net_profit < 0 THEN -net_profit ELSE 0 END), 0) AS below_cost,
             COALESCE(SUM(CASE WHEN payment_method = 'FIADO' AND payment_status != 'PAGADO' THEN total ELSE 0 END), 0) AS credit_pending
      FROM sales WHERE $inRange
    ''', args)).first;

    final previous = (await db.rawQuery('''
      SELECT COALESCE(SUM(total), 0) - COALESCE(SUM(total_cost), 0) AS gross
      FROM sales WHERE $inRange
    ''', [businessId, _iso(prevFrom), _iso(prevTo)])).first;

    final methods = await db.rawQuery('''
      SELECT payment_method AS method, SUM(total) AS amount
      FROM sales WHERE $inRange
      GROUP BY payment_method ORDER BY amount DESC
    ''', args);

    // Mermas a costo actual del producto (el movimiento no guarda el costo de ese día)
    final shrinkage = (await db.rawQuery('''
      SELECT COALESCE(SUM(m.quantity), 0) AS units,
             COALESCE(SUM(m.quantity * COALESCE(p.purchase_price, 0)), 0) AS loss
      FROM stock_movements m LEFT JOIN products p ON p.id = m.product_id
      WHERE m.business_id = ? AND m.type = 'MERMA' AND m.date >= ? AND m.date < ?
    ''', args)).first;

    final collected = (await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS amount
      FROM customer_payments WHERE $inRange
    ''', args)).first;

    final products = await db.rawQuery('''
      SELECT product_name AS name,
             SUM(quantity) AS qty,
             SUM(total) AS revenue,
             SUM(net_profit) AS profit
      FROM sales WHERE $inRange
      GROUP BY product_name
    ''', args);

    final perProduct = [
      for (final row in products)
        ProductProfit(
          name: row['name'] as String,
          quantity: (row['qty'] as num?)?.toInt() ?? 0,
          revenue: (row['revenue'] as num?)?.toDouble() ?? 0,
          profit: (row['profit'] as num?)?.toDouble() ?? 0,
        ),
    ];
    final top = [...perProduct]..sort((a, b) => b.profit.compareTo(a.profit));
    final lowMargin = perProduct.where((p) => p.revenue > 0 && p.margin < 15).toList()
      ..sort((a, b) => a.margin.compareTo(b.margin));

    double num0(Object? v) => (v as num?)?.toDouble() ?? 0;

    return ProfitReport(
      revenue: num0(totals['revenue']),
      cost: num0(totals['cost']),
      discounts: num0(totals['discounts']),
      salesCount: (totals['n'] as num?)?.toInt() ?? 0,
      belowCostLoss: num0(totals['below_cost']),
      shrinkageLoss: num0(shrinkage['loss']),
      shrinkageUnits: (shrinkage['units'] as num?)?.toInt() ?? 0,
      byPaymentMethod: {for (final m in methods) m['method'] as String: num0(m['amount'])},
      creditPending: num0(totals['credit_pending']),
      debtCollected: num0(collected['amount']),
      topProducts: top.where((p) => p.profit > 0).take(5).toList(),
      lowMarginProducts: lowMargin.take(5).toList(),
      previousGrossProfit: num0(previous['gross']),
    );
  }
}
