import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/design/phone_field.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/core/utils/countries.dart';

Future<List<PhoneValue>> _pump(WidgetTester tester, {String? initial, String country = 'CO'}) async {
  final values = <PhoneValue>[];
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: PhoneField(
        initialValue: initial,
        defaultCountry: countryByCode(country),
        onChanged: values.add,
      ),
    ),
  ));
  return values;
}

void main() {
  testWidgets('arma el número con el prefijo del país', (tester) async {
    final values = await _pump(tester);
    expect(find.text('+57'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '300 123 4567');
    expect(values.last.e164, '+573001234567');
    expect(values.last.isValid, isTrue);
  });

  testWidgets('avisa si el número no tiene el largo del país', (tester) async {
    final values = await _pump(tester);
    await tester.enterText(find.byType(TextField), '30012');
    await tester.pump();
    expect(values.last.isValid, isFalse);
    expect(find.text('Debe tener 10 dígitos'), findsOneWidget);
  });

  testWidgets('vacío es válido y no guarda número', (tester) async {
    final values = await _pump(tester);
    await tester.enterText(find.byType(TextField), '300');
    await tester.enterText(find.byType(TextField), '');
    expect(values.last.e164, isNull);
    expect(values.last.isValid, isTrue);
  });

  testWidgets('un número guardado con prefijo muestra su país', (tester) async {
    await _pump(tester, initial: '+525512345678');
    expect(find.text('+52'), findsOneWidget);
    expect(find.text('5512345678'), findsOneWidget);
  });

  testWidgets('se puede cambiar de país', (tester) async {
    final values = await _pump(tester);
    await tester.tap(find.text('+57'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perú'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '912345678');
    expect(values.last.e164, '+51912345678');
    expect(values.last.isValid, isTrue);
  });
}
