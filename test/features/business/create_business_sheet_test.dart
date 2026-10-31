import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/business/presentation/widgets/create_business_sheet.dart';

void main() {
  Future<NewBusinessData?> openAndFill(WidgetTester tester, {String? country}) async {
    NewBusinessData? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await CreateBusinessSheet.show(context),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Miselanea');
    if (country != null) {
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(country).last);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Crear negocio'));
    await tester.tap(find.text('Crear negocio'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('pide el nombre antes de crear', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => CreateBusinessSheet.show(context), child: const Text('abrir')),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Crear negocio'));
    await tester.tap(find.text('Crear negocio'));
    await tester.pump();
    expect(find.text('Escribe el nombre de tu negocio'), findsOneWidget);
  });

  testWidgets('crea el negocio con ícono y color por defecto', (tester) async {
    final data = await openAndFill(tester);
    expect(data, isNotNull);
    expect(data!.name, 'Miselanea');
    expect(data.icon, 'tienda');
    expect(data.color, '#1E6B4E');
  });

  testWidgets('elegir el país cambia la moneda', (tester) async {
    final data = await openAndFill(tester, country: 'México');
    expect(data!.country, 'MX');
    expect(data.currency, 'MXN');
  });
}
