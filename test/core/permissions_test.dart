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
    // Un rol desconocido o vacío se trata como cajero (nunca gana permisos)
    expect(Permissions.can(null, Perm.costs), isFalse);
    expect(Permissions.can('', Perm.costs), isFalse);
    expect(Permissions.can('SUPPORT', Perm.productsEdit), isFalse);
    expect(Permissions.can('cashier', Perm.sell), isTrue);
  });

  // Decisión de la 0.15.0 (revisión con Codex): el rol se lee sin importar mayúsculas,
  // igual que ya hacían Ajustes y la nube (supabase_service guarda el rol en MAYÚSCULAS).
  test('el rol se lee igual en minúsculas o mayúsculas', () {
    for (final p in Perm.values) {
      expect(Permissions.can('owner', p), Permissions.can('OWNER', p), reason: p.name);
      expect(Permissions.can('admin', p), Permissions.can('ADMIN', p), reason: p.name);
      expect(Permissions.can('Cashier', p), Permissions.can('CASHIER', p), reason: p.name);
    }
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

  test('el rol activo y «Ver como» deciden lo que se permite en cada acción', () {
    addTearDown(() {
      Permissions.current = Permissions.owner;
      Permissions.viewAs.value = null;
    });
    Permissions.current = Permissions.cashier;
    expect(Permissions.mine(Perm.costs), isFalse);
    expect(Permissions.mine(Perm.sell), isTrue);
    // El dueño mirando como Cajero tampoco ve costos
    Permissions.current = Permissions.owner;
    Permissions.viewAs.value = Permissions.cashier;
    expect(Permissions.mine(Perm.costs), isFalse);
    Permissions.viewAs.value = null;
    expect(Permissions.mine(Perm.costs), isTrue);
  });
}
