import 'package:flutter/foundation.dart';

import '../../../core/permissions/permissions.dart';
import '../../../core/services/supabase_service.dart';

/// Encargado de turno (0.18.5, docs/plan-0.18.5-traslados.md). El dueño o un
/// administrador deja a un cajero a cargo de su sede hasta una hora: mientras tanto
/// recibe traslados de forma definitiva, verifica los provisionales y cierra la caja de
/// otros. La hora la revisa la nube (business_members.lead_until); aquí solo se muestra.
class ShiftLead {
  ShiftLead._();

  /// Hasta cuándo es encargado quien usa la app en el negocio activo (null = no lo es)
  static final until = ValueNotifier<DateTime?>(null);

  /// «Hasta que lo quite»: un año, que la nube acepta como cualquier otra hora
  static const untilRemoved = Duration(days: 365);

  static bool get active => until.value?.isAfter(DateTime.now()) ?? false;

  /// Lee de la nube si quien usa la app es encargado en [businessId]
  static Future<void> load(String businessId, String email) async {
    final client = SupabaseService.instance.client;
    if (client?.auth.currentSession == null) return;
    try {
      final row = await client!
          .from('business_members')
          .select('lead_until')
          .eq('business_id', businessId)
          .ilike('user_email', email.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}'))
          .maybeSingle();
      _set(DateTime.tryParse('${row?['lead_until']}')?.toLocal());
    } catch (e) {
      debugPrint('Encargado de turno sin revisar: $e');
    }
  }

  static void clear() => _set(null);

  static void _set(DateTime? value) {
    final v = value != null && value.isAfter(DateTime.now()) ? value : null;
    until.value = v;
    Permissions.leadUntil = v;
  }

  /// Encargados vigentes del negocio: id del miembro → hasta cuándo
  static Future<Map<String, DateTime>> ofBusiness(String businessId) async {
    final client = SupabaseService.instance.client;
    if (client?.auth.currentSession == null) return const {};
    try {
      final rows = await client!
          .from('business_members')
          .select('id, lead_until')
          .eq('business_id', businessId)
          .gt('lead_until', DateTime.now().toUtc().toIso8601String());
      return {
        for (final r in rows as List)
          if (DateTime.tryParse('${r['lead_until']}') case final d?) r['id'] as String: d.toLocal(),
      };
    } catch (e) {
      debugPrint('Encargados sin bajar: $e');
      return const {};
    }
  }

  /// Nombra (o quita, con [until] null) al encargado de la sede de ese miembro
  static Future<void> set(String memberId, DateTime? until) async {
    final client = SupabaseService.instance.client;
    if (client?.auth.currentSession == null) throw Exception('Para nombrar un encargado necesitas conexión.');
    try {
      await client!.rpc('set_shift_lead', params: {'p_member_id': memberId, 'p_until': until?.toUtc().toIso8601String()});
    } catch (e) {
      final t = e.toString();
      if (t.contains('perm_denied')) throw Exception('Solo el dueño o un administrador nombran al encargado.');
      if (t.contains('lead_not_needed')) throw Exception('El dueño y los administradores ya pueden hacer todo eso.');
      if (t.contains('lead_past')) throw Exception('Elige una hora que todavía no haya pasado.');
      rethrow;
    }
  }

  /// «hasta las 6:00 p. m.», «hasta mañana a las 9:00 a. m.» o «hasta que lo quiten»
  static String describe(DateTime until, {DateTime? now}) {
    final n = now ?? DateTime.now();
    if (until.difference(n) > const Duration(days: 300)) return 'hasta que lo quiten';
    final h = until.hour % 12 == 0 ? 12 : until.hour % 12;
    final m = until.minute.toString().padLeft(2, '0');
    final time = '$h:$m ${until.hour < 12 ? 'a. m.' : 'p. m.'}';
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(until.year, until.month, until.day);
    if (day == today) return 'hasta las $time';
    if (day == today.add(const Duration(days: 1))) return 'hasta mañana a las $time';
    return 'hasta el ${until.day}/${until.month} a las $time';
  }
}
