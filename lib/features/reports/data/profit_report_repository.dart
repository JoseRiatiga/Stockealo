import '../../sales/models/payment_method.dart';
import '../../cash/models/cash_session.dart';
import '../../../core/database/app_database.dart';
import '../../business/data/branch_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../../../core/utils/business_clock.dart';

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

  /// Salidas de caja de tipo «Gasto» en el periodo, sin las anuladas (0.16.8, #43)
  final double cashExpenses;

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
    this.cashExpenses = 0,
    required this.byPaymentMethod,
    required this.creditPending,
    required this.debtCollected,
    required this.topProducts,
    required this.lowMarginProducts,
    required this.previousGrossProfit,
  });

  double get grossProfit => revenue - cost;

  /// Ganancia después de descontar las mermas y los gastos registrados en caja
  double get netProfit => grossProfit - shrinkageLoss - cashExpenses;

  double get margin => revenue > 0 ? netProfit / revenue * 100 : 0;

  bool get isEmpty => salesCount == 0 && shrinkageUnits == 0 && cashExpenses == 0;

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
    final r = period.range(now ?? appNow());
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
      SELECT COUNT(DISTINCT ${SalesRepository.saleKey}) AS n,
             COALESCE(SUM(total), 0) AS revenue,
             COALESCE(SUM(total_cost), 0) AS cost,
             COALESCE(SUM(discount_amount), 0) AS discounts,
             -- Las devoluciones restan ganancia, pero no son ventas por debajo del costo (0.16.4)
             COALESCE(SUM(CASE WHEN net_profit < 0 AND return_of IS NULL THEN -net_profit ELSE 0 END), 0) AS below_cost
      FROM sales_here WHERE $inRange
    ''', args)).first;

    final previous = (await db.rawQuery('''
      SELECT COALESCE(SUM(total), 0) - COALESCE(SUM(total_cost), 0) AS gross
      FROM sales_here WHERE $inRange
    ''', [businessId, _iso(prevFrom), _iso(prevTo)])).first;

    // El pago mixto se reparte entre sus medios, igual que en Caja y Ventas (0.16.4)
    final methodRows = await db.rawQuery('''
      SELECT payment_method AS method, total, payment_split, payment_status
      FROM sales_here WHERE $inRange
    ''', args);
    final byMethod = <String, double>{};
    // Fiado sin pagar: también la parte fiada de un pago mixto (0.16.8)
    var creditPending = 0.0;
    for (final r in methodRows) {
      final status = r['payment_status'];
      if (status != null && status != 'PAGADO') {
        creditPending += PaymentMethod.creditPart('${r['method'] ?? ''}', (r['total'] as num?)?.toDouble() ?? 0, r['payment_split'] as String?);
      }
      final parts = PaymentMethod.amounts('${r['method'] ?? 'OTRO'}', (r['total'] as num?)?.toDouble() ?? 0, r['payment_split'] as String?);
      for (final e in parts.entries) {
        byMethod[e.key] = (byMethod[e.key] ?? 0) + e.value;
      }
    }
    final methods = byMethod.entries.where((e) => e.value.abs() >= 0.5).toList()..sort((a, b) => b.value.compareTo(a.value));

    // Mermas a costo actual del producto (el movimiento no guarda el costo de ese día)
    final shrinkage = (await db.rawQuery('''
      SELECT COALESCE(SUM(m.quantity), 0) AS units,
             COALESCE(SUM(m.quantity * COALESCE(p.purchase_price, 0)), 0) AS loss
      FROM stock_movements m LEFT JOIN products p ON p.id = m.product_id
      WHERE m.business_id = ? AND m.type = 'MERMA' AND m.date >= ? AND m.date < ?
    ''', args)).first;

    // Gastos de caja (0.16.8, #43): las salidas «Gasto» que nadie anuló. Retiros,
    // pagos a proveedor y propinas no son gasto del negocio
    final expenses = (await db.rawQuery('''
      SELECT COALESCE(SUM(m.amount), 0) AS amount
      FROM cash_movements m
      WHERE m.business_id = ? AND m.date >= ? AND m.date < ?
        AND m.kind = '${CashMovement.exit}' AND m.reason = 'GASTO'
        AND NOT EXISTS (
          SELECT 1 FROM cash_movements v
          WHERE v.business_id = m.business_id AND v.reason = '${CashMovement.voidReason}'
            AND v.note = '${CashMovement.voidNotePrefix}' || m.id
        )${BranchRepository.scope('m.branch_id')}
    ''', [...args, ...BranchRepository.scopeArgs()])).first;

    final collected = (await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS amount
      FROM customer_payments WHERE $inRange
    ''', args)).first;

    // Por producto, con su nombre de hoy: un producto renombrado no sale en dos filas (0.16.4)
    final products = await db.rawQuery('''
      SELECT COALESCE(MAX(p.name), MAX(s.product_name)) AS name,
             SUM(s.quantity) AS qty,
             SUM(s.total) AS revenue,
             SUM(s.net_profit) AS profit
      FROM sales_here s LEFT JOIN products p ON p.id = s.product_id
      WHERE s.business_id = ? AND s.date >= ? AND s.date < ?
      GROUP BY CASE WHEN s.product_id IS NULL OR s.product_id = '' THEN 'n:' || s.product_name ELSE s.product_id END
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
      cashExpenses: num0(expenses['amount']),
      byPaymentMethod: {for (final m in methods) m.key: m.value},
      creditPending: creditPending,
      debtCollected: num0(collected['amount']),
      topProducts: top.where((p) => p.profit > 0).take(5).toList(),
      lowMarginProducts: lowMargin.take(5).toList(),
      previousGrossProfit: num0(previous['gross']),
    );
  }
}
