import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/products/presentation/widgets/stock_row.dart';

/// 0.16.7, decisión E2: Stock como lista, con lo agotado y lo bajo arriba
void main() {
  Product p(String name, int stock, {int min = 5}) => Product(
        id: name,
        businessId: 'b',
        code: name,
        name: name,
        category: 'General',
        purchasePrice: 1000,
        salePrice: 1500,
        stock: stock,
        minStock: min,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  test('agotados primero, luego bajos y después el resto, por nombre', () {
    final sorted = StockRow.sorted([p('Arroz', 20), p('Leche', 0), p('Huevos', 3), p('Aceite', 2), p('Café', 0)]);
    expect(sorted.map((x) => x.name), ['Café', 'Leche', 'Aceite', 'Huevos', 'Arroz']);
  });

  for (final size in const [Size(360, 640), Size(1200, 700)]) {
    for (final brightness in Brightness.values) {
      testWidgets('se ve sin cortarse a ${size.width.toInt()} px (${brightness.name})', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.build(brightness),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                StockRow(product: p('Aceite de girasol Premier botella de un litro', 0), onTap: () {}, onAdjust: () {}),
                StockRow(product: p('Huevos', 3), onTap: () {}, onAdjust: () {}),
                StockRow(product: p('Arroz', 1250), onTap: () {}),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Agotado'), findsOneWidget);
        expect(find.text('Bajo'), findsOneWidget);
        expect(find.text('Ajustar'), findsNWidgets(2));
      });
    }
  }
}
