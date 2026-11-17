import 'package:flutter/foundation.dart';
import '../../../core/utils/business_clock.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/data_events.dart';
import '../../../core/services/supabase_service.dart';
import '../../team/data/activity_repository.dart';
import '../../../core/utils/currency_formatter.dart';
import '../models/sales_goal.dart';

/// Metas de ventas (0.16.0, fase 0). La meta del negocio es gratis y se calcula con
/// las ventas del celular; las metas por persona y el historial son de Pro, y lo
/// vendido por cada persona lo da la nube (quién hizo cada venta).
class GoalsRepository {
  static final GoalsRepository instance = GoalsRepository._();
  GoalsRepository._();

  /// Cambia al guardar una meta: la tarjeta de Inicio y Reportes se recargan
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<SalesGoal>> list(String businessId) async {
    final rows = await (await _db).query('sales_goals', where: 'business_id = ?', whereArgs: [businessId]);
    return [for (final r in rows) SalesGoal.fromMap(r)];
  }

  /// La meta que vale en el periodo que empieza en [start]: la última puesta en ese
  /// periodo o antes. null = sin meta.
  static SalesGoal? goalFor(List<SalesGoal> all, GoalPeriod period, DateTime start, {String? member}) {
    SalesGoal? best;
    for (final g in all) {
      if (g.period != period || g.memberUserId != member || g.startsOn.isAfter(start)) continue;
      if (best == null ||
          g.startsOn.isAfter(best.startsOn) ||
          (g.startsOn == best.startsOn && g.updatedAt.isAfter(best.updatedAt))) {
        best = g;
      }
    }
    return best == null || best.amount <= 0 ? null : best;
  }

  /// Pone o cambia la meta desde el periodo actual. [amount] 0 la quita.
  Future<SalesGoal> setGoal({
    required String businessId,
    required GoalPeriod period,
    required double amount,
    String? memberUserId,
    String? memberName,
    DateTime? now,
  }) async {
    final at = now ?? appNow();
    final start = period.startOf(at);
    final id = SalesGoal.idFor(businessId, period, memberUserId, start);
    final db = await _db;
    final old = await db.query('sales_goals', columns: ['created_at'], where: 'id = ?', whereArgs: [id], limit: 1);
    final goal = SalesGoal(
      id: id,
      businessId: businessId,
      period: period,
      memberUserId: memberUserId,
      memberName: memberName,
      amount: amount < 0 ? 0 : amount,
      startsOn: start,
      createdAt: old.isEmpty ? at : DateTime.tryParse('${old.first['created_at']}') ?? at,
      updatedAt: at,
    );
    await db.insert('sales_goals', goal.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    SupabaseService.instance.upsertSalesGoalToCloud(goal.toMap());
    final who = memberUserId == null ? 'del negocio' : 'de ${memberName ?? 'una persona'}';
    ActivityRepository.instance.log(
      businessId: businessId,
      action: ActivityAction.goalChange,
      summary: goal.amount <= 0
          ? 'Quitó la meta ${period == GoalPeriod.week ? 'semanal' : 'mensual'} $who'
          : 'Puso la meta ${period == GoalPeriod.week ? 'semanal' : 'mensual'} $who en ${CurrencyFormatter.format(goal.amount)}',
      data: {'goal_id': id},
    );
    version.value++;
    return goal;
  }

  /// Ventas del negocio por día entre [from] y [to] (sin anuladas; las devoluciones restan)
  Future<List<double>> dailySales(String businessId, DateTime from, DateTime to) async {
    final days = to.difference(from).inDays;
    final out = List<double>.filled(days < 0 ? 0 : days, 0);
    final rows = await (await _db).query(
      'sales',
      columns: ['date', 'total'],
      where: 'business_id = ? AND voided_at IS NULL',
      whereArgs: [businessId],
    );
    for (final r in rows) {
      final d = DateTime.tryParse('${r['date']}')?.toLocal();
      if (d == null || d.isBefore(from) || !d.isBefore(to)) continue;
      final i = DateTime(d.year, d.month, d.day).difference(from).inDays;
      if (i >= 0 && i < out.length) out[i] += (r['total'] as num?)?.toDouble() ?? 0;
    }
    return out;
  }

  /// Cómo va la meta del negocio en el periodo que contiene [now]
  Future<GoalProgress?> businessProgress(String businessId, GoalPeriod period, {DateTime? now, List<SalesGoal>? goals}) async {
    final at = now ?? appNow();
    final from = period.startOf(at);
    final goal = goalFor(goals ?? await list(businessId), period, from);
    if (goal == null) return null;
    final to = period.endOf(from);
    final sold = (await dailySales(businessId, from, to)).fold<double>(0, (s, v) => s + v);
    return GoalProgress(period: period, goal: goal.amount, sold: sold, from: from, to: to, now: at);
  }

  /// Historial de la meta del negocio (Pro): los [count] periodos anteriores que tenían meta
  Future<List<GoalProgress>> businessHistory(String businessId, GoalPeriod period, {int count = 6, DateTime? now}) async {
    final at = now ?? appNow();
    final goals = await list(businessId);
    final out = <GoalProgress>[];
    var start = period.previous(period.startOf(at));
    for (var i = 0; i < count; i++) {
      final goal = goalFor(goals, period, start);
      if (goal != null) {
        final to = period.endOf(start);
        final sold = (await dailySales(businessId, start, to)).fold<double>(0, (s, v) => s + v);
        out.add(GoalProgress(period: period, goal: goal.amount, sold: sold, from: start, to: to, now: at));
      }
      start = period.previous(start);
    }
    return out;
  }

  /// Lo vendido por cada persona del equipo en el periodo (Pro, con internet). El dueño
  /// recibe a todos; los demás, solo lo suyo. null = sin conexión.
  Future<Map<String, double>?> memberSales(String businessId, DateTime from, DateTime to) async {
    final client = SupabaseService.instance.client;
    if (client == null) return null;
    try {
      final rows = await client.rpc('member_sales', params: {
        'p_business_id': businessId,
        // La nube guarda la hora del reloj del negocio: el periodo va en ese mismo
        // marco (con toUtc las ventas después de las 7 p. m. caían al día siguiente)
        'p_from': BusinessClock.cloudIso(from),
        'p_to': BusinessClock.cloudIso(to),
      });
      return {
        for (final r in (rows as List))
          '${(r as Map)['user_id']}': ((r['total'] as num?) ?? 0).toDouble(),
      };
    } catch (e) {
      debugPrint('No se pudo leer lo vendido por persona: $e');
      return null;
    }
  }

  /// Avisa que cambiaron las ventas (la tarjeta de Inicio escucha esto también)
  static ValueListenable<int> get salesVersion => DataEvents.instance.salesVersion;
}
