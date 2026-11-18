import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/products/presentation/category_icons.dart';
import 'package:stockealo/features/store/data/online_store_service.dart';

void main() {
  test('el ícono se sugiere por el nombre de la categoría (#28)', () {
    expect(CategoryIcon.suggest('Bebidas'), 'drink');
    expect(CategoryIcon.suggest('Aseo y limpieza'), 'cleaning');
    expect(CategoryIcon.suggest('Calzado'), 'shoe');
    expect(CategoryIcon.suggest('Lácteos'), 'dairy');
    expect(CategoryIcon.suggest('Licores'), 'liquor');
    expect(CategoryIcon.suggest('Mascotas'), 'pet');
    expect(CategoryIcon.suggest('Xyz'), isNull);
  });

  test('claves únicas y una desconocida se ve con el dibujo de siempre', () {
    final keys = kCategoryIcons.map((c) => c.key).toList();
    expect(keys.toSet().length, keys.length);
    expect(keys.every((k) => RegExp(r'^[a-z_]{1,40}$').hasMatch(k)), isTrue, reason: 'la nube solo acepta estas claves');
    expect(CategoryIcon.of('drink'), Icons.local_drink_outlined);
    expect(CategoryIcon.of('otra'), CategoryIcon.fallback);
    expect(CategoryIcon.of(null), isNull);
  });

  test('la tienda trae los íconos y se pueden apagar', () {
    final json = {
      'slug': 'x',
      'business': {'name': 'Tienda'},
      'category_icons': {'bebidas': 'drink'},
      'look': {'icons': false},
      'products': [],
    };
    final off = PublicStore.fromJson(json);
    expect(off.categoryIcons, {'bebidas': 'drink'});
    expect(off.iconOf('Bebidas'), isNull, reason: 'apagados');
    final on = PublicStore.fromJson({...json, 'look': {}});
    expect(on.look.icons, isTrue, reason: 'las tiendas de antes los muestran');
    expect(on.iconOf(' Bebidas '), 'drink');
    expect(StoreLook.fromJson({'icons': false}).toJson()['icons'], isFalse);
  });
}
