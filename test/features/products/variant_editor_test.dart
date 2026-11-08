import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/products/models/product_variant.dart';
import 'package:stockealo/features/products/presentation/widgets/variant_editor.dart';

ProductVariant _v(String id, String size, {String? color, String? hex, int stock = 0}) => ProductVariant(
      id: id,
      businessId: 'b1',
      productId: 'p1',
      attributeValue: size,
      attribute2Name: color == null ? null : 'Color',
      attribute2Value: color,
      colorHex: hex,
      stock: stock,
      createdAt: DateTime(2026, 11, 8),
      updatedAt: DateTime(2026, 11, 8),
    );

void main() {
  group('ProductVariant', () {
    test('el nombre junta talla y color', () {
      expect(_v('1', 'M').label, 'M');
      expect(_v('1', 'M', color: 'Rojo').label, 'M · Rojo');
      expect(_v('1', '', color: 'Rojo').label, 'Rojo');
    });

    test('separa lo escrito como "M (ROJO)" o "M - Rojo"', () {
      final a = ProductVariant.splitLegacy('M (ROJO)')!;
      expect(a.first, 'M');
      expect(a.second, 'Rojo');
      final b = ProductVariant.splitLegacy('XL - azul oscuro')!;
      expect(b.first, 'XL');
      expect(b.second, 'Azul oscuro');
      expect(ProductVariant.splitLegacy('M'), isNull);
      expect(ProductVariant.splitLegacy('38'), isNull);
    });

    test('solo acepta muestras de color válidas', () {
      expect(ProductVariant.validHex('c62828'), '#C62828');
      expect(ProductVariant.validHex('#ffffff'), '#FFFFFF');
      expect(ProductVariant.validHex('multi'), isNull);
      expect(ProductVariant.validHex('multi', allowMulti: true), 'multi');
      expect(ProductVariant.validHex('rojo'), isNull);
      expect(ProductVariant.validHex(''), isNull);
    });

    test('la fila para la nube no lleva columnas locales', () {
      final row = ProductVariant.cloudRow(_v('1', 'M', color: 'Rojo', hex: 'zzz', stock: 3).toMap());
      expect(row.containsKey('is_synced'), isFalse);
      expect(row['attribute2_value'], 'Rojo');
      expect(row['color_hex'], isNull); // inválido no se envía: la nube lo rechazaría
      expect(row['stock'], 3);
    });
  });

  group('VariantEditorController', () {
    test('tallas × colores forman la tabla y se pueden quitar combinaciones', () {
      final c = VariantEditorController();
      c.setSizes(['S', 'M']);
      c.upsertColor(VariantColor('Rojo', hex: '#C62828'));
      c.upsertColor(VariantColor('Verde', hex: '#2E7D32'));
      expect(c.combos.length, 4);

      c.removeCombo(VariantEditorController.cellKey('S', 'Verde'));
      expect(c.combos.length, 3);

      c.fillAll(2);
      expect(c.totalStock, 6);
      expect(c.totalForSize('M'), 4);
      expect(c.totalForColor(c.colors.first), 4);

      final built = c.build(businessId: 'b1', productId: 'p1', now: DateTime(2026, 11, 8));
      expect(built.map((v) => v.label), ['S · Rojo', 'M · Rojo', 'M · Verde']);
      expect(built.first.colorHex, '#C62828');
      expect(built.first.attribute2Name, 'Color');
      c.dispose();
    });

    test('sin colores, quitar una fila quita también la talla de arriba', () {
      final c = VariantEditorController()..setSizes(['S', 'M', 'L', 'XL']);
      for (final size in ['M', 'L', 'XL']) {
        c.removeCombo(VariantEditorController.cellKey(size, null));
      }
      expect(c.sizes, ['S']);
      expect(c.removed, isEmpty); // nada que "mostrar quitado"
      expect(c.combos.length, 1);
      c.dispose();
    });

    test('el caso de la captura: dejar solo S y luego agregar un color', () {
      final c = VariantEditorController()..setSizes(['S', 'M', 'L', 'XL']);
      for (final size in ['M', 'L', 'XL']) {
        c.removeCombo(VariantEditorController.cellKey(size, null));
      }
      c.cellFor(VariantEditorController.cellKey('S', null)).stock.text = '1';
      c.upsertColor(VariantColor('Rojo', hex: '#C62828'));
      expect(c.combos.map((x) => '${x.size} ${x.color?.name}'), ['S Rojo']);
      expect(c.totalStock, 1); // la unidad de la S pasa al rojo
      expect(c.removed, isEmpty);

      c.removeColor(c.colors.single);
      expect(c.totalStock, 1); // y vuelve a la S al quitar el color
      c.dispose();
    });

    test('con colores, quitar la última combinación de una talla la quita de arriba', () {
      final c = VariantEditorController()..setSizes(['S', 'M']);
      c.upsertColor(VariantColor('Rojo'));
      c.upsertColor(VariantColor('Verde'));
      c.removeCombo(VariantEditorController.cellKey('S', 'Rojo'));
      expect(c.sizes, ['S', 'M']); // a S le queda el verde
      c.removeCombo(VariantEditorController.cellKey('S', 'Verde'));
      expect(c.sizes, ['M']);
      expect(c.colors.length, 2);
      expect(c.removed, isEmpty);
      c.dispose();
    });

    test('sin colores funciona como antes: una fila por talla', () {
      final c = VariantEditorController()..setSizes(['36', '37']);
      final built = c.build(businessId: 'b1', productId: 'p1', now: DateTime(2026, 11, 8));
      expect(built.map((v) => v.label), ['36', '37']);
      expect(built.first.attribute2Name, isNull);
      c.dispose();
    });

    test('al cargar, las combinaciones que no existían quedan quitadas', () {
      final c = VariantEditorController()
        ..load([
          _v('a', 'M', color: 'Rojo', stock: 1),
          _v('b', 'L', color: 'Verde', stock: 2),
        ]);
      expect(c.combos.length, 2);
      expect(c.removed.length, 2);
      expect(c.totalStock, 3);
      c.dispose();
    });

    test('separar "M (ROJO)" conserva el id y las existencias de cada variante', () {
      final c = VariantEditorController()
        ..load([
          _v('a', 'M (ROJO)', stock: 1),
          _v('b', 'M (VERDE)', stock: 2),
          _v('c', 'L (ROJO)', stock: 3),
        ]);
      expect(c.canSplitLegacy, isTrue);
      c.splitLegacy();

      expect(c.sizes, ['M', 'L']);
      expect(c.colors.map((x) => x.name), ['Rojo', 'Verde']);
      expect(c.colors.first.hex, '#C62828'); // muestra sugerida por el nombre
      final built = c.build(businessId: 'b1', productId: 'p1', now: DateTime(2026, 11, 8));
      expect({for (final v in built) v.id: (v.label, v.stock)}, {
        'a': ('M · Rojo', 1),
        'b': ('M · Verde', 2),
        'c': ('L · Rojo', 3),
      });
      c.dispose();
    });

    test('renombrar un color mantiene sus existencias', () {
      final c = VariantEditorController()..setSizes(['M']);
      final rojo = VariantColor('Rojo');
      c.upsertColor(rojo);
      c.fillAll(5);
      c.upsertColor(VariantColor('Vinotinto', hex: '#7B1E3A'), replacing: rojo);
      expect(c.totalStock, 5);
      expect(c.combos.single.color!.name, 'Vinotinto');
      c.dispose();
    });
  });

  group('VariantEditor', () {
    for (final width in [360.0, 1200.0]) {
      testWidgets('se dibuja sin desbordes a ${width.toInt()} px', (tester) async {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final c = VariantEditorController()
          ..load([
            _v('a', 'M (ROJO)', stock: 1),
            _v('b', 'M (VERDE)', stock: 1),
            _v('c', 'L (AZUL OSCURO)', stock: 2),
          ]);
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(body: SingleChildScrollView(child: VariantEditor(controller: c))),
        ));
        expect(find.text('Separar talla y color'), findsOneWidget);

        await tester.tap(find.text('Separar talla y color'));
        await tester.pump();
        expect(find.text('Talla M'), findsOneWidget);
        expect(find.text('Azul oscuro'), findsWidgets);
        expect(find.text('Total: 4 unid.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        c.dispose();
      });
    }
  
    testWidgets('el diálogo de color se ve bien en un celular angosto', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = VariantEditorController()..setSizes(['M']);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: VariantEditor(controller: c))),
      ));
      await tester.tap(find.text('Agregar color'));
      await tester.pumpAndSettle();
      expect(find.text('Muestra'), findsOneWidget);
      await tester.tap(find.text('Es de dos colores (ej. blanca con roja)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Blanco').first);
      await tester.pump();
      await tester.tap(find.byTooltip('Rojo').last);
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Blanco con rojo'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(c.colors.single.name, 'Blanco con rojo');
      expect(c.colors.single.hex, '#FFFFFF');
      expect(c.colors.single.hex2, '#C62828');
      expect(tester.takeException(), isNull);
      c.dispose();
    });
  });
}
