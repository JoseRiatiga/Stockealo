import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';

/// Nombres para mostrar (0.18.6). Las cajas de versiones viejas guardaban el correo
/// de quien abrió o cerró; en pantalla se muestra el nombre de esa persona en el
/// equipo, o la parte del correo antes de la @ si ya no está. No cambia lo guardado.
class PersonNames {
  PersonNames._();

  static Map<String, String> _byEmail = const {};

  /// La carga más reciente: si se cambia de negocio a mitad de una, gana la última
  /// (Codex, 25 nov)
  static int _seq = 0;

  /// Carga los nombres del equipo del negocio (del celular; no necesita conexión)
  static Future<void> load(String businessId) async {
    final seq = ++_seq;
    _byEmail = const {};
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query('business_members', columns: ['email', 'name'], where: 'business_id = ?', whereArgs: [businessId]);
      if (seq != _seq) return;
      _byEmail = {
        for (final r in rows)
          if ((r['email'] as String?)?.trim().isNotEmpty == true && (r['name'] as String?)?.trim().isNotEmpty == true)
            (r['email'] as String).trim().toLowerCase(): (r['name'] as String).trim(),
      };
    } catch (e) {
      debugPrint('Nombres del equipo sin cargar: $e');
    }
  }

  @visibleForTesting
  static set debugNames(Map<String, String> names) => _byEmail = names;

  /// El nombre para mostrar: si [who] es un correo, el nombre de esa persona
  static String display(String? who) {
    final v = (who ?? '').trim();
    if (!v.contains('@')) return v;
    return _byEmail[v.toLowerCase()] ?? v.split('@').first;
  }
}
