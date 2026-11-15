import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/permissions/permissions.dart';

void main() {
  test('el dueño puede todo', () {
    for (final p in Perm.values) {
      expect(Permissions.can('OWNER', p), isTrue, reason: p.name);
    }
  });

  test('el administrador puede todo menos manejar el equipo (igual que antes)', () {
    expect(Permissions.can('ADMIN', Perm.team), isFalse);
    expect(Permissions.can('ADMIN', Perm.costs), isTrue);
    expect(Permissions.can('ADMIN', Perm.voidSale), isTrue);
    expect(Permissions.can('ADMIN', Perm.exportExcel), isTrue);
  });

  test('el cajero vende y fía, pero no ve costos ni anula (igual que antes)', () {
    for (final p in [Perm.sell, Perm.credit, Perm.cashOwn, Perm.servicesWork, Perm.catalog]) {
      expect(Permissions.can('CASHIER', p), isTrue, reason: p.name);
    }
    for (final p in [Perm.costs, Perm.voidSale, Perm.productsEdit, Perm.reportsSales, Perm.suppliers, Perm.store, Perm.team]) {
      expect(Permissions.can('CASHIER', p), isFalse, reason: p.name);
    }
    // Un rol desconocido o vacío se trata como cajero
    expect(Permissions.can(null, Perm.costs), isFalse);
    expect(Permissions.can('cashier', Perm.sell), isTrue);
  });

  test('encender un permiso enciende los que necesita', () {
    expect(Permissions.withDependencies({Perm.sellBelowCost}), containsAll([Perm.sell, Perm.discount, Perm.costs]));
    expect(Permissions.withDependencies({Perm.exportExcel}), containsAll([Perm.reportsSales, Perm.costs]));
  });

  test('cada permiso tiene nombre y frase, y las claves no se repiten', () {
    expect(Perm.values.map((p) => p.name).toSet().length, Perm.values.length);
    for (final p in Perm.values) {
      expect(p.label, isNotEmpty);
      expect(p.help, isNotEmpty);
      expect(Perm.byName(p.name), p);
    }
    expect(Permissions.templates.map((t) => t.id).toSet().length, Permissions.templates.length);
  });
}
