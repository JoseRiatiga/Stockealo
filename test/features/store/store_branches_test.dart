import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/store/data/online_store_service.dart';

/// Tienda por sede (0.18.3): quien compra elige la sede y ve lo que hay en ella
void main() {
  Map<String, dynamic> json({bool branches = true}) => {
        'slug': 'lavadero',
        'business': {'name': 'LAVADERO', 'currency': 'COP', 'address': 'Cra 1'},
        if (branches)
          'branches': [
            {'id': '', 'name': 'Principal', 'address': 'Cra 1'},
            {'id': 'n1', 'name': 'Norte', 'address': 'Cl 80', 'phone': '3001234567'},
          ],
        'products': [
          {'id': 'a', 'name': 'Shampoo', 'price': 9000, 'stock': 5, if (branches) 'branch_stock': {'': 5, 'n1': 0}},
          {'id': 'b', 'name': 'Cera', 'price': 15000, 'stock': 0, if (branches) 'branch_stock': {'': 0, 'n1': 2}},
        ],
      };

  test('sin sedes, la tienda es la de siempre', () {
    final s = PublicStore.fromJson(json(branches: false));
    expect(s.hasBranches, isFalse);
    expect(s.products.length, 2);
  });

  test('en cada sede solo se ve lo que hay, con su stock y su dirección', () {
    final s = PublicStore.fromJson(json());
    expect(s.hasBranches, isTrue);
    final north = s.inBranch('n1');
    expect(north.products.map((p) => p.name), ['Cera']);
    expect(north.products.single.stock, 2);
    expect(north.products.single.few, isTrue);
    expect(north.address, 'Cl 80');
    final main = s.inBranch('');
    expect(main.products.map((p) => p.name), ['Shampoo']);
    expect(main.address, 'Cra 1');
  });

  test('dice cuántos productos hay en otra sede y en cuál', () {
    final s = PublicStore.fromJson(json());
    final away = s.elsewhere('n1');
    expect(away.count, 1);
    expect(away.where?.name, 'Principal');
  });

  test('las tallas se ven agotadas o disponibles según la sede', () {
    final s = PublicStore.fromJson({
      ...json(),
      'products': [
        {
          'id': 'c', 'name': 'Camiseta', 'price': 20000, 'branch_stock': {'': 1, 'n1': 4},
          'variants': [
            {'id': 'v1', 'size': 'S', 'sold_out': false, 'branch_stock': {'': 1, 'n1': 0}},
            {'id': 'v2', 'size': 'M', 'sold_out': true, 'branch_stock': {'': 0, 'n1': 4}},
          ],
        },
      ],
    });
    final north = s.inBranch('n1').products.single;
    expect(north.variants.map((v) => v.soldOut), [true, false]);
    expect(north.variants.last.few, isFalse);
    // Stock oculto: 4 = hay (no «quedan pocas»), 1 = quedan pocas
    expect(north.few, isFalse);
    expect(s.inBranch('').products.single.few, isTrue);
  });

  test('una sede que ya no existe vuelve a la Principal', () {
    final s = PublicStore.fromJson(json());
    expect(s.branchOf('cerrada').isMain, isTrue);
    expect(s.branchOf(null).name, 'Principal');
  });
}
