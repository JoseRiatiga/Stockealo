import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../models/promotion.dart';

/// Las promociones del negocio: se guardan en el equipo y se suben a la nube
/// (tabla `promotions`). Vender las aplica solas mientras están vigentes.
class PromotionsRepository {
  PromotionsRepository._();
  static final PromotionsRepository instance = PromotionsRepository._();

  final _dbProvider = AppDatabase.instance;

  Promotion newPromotion(String businessId, {required String name, required String kind}) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return Promotion(
      id: const Uuid().v4(),
      businessId: businessId,
      name: name,
      kind: kind,
      percentOff: kind == Promotion.percent ? 10 : 0,
      startsAt: start,
      endsAt: start.add(const Duration(days: 8)),
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Todas, las vigentes y próximas primero
  Future<List<Promotion>> all(String businessId) async {
    final db = await _dbProvider.database;
    final rows = await db.query('promotions', where: 'business_id = ?', whereArgs: [businessId], orderBy: 'ends_at DESC');
    final list = [for (final r in rows) Promotion.fromMap(r)];
    final now = DateTime.now();
    list.sort((a, b) {
      int rank(Promotion p) => p.isLiveAt(now) ? 0 : (p.isOverAt(now) ? 2 : 1);
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.endsAt.compareTo(b.endsAt);
    });
    return list;
  }

  /// Las que valen ahora
  Future<List<Promotion>> live(String businessId, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    return [for (final p in await all(businessId)) if (p.isLiveAt(now)) p];
  }

  Future<void> save(Promotion p) async {
    final db = await _dbProvider.database;
    final row = p.copyWith(updatedAt: DateTime.now()).toMap();
    await db.insert('promotions', row, conflictAlgorithm: ConflictAlgorithm.replace);
    await SupabaseService.instance.upsertPromotionToCloud(row);
  }

  Future<void> delete(Promotion p) async {
    final db = await _dbProvider.database;
    await db.delete('promotions', where: 'id = ?', whereArgs: [p.id]);
    await SupabaseService.instance.deletePromotionFromCloud(p.id);
  }

  /// Cuánto vendió y cuánto descontó cada promoción en un periodo (para Reportes)
  Future<List<({String name, int units, double sold, double discount})>> results(
      String businessId, DateTime from, DateTime to) async {
    final db = await _dbProvider.database;
    final rows = await db.rawQuery('''
      SELECT promotion_name AS name, SUM(quantity) AS units, SUM(total) AS sold, SUM(promotion_discount) AS discount
      FROM sales
      WHERE business_id = ? AND promotion_name IS NOT NULL AND voided_at IS NULL AND date >= ? AND date < ?
      GROUP BY promotion_name
      ORDER BY discount DESC
    ''', [businessId, from.toIso8601String(), to.toIso8601String()]);
    return [
      for (final r in rows)
        (
          name: r['name'] as String,
          units: (r['units'] as num?)?.toInt() ?? 0,
          sold: (r['sold'] as num?)?.toDouble() ?? 0,
          discount: (r['discount'] as num?)?.toDouble() ?? 0,
        ),
    ];
  }
}
