import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/services/models/service_template.dart';
import 'package:stockealo/features/services/presentation/screens/services_tab.dart';

/// 0.14.0: lo que respondió al crear el negocio («¿Para qué usarás Stockealo?»)
/// sugiere la plantilla de Servicios cuando compra Pro Servicios.
void main() {
  test('cada tipo de negocio sugiere su plantilla; los de productos, ninguna', () {
    expect(ServiceTemplate.suggestedFor('lavadero'), ServiceTemplate.lavadero);
    expect(ServiceTemplate.suggestedFor('barberia'), ServiceTemplate.barberia);
    expect(ServiceTemplate.suggestedFor('unas'), ServiceTemplate.spa);
    expect(ServiceTemplate.suggestedFor('llantas'), ServiceTemplate.taller);
    expect(ServiceTemplate.suggestedFor('celulares'), ServiceTemplate.tecnico);
    expect(ServiceTemplate.suggestedFor('lavanderia'), ServiceTemplate.lavanderia);
    expect(ServiceTemplate.suggestedFor('licores'), isNull);
    expect(ServiceTemplate.suggestedFor(null), isNull);
  });

  testWidgets('la sugerida sale primero y marcada; se puede elegir otra', (tester) async {
    final business = Business(id: 'b', userId: 'u', name: 'Lavadero', icon: 'lavadero', createdAt: DateTime(2026));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: TemplatePicker(business: business, canConfigure: true),
    ));
    expect(find.text('Sugerida para tu negocio'), findsOneWidget);
    final first = tester.getTopLeft(find.text(ServiceTemplate.lavadero.label)).dy;
    final other = tester.getTopLeft(find.text(ServiceTemplate.barberia.label)).dy;
    expect(first, lessThan(other));
  });
}
