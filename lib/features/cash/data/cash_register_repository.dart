import 'package:sqflite/sqflite.dart' show DatabaseException;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/data_events.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/data/auth_repository.dart';
import '../../team/data/activity_repository.dart';
import '../../business/models/business.dart';
import '../models/cash_session.dart';
import '../../sales/models/payment_method.dart';

/// Arqueo de caja por negocio (0.12.0: con movimientos, propinas, cierre por forma
/// de pago y en la nube).
///
/// El efectivo esperado es: base + ventas y abonos en efectivo + propinas cobradas
/// en efectivo − propinas entregadas + entradas − salidas − mercancía de contado.
/// Las ventas anuladas ya no existen en la tabla, así que no se cuentan.
class CashRegisterRepository {
  static final CashRegisterRepository instance = CashRegisterRepository();
  final AppDatabase _dbProvider = AppDatabase.instance;
  final _cloud = SupabaseService.instance;

  static const String _cash = 'EFECTIVO';

  /// Lanza [CashClosedException] si el negocio usa caja y no hay una abierta.
  /// Lo llaman todas las formas de registrar una venta.
  Future<void> requireOpen(String businessId) async {
    final db = await _dbProvider.database;
    final rows = await db.query('businesses', columns: ['cash_register_enabled'], where: 'id = ?', whereArgs: [businessId], limit: 1);
    if (rows.isEmpty || (rows.first['cash_register_enabled'] as int? ?? 0) != 1) return;
    if (await getOpenSession(businessId) == null) throw const CashClosedException();
  }

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

  Future<void> _store(CashSession s, {bool insert = false}) async {
    final db = await _dbProvider.database;
    final row = s.toMap();
    if (insert) {
      await db.insert('cash_sessions', row);
    } else {
      await db.update('cash_sessions', row, where: 'id = ?', whereArgs: [s.id]);
    }
    _cloud.upsertCashSessionToCloud(row);
  }

  Future<CashSession> openSession({
    required String businessId,
    required double openingAmount,
    required String openedBy,
    DateTime? now,
  }) async {
    if (openingAmount < 0) {
      throw Exception('La base inicial no puede ser negativa.');
    }
    if (await getOpenSession(businessId) != null) {
      throw Exception('Ya hay una caja abierta. Ciérrala antes de abrir otra.');
    }
    final at = now ?? DateTime.now();
    final session = CashSession(
      id: const Uuid().v4(),
      businessId: businessId,
      openedBy: openedBy,
      openedAt: at,
      openingAmount: openingAmount,
      updatedAt: at,
    );
    await _store(session, insert: true);
    ActivityRepository.instance.log(
      businessId: businessId,
      action: ActivityAction.cashOpen,
      summary: 'Abrió la caja con ${CurrencyFormatter.format(openingAmount)} de base',
      data: {'session_id': session.id},
    );
    DataEvents.instance.cashChanged();
    return session;
  }

  // ---------------------------------------------------------------------------
  // Movimientos
  // ---------------------------------------------------------------------------

  Future<CashMovement> addMovement({
    required CashSession session,
    required String kind,
    required String reason,
    required double amount,
    String? note,
    DateTime? now,
  }) async {
    if (!session.isOpen) throw StateError('La caja ya está cerrada.');
    if (amount <= 0) throw StateError('Escribe un valor mayor que cero.');
    final m = CashMovement(
      id: const Uuid().v4(),
      businessId: session.businessId,
      sessionId: session.id,
      kind: kind,
      reason: reason,
      amount: amount,
      note: (note ?? '').trim().isEmpty ? null : note!.trim(),
      createdBy: AuthRepository.instance.currentUser?.email,
      date: now ?? DateTime.now(),
    );
    final db = await _dbProvider.database;
    final row = m.toMap();
    await db.insert('cash_movements', row);
    _cloud.upsertCashMovementToCloud(row);
    ActivityRepository.instance.log(
      businessId: session.businessId,
      action: 'cash_movement',
      summary: '${m.isExit ? 'Sacó' : 'Metió'} ${CurrencyFormatter.format(amount)} de la caja: '
          '${m.reasonLabel.toLowerCase()}${m.note == null ? '' : ' (${m.note})'}',
      data: {'session_id': session.id, 'movement_id': m.id},
    );
    return m;
  }

  Future<List<CashMovement>> movements(CashSession session) async {
    final db = await _dbProvider.database;
    final rows = await db.query('cash_movements', where: 'session_id = ?', whereArgs: [session.id], orderBy: 'date ASC');
    return rows.map(CashMovement.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Resumen
  // ---------------------------------------------------------------------------

  /// Lo que pasó entre la apertura y el cierre (o ahora)
  Future<CashSummary> summarize(CashSession session, {DateTime? until}) async {
    final db = await _dbProvider.database;
    final fromAt = session.openedAt;
    final toAt = session.closedAt ?? until ?? DateTime.now();
    final from = fromAt.toIso8601String();
    final to = toAt.toIso8601String();
    final biz = session.businessId;

    // Ventas y abonos por forma de pago
    final byMethod = <String, double>{};
    var cashSales = 0.0;
    var cashSalesCount = 0;
    // Un pago mixto suma a cada medio lo que entró por él; una venta es un número
    final cashInvoices = <String>{};
    final sales = await db.rawQuery('''
      SELECT payment_method AS method, total, payment_split, COALESCE(invoice_number, id) AS invoice FROM sales_ok
      WHERE business_id = ? AND date >= ? AND date <= ?
    ''', [biz, from, to]);
    for (final r in sales) {
      final parts = PaymentMethod.amounts('${r['method'] ?? 'OTRO'}', (r['total'] as num).toDouble(), r['payment_split'] as String?);
      for (final e in parts.entries) {
        byMethod[e.key] = (byMethod[e.key] ?? 0) + e.value;
        if (e.key == _cash && e.value > 0) {
          cashSales += e.value;
          cashInvoices.add('${r['invoice']}');
        }
      }
    }
    cashSalesCount = cashInvoices.length;
    var cashPayments = 0.0;
    final payments = await db.rawQuery('''
      SELECT payment_method AS method, COALESCE(SUM(amount), 0) AS amount FROM customer_payments
      WHERE business_id = ? AND date >= ? AND date <= ? GROUP BY payment_method
    ''', [biz, from, to]);
    for (final r in payments) {
      final method = '${r['method'] ?? 'OTRO'}'.toUpperCase();
      final amount = (r['amount'] as num).toDouble();
      byMethod['ABONO_$method'] = (byMethod['ABONO_$method'] ?? 0) + amount;
      if (method == _cash) cashPayments += amount;
    }

    // Propinas cobradas en efectivo (trabajos de servicios entregados en el turno)
    var tipsIn = 0.0;
    try {
      final tips = await db.rawQuery('''
        SELECT COALESCE(SUM(tip), 0) AS amount FROM work_orders
        WHERE business_id = ? AND payment_method = ? AND status = 'ENTREGADA' AND tip > 0
          AND updated_at >= ? AND updated_at <= ?
      ''', [biz, _cash, from, to]);
      tipsIn = (tips.first['amount'] as num).toDouble();
    } on DatabaseException {
      tipsIn = 0;
    }

    // Entradas y salidas a mano
    var entries = 0.0, exits = 0.0, tipsOut = 0.0;
    for (final m in await movements(session)) {
      if (!m.isExit) {
        entries += m.amount;
      } else if (m.reason == 'PROPINA') {
        tipsOut += m.amount;
      } else {
        exits += m.amount;
      }
    }

    // Mercancía que llegó pagada de contado
    var cashPurchases = 0.0;
    try {
      final purchases = await db.rawQuery('''
        SELECT COALESCE(SUM(total), 0) AS amount FROM purchases
        WHERE business_id = ? AND payment_terms = 'CONTADO' AND date >= ? AND date <= ?
      ''', [biz, from, to]);
      cashPurchases = (purchases.first['amount'] as num).toDouble();
    } on DatabaseException {
      cashPurchases = 0;
    }

    return CashSummary(
      openingAmount: session.openingAmount,
      cashSales: cashSales,
      cashSalesCount: cashSalesCount,
      cashPayments: cashPayments,
      tipsIn: tipsIn,
      tipsOut: tipsOut,
      entries: entries,
      exits: exits,
      cashPurchases: cashPurchases,
      byMethod: byMethod,
    );
  }

  /// Cierra el turno. Si el conteo no cuadra con lo esperado, la nota es obligatoria.
  Future<CashSession> closeSession({
    required CashSession session,
    required double countedAmount,
    String? notes,
    Map<int, int> denominations = const {},
    Map<String, dynamic> extra = const {},
    DateTime? now,
  }) async {
    if (countedAmount < 0) {
      throw Exception('El efectivo contado no puede ser negativo.');
    }
    final closedAt = now ?? DateTime.now();
    final summary = await summarize(session.copyWith(closedAt: closedAt));
    final difference = countedAmount - summary.expected;
    final cleanNotes = (notes ?? '').trim();
    if (difference.abs() >= 1 && cleanNotes.isEmpty) {
      throw StateError('La caja no cuadra: escribe una nota que explique la diferencia.');
    }
    final closed = session.copyWith(
      closedAt: closedAt,
      closedBy: AuthRepository.instance.currentUser?.email,
      expectedAmount: summary.expected,
      countedAmount: countedAmount,
      notes: cleanNotes.isEmpty ? null : cleanNotes,
      summary: {
        ...summary.toJson(),
        if (denominations.isNotEmpty) 'denominations': {for (final e in denominations.entries) '${e.key}': e.value},
        ...extra,
      },
      updatedAt: closedAt,
    );
    await _store(closed);
    ActivityRepository.instance.log(
      businessId: session.businessId,
      action: ActivityAction.cashClose,
      summary: 'Cerró la caja: contó ${CurrencyFormatter.format(countedAmount)} y se esperaban '
          '${CurrencyFormatter.format(summary.expected)}'
          '${difference.abs() < 1 ? ' (cuadró)' : difference > 0 ? ' (sobran ${CurrencyFormatter.format(difference)})' : ' (faltan ${CurrencyFormatter.format(-difference)})'}',
      data: {'session_id': session.id, 'difference': difference},
    );
    DataEvents.instance.cashChanged();
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

  /// Nombre de cada forma de pago en el resumen
  static String methodLabel(String code) => switch (code) {
        'ABONO_EFECTIVO' => 'Abonos en efectivo',
        'ABONO_TRANSFERENCIA' => 'Abonos por transferencia',
        _ when code.startsWith('ABONO_') => 'Abonos (${code.substring(6).toLowerCase()})',
        _ => PaymentMethod.label(code),
      };

  /// Comprobante del cierre para enviar por WhatsApp
  static String receipt({
    required String businessName,
    required CashSession session,
    required CashSummary summary,
    List<String> servicesLines = const [],
  }) {
    String hour(DateTime d) {
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      return '${d.day}/${d.month} $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'a. m.' : 'p. m.'}';
    }

    final diff = session.difference ?? 0;
    return [
      'Cierre de caja · $businessName',
      'Abrió: ${hour(session.openedAt)}${session.closedAt == null ? '' : ' · Cerró: ${hour(session.closedAt!)}'}',
      '',
      'Base: ${CurrencyFormatter.format(summary.openingAmount)}',
      for (final e in summary.byMethod.entries) '${methodLabel(e.key)}: ${CurrencyFormatter.format(e.value)}',
      if (summary.tipsIn > 0) 'Propinas en efectivo: ${CurrencyFormatter.format(summary.tipsIn)}',
      if (summary.tipsOut > 0) 'Propinas entregadas: ${CurrencyFormatter.format(summary.tipsOut)}',
      if (summary.entries > 0) 'Entradas: ${CurrencyFormatter.format(summary.entries)}',
      if (summary.exits > 0) 'Salidas: ${CurrencyFormatter.format(summary.exits)}',
      if (summary.cashPurchases > 0) 'Mercancía de contado: ${CurrencyFormatter.format(summary.cashPurchases)}',
      '',
      'Efectivo esperado: ${CurrencyFormatter.format(summary.expected)}',
      if (session.countedAmount != null) 'Efectivo contado: ${CurrencyFormatter.format(session.countedAmount!)}',
      if (session.countedAmount != null)
        diff.abs() < 1
            ? 'Cuadró'
            : diff > 0
                ? 'Sobran ${CurrencyFormatter.format(diff)}'
                : 'Faltan ${CurrencyFormatter.format(-diff)}',
      if ((session.notes ?? '').isNotEmpty) 'Nota: ${session.notes}',
      if (servicesLines.isNotEmpty) ...['', ...servicesLines],
    ].join('\n');
  }
}

/// El negocio usa caja y no hay una abierta: no se puede vender (decisión del
/// dueño, 10 nov). La pantalla ofrece «Abrir caja» ahí mismo.
class CashClosedException implements Exception {
  const CashClosedException();

  @override
  String toString() => 'Exception: Abre la caja para vender. Tu negocio usa caja y está cerrada.';
}

/// ¿El negocio usa caja y está cerrada? (antes de mostrar Vender o cobrar)
Future<bool> isCashClosedFor(Business? business) async {
  if (business == null || !business.cashRegisterEnabled) return false;
  return await CashRegisterRepository.instance.getOpenSession(business.id) == null;
}
