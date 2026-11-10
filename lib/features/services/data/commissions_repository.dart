import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/countries.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/data/auth_repository.dart';
import '../../business/models/business.dart';
import '../../customers/data/debt_reminder.dart';
import '../../team/data/activity_repository.dart';
import '../models/commission_models.dart';
import '../models/service_models.dart';

/// Un servicio cobrado: su venta, lo cobrado después del descuento y la línea del trabajo
typedef ChargedLine = ({String saleId, double total, WorkOrderLine line});

/// Comisiones y liquidaciones (0.12.0):
///   • Cada servicio cobrado deja una comisión por persona: % del servicio sobre lo
///     cobrado (después del descuento), repartida si lo hicieron varios.
///   • La propina va completa a quienes atendieron, repartida en partes iguales.
///   • Se liquida al final del día, la semana o el mes: lo pendiente se marca pagado.
///   • Anular un cobro borra sus comisiones pendientes; si ya se habían pagado,
///     deja un ajuste negativo para la próxima liquidación.
class CommissionsRepository {
  CommissionsRepository._();
  static final CommissionsRepository instance = CommissionsRepository._();

  final AppDatabase _dbProvider = AppDatabase.instance;
  final _cloud = SupabaseService.instance;

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  /// Comisión de cada persona por un servicio cobrado
  static List<({String staffId, double base, double amount})> split(double total, double pct, List<String> staffIds) {
    if (staffIds.isEmpty) return const [];
    final base = total / staffIds.length;
    return [
      for (final id in staffIds) (staffId: id, base: _round(base), amount: _round(base * pct / 100)),
    ];
  }

  /// Total de comisiones de un servicio cobrado (se descuenta como costo de la venta)
  static double commissionOf(double total, double pct, List<String> staffIds) =>
      split(total, pct, staffIds).fold(0.0, (s, c) => s + c.amount);

  Future<void> _insert(Commission c) async {
    final db = await _dbProvider.database;
    final row = c.toMap();
    await db.insert('commissions', row, conflictAlgorithm: ConflictAlgorithm.replace);
    _cloud.upsertCommissionToCloud(row);
  }

  Future<void> _delete(String id) async {
    final db = await _dbProvider.database;
    await db.delete('commissions', where: 'id = ?', whereArgs: [id]);
    _cloud.deleteCommissionFromCloud(id);
  }

  /// Al cobrar un trabajo: comisiones por servicio y la propina repartida
  Future<List<Commission>> recordForOrder({
    required WorkOrder order,
    required List<ChargedLine> charged,
    double tip = 0,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final created = <Commission>[];
    for (final ch in charged) {
      for (final part in split(ch.total, ch.line.commissionPct, ch.line.staffIds)) {
        created.add(Commission(
          id: const Uuid().v4(),
          businessId: order.businessId,
          staffId: part.staffId,
          workOrderId: order.id,
          saleId: ch.saleId,
          label: ch.line.name,
          base: part.base,
          pct: ch.line.commissionPct,
          amount: part.amount,
          date: at,
          updatedAt: at,
        ));
      }
    }
    final people = order.staffIds.toList();
    if (tip > 0 && people.isNotEmpty) {
      final share = _round(tip / people.length);
      for (final id in people) {
        created.add(Commission(
          id: const Uuid().v4(),
          businessId: order.businessId,
          staffId: id,
          workOrderId: order.id,
          kind: Commission.kindTip,
          label: 'Propina',
          amount: share,
          date: at,
          updatedAt: at,
        ));
      }
    }
    for (final c in created) {
      await _insert(c);
    }
    return created;
  }

  /// Se anuló una venta de servicio: fuera sus comisiones pendientes; las pagadas
  /// dejan un ajuste negativo
  Future<void> onSaleCancelled(String saleId, {DateTime? now}) async {
    final db = await _dbProvider.database;
    final rows = await db.query('commissions', where: 'sale_id = ?', whereArgs: [saleId]);
    final at = now ?? DateTime.now();
    for (final c in rows.map(Commission.fromMap)) {
      if (!c.isPaid) {
        await _delete(c.id);
      } else if (c.amount != 0) {
        await _insert(Commission(
          id: const Uuid().v4(),
          businessId: c.businessId,
          staffId: c.staffId,
          workOrderId: c.workOrderId,
          kind: Commission.kindAdjustment,
          label: 'Anulación: ${c.label}',
          amount: -c.amount,
          date: at,
          updatedAt: at,
        ));
      }
    }
  }

  /// Se anuló el cobro de un trabajo: fuera sus propinas pendientes (las pagadas, ajuste)
  Future<void> onOrderReopened(String workOrderId, {DateTime? now}) async {
    final db = await _dbProvider.database;
    final rows = await db.query('commissions',
        where: 'work_order_id = ? AND kind = ?', whereArgs: [workOrderId, Commission.kindTip]);
    final at = now ?? DateTime.now();
    for (final c in rows.map(Commission.fromMap)) {
      if (!c.isPaid) {
        await _delete(c.id);
      } else {
        await _insert(Commission(
          id: const Uuid().v4(),
          businessId: c.businessId,
          staffId: c.staffId,
          workOrderId: c.workOrderId,
          kind: Commission.kindAdjustment,
          label: 'Anulación: propina',
          amount: -c.amount,
          date: at,
          updatedAt: at,
        ));
      }
    }
  }

  /// Lo pendiente de cada persona entre [from] y [to] (incluidos). Sin fechas: todo lo pendiente.
  Future<List<StaffEarnings>> pending(String businessId, {DateTime? from, DateTime? to}) async {
    final db = await _dbProvider.database;
    final where = StringBuffer('business_id = ? AND payout_id IS NULL');
    final args = <Object>[businessId];
    if (from != null) {
      where.write(' AND date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.write(' AND date < ?');
      args.add(to.toIso8601String());
    }
    final rows = await db.query('commissions', where: where.toString(), whereArgs: args, orderBy: 'date ASC');
    final byStaff = <String, List<Commission>>{};
    for (final c in rows.map(Commission.fromMap)) {
      byStaff.putIfAbsent(c.staffId, () => []).add(c);
    }
    return [for (final e in byStaff.entries) StaffEarnings(e.key, e.value)];
  }

  /// Lo que hizo cada persona en un periodo (pagado o no), para el cierre del día
  Future<List<StaffEarnings>> earnedBetween(String businessId, DateTime from, DateTime to) async {
    final db = await _dbProvider.database;
    final rows = await db.query('commissions',
        where: 'business_id = ? AND date >= ? AND date < ?',
        whereArgs: [businessId, from.toIso8601String(), to.toIso8601String()],
        orderBy: 'date ASC');
    final byStaff = <String, List<Commission>>{};
    for (final c in rows.map(Commission.fromMap)) {
      byStaff.putIfAbsent(c.staffId, () => []).add(c);
    }
    return [for (final e in byStaff.entries) StaffEarnings(e.key, e.value)];
  }

  /// Paga lo pendiente de una persona: crea la liquidación y marca sus comisiones
  Future<StaffPayout> pay(String businessId, StaffEarnings earnings, {String? staffName, DateTime? now}) async {
    if (earnings.items.isEmpty) throw StateError('No hay nada pendiente por pagar.');
    final at = now ?? DateTime.now();
    final dates = earnings.items.map((c) => c.date).toList()..sort();
    final payout = StaffPayout(
      id: const Uuid().v4(),
      businessId: businessId,
      staffId: earnings.staffId,
      fromDate: dates.first,
      toDate: dates.last,
      commissions: _round(earnings.commissions),
      tips: _round(earnings.tips),
      paidAt: at,
      paidBy: AuthRepository.instance.currentUser?.email,
    );
    final db = await _dbProvider.database;
    final row = payout.toMap();
    await db.insert('staff_payouts', row);
    _cloud.upsertPayoutToCloud(row);
    for (final c in earnings.items) {
      final paid = c.copyWith(payoutId: payout.id, updatedAt: at);
      await db.update('commissions', paid.toMap(), where: 'id = ?', whereArgs: [c.id]);
      _cloud.upsertCommissionToCloud(paid.toMap());
    }
    ActivityRepository.instance.log(
      businessId: businessId,
      action: 'staff_payout',
      summary: 'Pagó ${CurrencyFormatter.format(payout.total)} a ${staffName ?? 'un empleado'} '
          '(${earnings.services} ${earnings.services == 1 ? 'servicio' : 'servicios'})',
      data: {'payout_id': payout.id, 'staff_id': payout.staffId, 'total': payout.total},
    );
    return payout;
  }

  Future<List<StaffPayout>> payouts(String businessId, {String? staffId, int limit = 50}) async {
    final db = await _dbProvider.database;
    final rows = await db.query('staff_payouts',
        where: staffId == null ? 'business_id = ?' : 'business_id = ? AND staff_id = ?',
        whereArgs: [businessId, if (staffId != null) staffId],
        orderBy: 'paid_at DESC',
        limit: limit);
    return rows.map(StaffPayout.fromMap).toList();
  }

  /// Detalle para enviarle a la persona por WhatsApp
  static String detailMessage({
    required String staffName,
    required String businessName,
    required StaffEarnings earnings,
    bool paid = false,
  }) {
    String day(DateTime d) => '${d.day}/${d.month}';
    final lines = [
      for (final c in earnings.items)
        '• ${day(c.date)} ${c.label}: ${CurrencyFormatter.format(c.amount)}',
    ];
    return [
      'Hola ${staffName.split(' ').first}, este es el detalle de $businessName:',
      ...lines,
      'Servicios: ${earnings.services} · Comisiones: ${CurrencyFormatter.format(earnings.commissions)}'
          '${earnings.tips != 0 ? ' · Propinas: ${CurrencyFormatter.format(earnings.tips)}' : ''}',
      '${paid ? 'Pagado' : 'Total'}: ${CurrencyFormatter.format(earnings.total)}',
    ].join('\n');
  }

  /// Abre WhatsApp con el detalle (o compartir, si la persona no tiene celular)
  static Future<void> sendDetail({
    required StaffMember staff,
    required Business business,
    required StaffEarnings earnings,
    bool paid = false,
  }) async {
    final text = detailMessage(staffName: staff.name, businessName: business.name, earnings: earnings, paid: paid);
    final number = DebtReminder.normalizePhone(staff.phone, country: countryByCode(business.country));
    if (number != null) {
      try {
        final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}');
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (e) {
        debugPrint('No se pudo abrir WhatsApp: $e');
      }
    }
    await Share.share(text);
  }
}
