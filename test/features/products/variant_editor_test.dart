import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/products/models/product_variant.dart';
import 'package:stockealo/features/products/presentation/widgets/photo_color_picker.dart';
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
    test('cada talla tiene sus propios colores (S solo rojo, M rojo y verde)', () {
      final c = VariantEditorController()..setSizes(['S', 'M']);
      c.addColorTo('S', VariantColor('Rojo', hex: '#C62828'));
      c.addColorTo('M', VariantColor('Rojo', hex: '#C62828'));
      c.addColorTo('M', VariantColor('Verde', hex: '#2E7D32'));

      expect(c.combos.map((x) => '${x.size} ${x.color?.name}'), ['S Rojo', 'M Rojo', 'M Verde']);
      expect(c.colorsOf('S').map((x) => x.name), ['Rojo']); // la S no recibe el verde
      expect(c.colors.map((x) => x.name), ['Rojo', 'Verde']);

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

    test('tallas con y sin colores conviven', () {
      final c = VariantEditorController()..setSizes(['S', 'M']);
      c.addColorTo('M', VariantColor('Azul'));
      final built = c.build(businessId: 'b1', productId: 'p1', now: DateTime(2026, 11, 8));
      expect(built.map((v) => v.label), ['S', 'M · Azul']);
      expect(built.first.attribute2Name, isNull);
      c.dispose();
    });

    test('la × de una talla sin colores la quita de arriba', () {
      final c = VariantEditorController()..setSizes(['S', 'M', 'L', 'XL']);
      for (final size in ['M', 'L', 'XL']) {
        c.removeCombo(VariantEditorController.cellKey(size, null));
      }
      expect(c.sizes, ['S']);
      expect(c.combos.length, 1);
      c.dispose();
    });

    test('el primer color de una talla se queda con sus unidades, y vuelven al quitarlo', () {
      final c = VariantEditorController()..setSizes(['S', 'M']);
      c.cellFor(VariantEditorController.cellKey('S', null)).stock.text = '3';
      c.addColorTo('S', VariantColor('Rojo'));
      expect(c.totalForSize('S'), 3);
      expect(c.totalForSize('M'), 0); // la M no se toca

      c.removeCombo(VariantEditorController.cellKey('S', 'Rojo'));
      expect(c.colorsOf('S'), isEmpty);
      expect(c.totalForSize('S'), 3);
      expect(c.sizes, ['S', 'M']); // quitar el color no quita la talla
      c.dispose();
    });

    test('los colores usados en otras tallas se sugieren con su muestra', () {
      final c = VariantEditorController()..setSizes(['S', 'M']);
      c.addColorTo('S', VariantColor('Rojo', hex: '#C62828'));
      c.addColorTo('S', VariantColor('Negro', hex: '#1F1D18'));
      c.addColorTo('M', VariantColor('Negro', hex: '#1F1D18'));
      expect(c.suggestionsFor('M').map((x) => x.name), ['Rojo']);
      expect(c.suggestionsFor('M').single.hex, '#C62828');
      c.dispose();
    });

    test('cambiar la muestra de un color la cambia en todas las tallas', () {
      final c = VariantEditorController()..setSizes(['S', 'M']);
      c.addColorTo('S', VariantColor('Rojo', hex: '#C62828'));
      c.addColorTo('M', VariantColor('Rojo', hex: '#C62828'));
      c.cellFor(VariantEditorController.cellKey('S', 'Rojo')).stock.text = '5';
      c.updateColorIn('S', c.colorsOf('S').single, VariantColor('Rojo', hex: '#7B1E3A'));
      expect(c.colorsOf('M').single.hex, '#7B1E3A');

      // renombrar solo en la S mantiene sus unidades
      c.updateColorIn('S', c.colorsOf('S').single, VariantColor('Vinotinto', hex: '#7B1E3A'));
      expect(c.colorsOf('S').single.name, 'Vinotinto');
      expect(c.colorsOf('M').single.name, 'Rojo');
      expect(c.totalForSize('S'), 5);
      c.dispose();
    });

    test('al cargar, cada talla recupera solo sus colores', () {
      final c = VariantEditorController()
        ..load([
          _v('a', 'S', color: 'Rojo', stock: 1),
          _v('b', 'M', color: 'Rojo', stock: 2),
          _v('c', 'M', color: 'Verde', stock: 3),
          _v('d', 'L', stock: 4),
        ]);
      expect(c.colorsOf('S').map((x) => x.name), ['Rojo']);
      expect(c.colorsOf('M').map((x) => x.name), ['Rojo', 'Verde']);
      expect(c.colorsOf('L'), isEmpty);
      expect(c.totalStock, 10);
      final ids = c.build(businessId: 'b1', productId: 'p1', now: DateTime(2026, 11, 8)).map((v) => v.id);
      expect(ids, ['a', 'b', 'c', 'd']); // se conservan para el historial de ventas
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
      expect(c.colorsOf('L').map((x) => x.name), ['Rojo']); // la L no recibe el verde
      expect(c.colors.first.hex, '#C62828'); // muestra sugerida por el nombre
      final built = c.build(businessId: 'b1', productId: 'p1', now: DateTime(2026, 11, 8));
      expect({for (final v in built) v.id: (v.label, v.stock)}, {
        'a': ('M · Rojo', 1),
        'b': ('M · Verde', 2),
        'c': ('L · Rojo', 3),
      });
      c.dispose();
    });

    test('sin tallas, el producto puede variar solo por color', () {
      final c = VariantEditorController();
      c.addColorTo('', VariantColor('Rojo'));
      c.addColorTo('', VariantColor('Azul'));
      final built = c.build(businessId: 'b1', productId: 'p1', now: DateTime(2026, 11, 8));
      expect(built.map((v) => v.label), ['Rojo', 'Azul']);

      // al agregar la primera talla, esos colores pasan a ella
      c.addSize('Única');
      expect(c.colorsOf('Única').map((x) => x.name), ['Rojo', 'Azul']);
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
        expect(find.text('Talla L'), findsOneWidget);
        expect(find.text('Azul oscuro'), findsWidgets);
        expect(find.text('Total: 4 unid.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        c.dispose();
      });
    }

    testWidgets('"+ Color" en una talla agrega el color solo a esa talla', (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = VariantEditorController()..setSizes(['S', 'M']);
      c.addColorTo('S', VariantColor('Rojo', hex: '#C62828'));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: VariantEditor(controller: c))),
      ));

      // El "+ Color" de la talla M es el segundo
      await tester.tap(find.text('Color').at(1));
      await tester.pumpAndSettle();
      expect(find.text('Agregar color a la talla m'), findsOneWidget);
      expect(find.text('Ya usados'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'Rojo'));
      await tester.pumpAndSettle();

      expect(c.colorsOf('M').single.name, 'Rojo');
      expect(c.colorsOf('M').single.hex, '#C62828');
      expect(c.colorsOf('S').length, 1);
      expect(tester.takeException(), isNull);
      c.dispose();
    });

    test('cada color de la paleta recibe su propio nombre', () {
      for (final e in VariantEditorController.palette.entries) {
        final color = Color(int.parse('FF${e.value.substring(1)}', radix: 16));
        expect(VariantEditorController.colorNameFor(color), e.key, reason: e.value);
      }
    });

    test('nombra cualquier color: grises, claros y oscuros', () {
      String name(int argb) => VariantEditorController.colorNameFor(Color(argb));
      expect(name(0xFF6F6E6C), 'Gris'); // el de la captura salía "Café"
      expect(name(0xFFD0D0D0), 'Gris claro');
      expect(name(0xFF3A3A3A), 'Gris oscuro');
      expect(name(0xFF0B6623), 'Verde oscuro');
      expect(name(0xFFA5D6A7), 'Verde claro');
      expect(name(0xFFFA3838), 'Rojo'); // el código de la otra captura
      expect(name(0xFF8D6E63), 'Café');
      expect(name(0xFFB8860B), 'Mostaza');
      expect(name(0xFF00838F), 'Turquesa oscuro');
      expect(name(0xFF26C6DA), 'Turquesa');
    });

    test('el color de la foto es el promedio alrededor del toque', () {
      // Imagen de 4×1: dos píxeles rojos y dos azules
      final rgba = ByteData(16);
      for (var i = 0; i < 4; i++) {
        rgba.setUint8(i * 4, i < 2 ? 200 : 0);
        rgba.setUint8(i * 4 + 2, i < 2 ? 0 : 200);
        rgba.setUint8(i * 4 + 3, 255);
      }
      final left = PhotoColorPicker.sampleAround(rgba, 4, 1, 0, 0, radius: 0);
      expect(left, const Color(0xFFC80000));
      final middle = PhotoColorPicker.sampleAround(rgba, 4, 1, 1, 0, radius: 1);
      expect(middle.red, greaterThan(middle.blue)); // 2 rojos y 1 azul
    });

    testWidgets('"Más colores" deja elegir con las barras sin escribir códigos', (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = VariantEditorController()..setSizes(['M']);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: VariantEditor(controller: c))),
      ));
      await tester.tap(find.text('Color'));
      await tester.pumpAndSettle();
      expect(find.text('Código del color (hexadecimal)'), findsNothing); // escondido en avanzadas
      expect(find.text('De la foto'), findsNothing); // el producto no tiene foto
      expect(find.text('Tomar de la pantalla'), findsNothing); // solo en el computador

      await tester.tap(find.text('Más colores'));
      await tester.pumpAndSettle();
      expect(find.text('Tono'), findsOneWidget);
      // Tocar el azul en la barra de tono (hacia los dos tercios)
      final bar = tester.getRect(find.ancestor(of: find.text('Tono'), matching: find.byType(Row)).first);
      await tester.tapAt(Offset(bar.left + 74 + (bar.width - 74) * 0.62, bar.center.dy));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final color = c.colorsOf('M').single;
      expect(color.hex, isNotNull);
      expect(color.name, anyOf('Azul', 'Azul cielo', 'Azul oscuro', 'Turquesa'));
      expect(tester.takeException(), isNull);
      c.dispose();
    });

    testWidgets('en opciones avanzadas la etiqueta del código no queda cortada', (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = VariantEditorController()..setSizes(['M']);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: VariantEditor(controller: c))),
      ));
      await tester.tap(find.text('Color'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rojo').first); // con valor, la etiqueta flota arriba
      await tester.pump();
      await tester.tap(find.text('Opciones avanzadas'));
      await tester.pumpAndSettle();

      // La fila del título recorta lo que se le meta encima: la etiqueta flotante
      // tiene que quedar completa debajo de ella
      final header = tester.getRect(find.ancestor(of: find.text('Opciones avanzadas'), matching: find.byType(ListTile)));
      final label = tester.getRect(find.text('Código del color (hexadecimal)'));
      expect(label.top, greaterThanOrEqualTo(header.bottom));
      c.dispose();
    });

    testWidgets('al escribir el código, el nombre también cambia', (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = VariantEditorController()..setSizes(['M']);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: VariantEditor(controller: c))),
      ));
      await tester.tap(find.text('Color'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Opciones avanzadas'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Código del color (hexadecimal)'), '0B6623');
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Verde oscuro'), findsOneWidget);
      c.dispose();
    });

    test('del nombre a la muestra: conocidos, personalizados y sin pista', () {
      final rojo = VariantEditorController.swatchForName('Rojo')!;
      expect(rojo.hex, '#C62828');
      expect(rojo.exact, isTrue);
      expect(VariantEditorController.swatchForName('gris oscuro')!.exact, isTrue);
      expect(VariantEditorController.swatchForName('Verde menta')!.hex, '#98D8C8');

      final bajito = VariantEditorController.swatchForName('Azul bajito')!;
      expect(bajito.exact, isFalse); // nombre propio
      final azul = HSLColor.fromColor(const Color(0xFF1565C0));
      final claro = HSLColor.fromColor(Color(int.parse('FF${bajito.hex.substring(1)}', radix: 16)));
      expect(claro.lightness, greaterThan(azul.lightness)); // "bajito" = más claro
      expect(VariantEditorController.colorNameFor(Color(int.parse('FF${bajito.hex.substring(1)}', radix: 16))),
          startsWith('Azul'));

      expect(VariantEditorController.swatchForName('Pepito'), isNull);
      expect(VariantEditorController.swatchForName('Estampado')!.hex, 'multi');
    });

    testWidgets('escribir el nombre pone la muestra y marca los nombres personalizados', (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = VariantEditorController()..setSizes(['M']);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: VariantEditor(controller: c))),
      ));
      await tester.tap(find.text('Color'));
      await tester.pumpAndSettle();
      final nameField = find.widgetWithText(TextField, 'Nombre del color');

      await tester.enterText(nameField, 'Rojo');
      await tester.pump();
      expect(find.textContaining('Nombre personalizado'), findsNothing);

      await tester.enterText(nameField, 'Azul bajito');
      await tester.pump();
      expect(find.textContaining('Nombre personalizado: pusimos una muestra parecida'), findsOneWidget);

      // Elegir la muestra a mano la deja fija aunque se siga escribiendo
      await tester.tap(find.byTooltip('Lila').first);
      await tester.pump();
      await tester.enterText(nameField, 'Azul bajito de verano');
      await tester.pump();
      expect(find.text('Nombre personalizado'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      final color = c.colorsOf('M').single;
      expect(color.name, 'Azul bajito de verano');
      expect(color.hex, '#B39DDB');

      c.dispose();
    });

    test('distingue los nombres de la paleta de los escritos a mano', () {
      expect(VariantEditorController.isPaletteName('Rojo'), isTrue);
      expect(VariantEditorController.isPaletteName('blanco con rojo'), isTrue);
      expect(VariantEditorController.isPaletteName('Vinotinto clarito'), isFalse);
      expect(VariantEditorController.isPaletteName('Gris oscuro'), isTrue); // puesto por la app
    });

    testWidgets('al cambiar la muestra de un color ya creado, el nombre la sigue', (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = VariantEditorController()..setSizes(['M']);
      c.addColorTo('M', VariantColor('Rojo', hex: '#C62828'));
      c.addColorTo('M', VariantColor('Vinotinto clarito', hex: '#7B1E3A'));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: VariantEditor(controller: c))),
      ));

      // Rojo → Café: se renombra
      await tester.tap(find.text('Rojo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Café').first);
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(c.colorsOf('M').first.name, 'Café');
      expect(c.colorsOf('M').first.hex, '#6D4C41');

      // Nombre escrito a mano: se respeta aunque cambie la muestra
      await tester.tap(find.text('Vinotinto clarito'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rosado').first);
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(c.colorsOf('M').last.name, 'Vinotinto clarito');
      expect(c.colorsOf('M').last.hex, '#F48FB1');
      expect(c.totalStock, 0);
      c.dispose();
    });

    testWidgets('el diálogo de color se ve bien en un celular angosto', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = VariantEditorController()..setSizes(['M']);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: VariantEditor(controller: c))),
      ));
      await tester.tap(find.text('Color'));
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
      final color = c.colorsOf('M').single;
      expect(color.name, 'Blanco con rojo');
      expect(color.hex, '#FFFFFF');
      expect(color.hex2, '#C62828');
      expect(tester.takeException(), isNull);
      c.dispose();
    });
  });
}
