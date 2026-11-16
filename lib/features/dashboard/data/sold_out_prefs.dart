import 'dart:convert';

import '../../../core/database/app_database.dart';

/// Los dos interruptores del panel «Resolver» de un agotado (0.16.0, fase 7):
/// • «Recordarme si no llega»: si a los [remindAfterDays] días sigue agotado, Inicio lo
///   dice («Lo pediste hace 4 días y no ha llegado»).
/// • «Ocultarlo en Vender»: mientras esté agotado no sale en Vender. Vuelve solo cuando
///   llega el stock (la tienda en línea ya no muestra lo agotado).
/// Se guarda en este equipo, por negocio.
abstract final class SoldOutPrefs {
  static const remindAfterDays = 3;

  static String _hiddenKey(String businessId) => 'sold_out_hidden_$businessId';
  static String _remindKey(String businessId) => 'restock_remind_$businessId';

  static Future<Set<String>> hidden(String businessId) async {
    try {
      final raw = await AppDatabase.instance.getSetting(_hiddenKey(businessId));
      return {for (final v in (jsonDecode(raw ?? '[]') as List)) '$v'};
    } catch (_) {
      return {};
    }
  }

  static Future<void> setHidden(String businessId, String productId, bool hide) async {
    final set = await hidden(businessId);
    hide ? set.add(productId) : set.remove(productId);
    await AppDatabase.instance.setSetting(_hiddenKey(businessId), set.isEmpty ? null : jsonEncode(set.toList()));
  }

  /// Cuándo se pidió que le recordaran cada producto
  static Future<Map<String, DateTime>> reminders(String businessId) async {
    try {
      final raw = await AppDatabase.instance.getSetting(_remindKey(businessId));
      final map = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          if (DateTime.tryParse('${e.value}') != null) e.key: DateTime.parse('${e.value}'),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> setReminder(String businessId, String productId, bool on, {DateTime? now}) async {
    final map = await reminders(businessId);
    on ? map[productId] = now ?? DateTime.now() : map.remove(productId);
    await AppDatabase.instance.setSetting(
      _remindKey(businessId),
      map.isEmpty ? null : jsonEncode({for (final e in map.entries) e.key: e.value.toIso8601String()}),
    );
  }

  /// Días desde que lo pidió, si ya pasaron [remindAfterDays]; null si no toca avisar
  static int? overdueDays(DateTime? askedAt, {DateTime? now}) {
    if (askedAt == null) return null;
    final days = (now ?? DateTime.now()).difference(askedAt).inDays;
    return days >= remindAfterDays ? days : null;
  }
}
