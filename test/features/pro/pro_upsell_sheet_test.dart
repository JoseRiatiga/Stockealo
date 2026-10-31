import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/pro/data/pro_service.dart';
import 'package:stockealo/features/pro/presentation/widgets/pro_upsell_sheet.dart';

/// Pantalla de celular (360 × 800) para que la ventana quepa entera
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  ProPlan plan(String period, double price) => ProPlan(
        id: '$period-$price',
        kind: 'business',
        period: period,
        currency: 'COP',
        price: price,
      );

  group('precio de entrada', () {
    test('toma el plan semanal o mensual más barato', () {
      final text = ProUpsellSheet.priceFromText([plan('lifetime', 1000), plan('month', 6900), plan('week', 2000)]);
      expect(text, startsWith('Desde'));
      expect(text, contains('2.000'));
      expect(text, contains('/ semana'));
    });

    test('sin planes no hay precio', () {
      expect(ProUpsellSheet.priceFromText(const []), isNull);
      expect(ProUpsellSheet.priceFromText([plan('lifetime', 39900)]), isNull);
    });
  });

  testWidgets('la ventana muestra lo que tocaste, los beneficios y se cierra con "Ahora no"', (tester) async {
    usePhoneSize(tester);
    ProUpsellResult? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await ProUpsellSheet.show(
              context,
              business: Business(id: 'b1', name: 'Tienda', userId: 'u1', createdAt: DateTime(2026)),
              title: 'Estado de cuenta en PDF',
              message: 'Envíale a Ana su saldo.',
              highlight: ProBenefit.debtCollection,
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Estado de cuenta en PDF'), findsOneWidget);
    expect(find.text('Cobro automático de fiados'), findsOneWidget);
    expect(find.text('Ver planes'), findsOneWidget);
    expect(find.text('Ya tengo un código'), findsOneWidget);

    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();
    expect(result, ProUpsellResult.dismissed);
    expect(find.text('Estado de cuenta en PDF'), findsNothing);
  });

  testWidgets('con opción gratis, la ventana la ofrece en lugar de "Ahora no"', (tester) async {
    usePhoneSize(tester);
    ProUpsellResult? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await ProUpsellSheet.show(
              context,
              business: Business(id: 'b1', name: 'Tienda', userId: 'u1', createdAt: DateTime(2026)),
              title: '¿Te gusta cómo quedó?',
              message: 'Tu catálogo usa fondo oscuro.',
              highlight: ProBenefit.catalogs,
              alternativeLabel: 'Descargar la versión gratis',
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Ahora no'), findsNothing);

    await tester.tap(find.text('Descargar la versión gratis'));
    await tester.pumpAndSettle();
    expect(result, ProUpsellResult.alternative);
  });
}
