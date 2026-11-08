import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/products/presentation/widgets/category_name_dialog.dart';

Future<String?> _open(WidgetTester tester, {List<String> existing = const [], String? initial}) async {
  String? result = 'sin cerrar';
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.build(Brightness.light),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => result = await CategoryNameDialog.show(context, existing: existing, initial: initial),
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  test('limpia el nombre', () {
    expect(CategoryNameDialog.clean('  bebidas   frías '), 'Bebidas frías');
    expect(CategoryNameDialog.clean('   '), '');
  });

  testWidgets('crear: título con el estilo de la app y botón apagado sin nombre', (tester) async {
    await _open(tester);
    expect(find.text('Nueva categoría'), findsOneWidget);
    final crear = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Crear'));
    expect(crear.onPressed, isNull);
  });

  testWidgets('crear una que ya existe con otra escritura elige la existente', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await CategoryNameDialog.show(context, existing: ['Ropa', 'Bebidas']),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ropa ');
    await tester.pump();
    expect(find.text('Ya tienes "Ropa": se elegirá esa.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Elegir'));
    await tester.pumpAndSettle();
    expect(result, 'Ropa');
  });

  testWidgets('renombrar a una que ya existe no se permite', (tester) async {
    await _open(tester, existing: ['Ropa', 'Bebidas'], initial: 'Bebidas');
    expect(find.text('Renombrar categoría'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ropa');
    await tester.pump();
    expect(find.text('Ya tienes una categoría "Ropa".'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar')).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'bebidas frías');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar')).onPressed, isNotNull);
  });
}
