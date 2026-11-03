import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/design/country_flag.dart';
import 'package:stockealo/core/utils/countries.dart';

void main() {
  testWidgets('cada país tiene bandera dibujada y con nombre para lectores de pantalla', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [for (final c in kCountries) CountryFlag(code: c.code, width: 30)]),
      ),
    ));
    expect(tester.takeException(), isNull);
    for (final c in kCountries) {
      expect(find.bySemanticsLabel('Bandera de ${c.name}'), findsOneWidget);
    }
    expect(tester.getSize(find.byType(CountryFlag).first), const Size(30, 20));
  });
}
