import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/business/presentation/business_identity.dart';

void main() {
  test('las claves no se repiten', () {
    final keys = kBusinessKinds.map((k) => k.key).toList();
    expect(keys.toSet(), hasLength(keys.length));
    expect(keys.length, greaterThanOrEqualTo(100));
  });

  test('los negocios creados antes conservan su ícono', () {
    const before = {
      'tienda': Icons.storefront_rounded,
      'ropa': Icons.checkroom_rounded,
      'ferreteria': Icons.handyman_rounded,
      'comida': Icons.restaurant_rounded,
      'drogueria': Icons.local_pharmacy_rounded,
      'belleza': Icons.content_cut_rounded,
      'papeleria': Icons.edit_note_rounded,
      'tecnologia': Icons.devices_rounded,
      'regalos': Icons.redeem_rounded,
      'otro': Icons.category_rounded,
    };
    before.forEach((key, icon) => expect(businessKindFor(key).icon, icon, reason: key));
  });

  test('un valor desconocido se muestra como tienda', () {
    expect(businessKindFor('no-existe').key, 'tienda');
    expect(businessKindFor(null).key, 'tienda');
  });

  test('el buscador ignora tildes y mayúsculas y usa otras palabras', () {
    List<String> keys(String q) => searchBusinessKinds(q).map((k) => k.key).toList();
    expect(keys('PAN').first, 'panaderia'); // el nombre va antes que "pantallas"
    expect(keys('pan'), contains('tv'));
    expect(keys('farmacia'), contains('drogueria'));
    expect(keys('unas'), contains('unas'));
    expect(keys('tecnologia'), contains('celulares')); // por rubro
    expect(keys('moto taller'), isEmpty); // todas las palabras deben coincidir
    expect(searchBusinessKinds('').length, kBusinessKinds.length);
  });

  test('lo que coincide por el nombre va arriba y lo relacionado aparte', () {
    final pan = searchBusinessKindsSplit('pan');
    expect(pan.byName.map((k) => k.key), ['panaderia']);
    expect(pan.related.map((k) => k.key), contains('tv')); // por "pantallas"

    final farmacia = searchBusinessKindsSplit('farmacia');
    expect(farmacia.byName, isEmpty);
    expect(farmacia.related.map((k) => k.key), contains('drogueria'));
  });

  testWidgets('el panel muestra el título de relacionados', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: const Scaffold(body: BusinessIconPickerSheet(selected: 'tienda', color: Color(0xFF1E6B4E))),
    ));
    await tester.enterText(find.byType(TextField), 'pan');
    await tester.pumpAndSettle();
    expect(find.text('Otros íconos relacionados con «pan»'), findsOneWidget);
    expect(find.byIcon(Icons.bakery_dining_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tv_rounded), findsOneWidget);
  });

  testWidgets('la fila abre el panel, se filtra y al elegir se cierra', (tester) async {
    var selected = 'tienda';
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => BusinessIconField(
            selected: selected,
            color: const Color(0xFFBE185D),
            onSelected: (key) => setState(() => selected = key),
          ),
        ),
      ),
    ));
    expect(find.text('Tienda'), findsOneWidget);
    expect(find.byIcon(Icons.pets_rounded), findsNothing); // el panel no está abierto

    await tester.tap(find.byType(BusinessIconField));
    await tester.pumpAndSettle();
    expect(find.text('Elegir ícono'), findsOneWidget);

    expect(find.text('TIENDAS'), findsOneWidget); // rubros dentro de la cuadrícula
    expect(find.byType(ChoiceChip), findsNothing);

    await tester.enterText(find.byType(TextField), 'perros');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.pets_rounded));
    await tester.pumpAndSettle();

    expect(selected, 'mascotas');
    expect(find.text('Elegir ícono'), findsNothing);
    expect(find.text('Mascotas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
