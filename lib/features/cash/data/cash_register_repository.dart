import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../team/data/activity_repository.dart';
import '../models/cash_session.dart';

/// Arqueo de caja por negocio. Solo cuenta el efectivo: las ventas y abonos en
/// efectivo registrados desde que se abrió el turno. Las ventas anuladas ya no
/// existen en la tabla, así que no se cuentan.
class CashRegisterRepository {
  static final CashRegisterRepository instance = CashRegisterRepository();
  final AppDatabase _dbProvider = AppDatabase.instance;

  static const String _cash = 'EFECTIVO';

  Future<CashSession?> getOpenSession(String businessId) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'cash_sessions',
      where: 'business_id = ? AND closed_at IS NULL',
      whereArgs: [businessId],
      orderBy: 'opened_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : CashSession.fromMap(rows.first);
  }

  Future<CashSession> openSession({
    required String businessId,
    required double openingAmount,
    required String openedBy,
  }) async {
    if (openingAmount < 0) {
      throw Exception('La base inicial no puede ser negativa.');
    }
    if (await getOpenSession(businessId) != null) {
      throw Exception('Ya hay una caja abierta. Ciérrala antes de abrir otra.');
    }
    final session = CashSession(
      id: const Uuid().v4(),
      businessId: businessId,
      openedBy: openedBy,
      openedAt: DateTime.now(),
      openingAmount: openingAmount,
    );
    await (await _dbProvider.database).insert('cash_sessions', session.toMap());
    ActivityRepository.instance.log(
      businessId: businessId,
      action: ActivityAction.cashOpen,
      summary: 'Abrió la caja con ${CurrencyFormatter.format(openingAmount)} de base',
      data: {'session_id': session.id},
    );
    return session;
  }

  /// Efectivo que entró desde la apertura (o entre apertura y cierre)
  Future<CashSummary> summarize(CashSession session) async {
    final db = await _dbProvider.database;
    final from = session.openedAt.toIso8601String();
    final to = (session.closedAt ?? DateTime.now()).toIso8601String();

    final sales = await db.rawQuery('''
      SELECT COALESCE(SUM(total), 0) AS amount, COUNT(*) AS count FROM sales
      WHERE business_id = ? AND payment_method = ? AND date >= ? AND date <= ?
    ''', [session.businessId, _cash, from, to]);
    final payments = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS amount FROM customer_payments
      WHERE business_id = ? AND payment_method = ? AND date >= ? AND date <= ?
    ''', [session.businessId, _cash, from, to]);

    return CashSummary(
      openingAmount: session.openingAmount,
      cashSales: (sales.first['amount'] as num).toDouble(),
      cashSalesCount: (sales.first['count'] as num).toInt(),
      cashPayments: (payments.first['amount'] as num).toDouble(),
    );
  }

  Future<CashSession> closeSession({
    required CashSession session,
    required double countedAmount,
    String? notes,
  }) async {
    if (countedAmount < 0) {
      throw Exception('El efectivo contado no puede ser negativo.');
    }
    final closedAt = DateTime.now();
    final summary = await summarize(CashSession(
      id: session.id,
      businessId: session.businessId,
      openedBy: session.openedBy,
      openedAt: session.openedAt,
      openingAmount: session.openingAmount,
      closedAt: closedAt,
    ));
    final closed = CashSession(
      id: session.id,
      businessId: session.businessId,
      openedBy: session.openedBy,
      openedAt: session.openedAt,
      openingAmount: session.openingAmount,
      closedAt: closedAt,
      expectedAmount: summary.expected,
      countedAmount: countedAmount,
      notes: notes?.trim().isNotEmpty == true ? notes!.trim() : null,
    );
    await (await _dbProvider.database).update(
      'cash_sessions',
      closed.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
    final difference = countedAmount - summary.expected;
    ActivityRepository.instance.log(
      businessId: session.businessId,
      action: ActivityAction.cashClose,
      summary: 'Cerró la caja: contó ${CurrencyFormatter.format(countedAmount)} y se esperaban '
          '${CurrencyFormatter.format(summary.expected)}'
          '${difference == 0 ? ' (cuadró)' : difference > 0 ? ' (sobran ${CurrencyFormatter.format(difference)})' : ' (faltan ${CurrencyFormatter.format(-difference)})'}',
      data: {'session_id': session.id, 'difference': difference},
    );
    return closed;
  }

  Future<List<CashSession>> getClosedSessions(String businessId, {int limit = 30}) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'cash_sessions',
      where: 'business_id = ? AND closed_at IS NOT NULL',
      whereArgs: [businessId],
      orderBy: 'closed_at DESC',
      limit: limit,
    );
    return rows.map(CashSession.fromMap).toList();
  }
}
