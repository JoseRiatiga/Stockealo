import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/permissions/permissions.dart';

/// 0.15.0, punto 7: la nube sabe lo mismo que la app. Si cambia la lista del Cajero de
/// fábrica o los nombres de los límites en permissions.dart, hay que cambiar también la
/// migración (y viceversa); esta prueba lo avisa.
void main() {
  final sql = File('supabase/migrations/20261202500000_permissions_in_cloud.sql').readAsStringSync();

  test('el Cajero de fábrica es igual en la app y en la nube', () {
    final match = RegExp(r"return p_perm = any \(array\[([^\]]+)\]\);").firstMatch(sql);
    expect(match, isNotNull, reason: 'no se encontró la lista del Cajero en la migración');
    final cloud = RegExp(r"'(\w+)'").allMatches(match!.group(1)!).map((m) => m.group(1)!).toSet();
    final app = Permissions.factoryDefaults(Permissions.cashier).map((p) => p.name).toSet();
    expect(cloud, app);
  });

  test('el Administrador de fábrica tiene todo menos el equipo, en la app y en la nube', () {
    expect(sql, contains("return p_perm <> 'team';"));
    final app = Permissions.factoryDefaults(Permissions.admin);
    expect(Perm.values.where((p) => !app.contains(p)).map((p) => p.name), ['team']);
  });

  test('los permisos y límites que revisa la nube existen en la app', () {
    final perms = RegExp(r"has_permission\([^,]+, '(\w+)'\)").allMatches(sql).map((m) => m.group(1)!).toSet();
    for (final name in perms) {
      expect(Perm.byName(name), isNotNull, reason: 'la nube revisa «$name» y la app no lo tiene');
    }
    final limits = RegExp(r"my_limit\([^,]+, '(\w+)'\)").allMatches(sql).map((m) => m.group(1)!).toSet();
    expect(limits, isNotEmpty);
    for (final name in limits) {
      expect(RoleLimit.byName(name), isNotNull, reason: 'la nube revisa el límite «$name» y la app no lo tiene');
    }
  });
}
