import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/services/supabase_service.dart';

/// «Sincronizar ahora» (24 nov): un negocio con servicios y otro sin ellos no pueden
/// ir en la misma tanda, porque al que no los trae le llegarían vacíos a la nube.
void main() {
  test('las filas con columnas distintas van en tandas aparte', () {
    final groups = SupabaseService.groupByColumns([
      {'id': 'a', 'name': 'Miselanea'},
      {'id': 'b', 'name': 'LAVADERO', 'services_enabled': true, 'service_type': 'lavadero'},
      {'name': 'Yeddgd', 'id': 'c'},
    ]);
    expect(groups.length, 2);
    for (final g in groups) {
      final keys = g.first.keys.toSet();
      expect(g.every((r) => r.keys.toSet().containsAll(keys) && keys.containsAll(r.keys)), isTrue);
    }
    expect(groups.firstWhere((g) => g.first.containsKey('services_enabled')).map((r) => r['id']), ['b']);
    expect(groups.firstWhere((g) => !g.first.containsKey('services_enabled')).map((r) => r['id']), ['a', 'c']);
  });

  test('ventas con y sin descuento de promoción no se mezclan', () {
    final groups = SupabaseService.groupByColumns([
      {'id': '1', 'total_amount': 9000},
      {'id': '2', 'total_amount': 8000, 'promotion_discount': 1000},
    ]);
    expect(groups.length, 2);
  });
}
