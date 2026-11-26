import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/products/models/product_variant.dart';
import 'package:stockealo/core/design/qty_stepper.dart';
import 'package:stockealo/features/products/data/product_templates.dart';
import 'package:stockealo/features/products/presentation/widgets/variant_editor.dart';

/// 0.18.7: lo que notó el dueño probando en su negocio (tallas y cantidades)
void main() {
  group('la talla nueva se acomoda sola', () {
    test('la S olvidada queda antes de la M', () {
      final ctrl = VariantEditorController()..addSize('M, L, XL');
      ctrl.addSize('S');
      expect(ctrl.sizes, ['S', 'M', 'L', 'XL']);
      ctrl.addSize('xxl');
      expect(ctrl.sizes, ['S', 'M', 'L', 'XL', 'xxl']);
      ctrl.addSize('XS');
      expect(ctrl.sizes.first, 'XS');
    });

    test('números de menor a mayor, también medios números', () {
      final ctrl = VariantEditorController()..addSize('28, 32, 36');
      ctrl.addSize('30');
      ctrl.addSize('38');
      ctrl.addSize('34.5');
      expect(ctrl.sizes, ['28', '30', '32', '34.5', '36', '38']);
    });

    test('varias a la vez se ordenan entre ellas', () {
      final ctrl = VariantEditorController()..addSize('L, S, M');
      expect(ctrl.sizes, ['S', 'M', 'L']);
    });

    test('lo que no se conoce va al final y no reordena nada', () {
      final ctrl = VariantEditorController()..addSize('M, Única');
      ctrl.addSize('S');
      expect(ctrl.sizes, ['M', 'Única', 'S']);
      final mixed = VariantEditorController()..addSize('M, L');
      mixed.addSize('32 largo');
      expect(mixed.sizes, ['M', 'L', '32 largo']);
      // Letras y números juntos: la nueva va al final
      final both = VariantEditorController()..addSize('M, 32');
      both.addSize('S');
      expect(both.sizes, ['M', '32', 'S']);
    });

    test('SizeOrder reconoce los nombres comunes', () {
      expect(SizeOrder.letterRank('xxxl'), SizeOrder.letterRank('3XL'));
      expect(SizeOrder.letterRank('Única'), isNull);
      expect(SizeOrder.numberValue('7,5'), 7.5);
      expect(SizeOrder.numberValue('32 largo'), isNull);
    });
  });

  test('botón Pantalón: hombre, dama y niños por número', () {
    expect(VariantPreset.pants.map((p) => p.label), ['Hombre', 'Dama', 'Niños']);
    final ctrl = VariantEditorController()..applyPreset(VariantPreset.pantsMen);
    expect(ctrl.sizes, ['28', '30', '32', '34', '36', '38']);
    expect(ctrl.attributeName, 'Talla');
    expect(ctrl.usesColor, isTrue);
  });

  group('− y + en la cantidad', () {
    test('suma, resta y no baja de 0', () {
      final t = TextEditingController(text: '0');
      QtyStepper.step(t, -1);
      expect(t.text, '0');
      QtyStepper.step(t, 1);
      QtyStepper.step(t, 1);
      expect(t.text, '2');
      t.text = '50';
      QtyStepper.step(t, -1);
      expect(t.text, '49');
      t.text = '';
      QtyStepper.step(t, 1);
      expect(t.text, '1');
    });

    testWidgets('los botones cambian el número y se puede escribir', (tester) async {
      final t = TextEditingController(text: '0');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: QtyStepper.field(controller: t)))));
      await tester.tap(find.bySemanticsLabel('Sumar uno'));
      await tester.pump();
      expect(t.text, '1');
      await tester.tap(find.bySemanticsLabel('Restar uno'));
      await tester.pump();
      expect(t.text, '0');
      await tester.enterText(find.byType(TextField), '50');
      expect(t.text, '50');
    });

    testWidgets('dejar presionado sigue sumando', (tester) async {
      final t = TextEditingController(text: '0');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: QtyStepper.field(controller: t)))));
      final gesture = await tester.startGesture(tester.getCenter(find.bySemanticsLabel('Sumar uno')));
      await tester.pump(const Duration(milliseconds: 600)); // empieza el «presionado»
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      expect(int.parse(t.text), greaterThan(5));
      final after = t.text;
      await tester.pump(const Duration(seconds: 1));
      expect(t.text, after, reason: 'al soltar deja de sumar');
    });
  });

  group('orden de las tallas (A1)', () {
    test('mover una talla cambia también el orden de arriba', () {
      final ctrl = VariantEditorController()..addSize('M, L, XL');
      ctrl.addSize('Única'); // va al final
      ctrl.moveSize(3, 0);
      expect(ctrl.sizes, ['Única', 'M', 'L', 'XL']);
      ctrl.moveSize(0, 3);
      expect(ctrl.sizes, ['M', 'L', 'XL', 'Única']);
    });

    test('al guardar, cada variante lleva su posición, también los colores', () {
      final ctrl = VariantEditorController()..addSize('S, M');
      ctrl.addColorTo('M', VariantColor('Negro'));
      ctrl.addColorTo('M', VariantColor('Blanco'));
      ctrl.moveSize(1, 0);
      final list = ctrl.build(businessId: 'b', productId: 'p', now: DateTime(2026, 11, 25));
      expect([for (final v in list) '${v.label}:${v.sortOrder}'], ['M · Negro:0', 'M · Blanco:1', 'S:2']);
    });

    test('la posición va a la base local y a la nube, y vuelve igual', () {
      final v = ProductVariant(
          id: '1', businessId: 'b', productId: 'p', attributeValue: 'S', sortOrder: 4,
          createdAt: DateTime(2026), updatedAt: DateTime(2026));
      expect(v.toMap()['sort_order'], 4);
      expect(ProductVariant.cloudRow(v.toMap())['sort_order'], 4);
      expect(ProductVariant.fromMap(v.toMap()).sortOrder, 4);
      expect(v.copyWith(stock: 2).sortOrder, 4, reason: 'copyWith no lo pierde');
    });

    test('base local v34: agrega la columna y ordena; las de antes siguen por fecha', () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute(
          'CREATE TABLE product_variants (id TEXT PRIMARY KEY, product_id TEXT, attribute_value TEXT, created_at TEXT)');
      await db.insert('product_variants', {'id': 'a', 'product_id': 'p', 'attribute_value': 'M', 'created_at': '2026-01-01'});
      await db.insert('product_variants', {'id': 'b', 'product_id': 'p', 'attribute_value': 'L', 'created_at': '2026-01-02'});
      await AppDatabase.upgradeSchema(db, 33, 34);
      await AppDatabase.upgradeSchema(db, 33, 34); // dos veces no falla
      Future<List<Object?>> order() async =>
          [for (final r in await db.query('product_variants', orderBy: ProductVariant.orderBy)) r['attribute_value']];
      expect(await order(), ['M', 'L'], reason: 'sin orden guardado: por fecha, como antes');
      await db.insert('product_variants',
          {'id': 'c', 'product_id': 'p', 'attribute_value': 'S', 'created_at': '2026-01-03', 'sort_order': 0});
      await db.update('product_variants', {'sort_order': 1}, where: 'id = ?', whereArgs: ['a']);
      await db.update('product_variants', {'sort_order': 2}, where: 'id = ?', whereArgs: ['b']);
      expect(await order(), ['S', 'M', 'L']);
    });

    testWidgets('dejar presionada una talla en Existencias y soltarla más arriba', (tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = VariantEditorController()..addSize('M, L, Única');
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: VariantEditor(controller: c))),
      ));
      expect(find.text('Mantén presionada una talla para moverla'), findsOneWidget);
      final from = tester.getCenter(find.text('Talla Única'));
      final to = tester.getTopLeft(find.text('Talla M'));
      final gesture = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      // Se mueve de a poco, como el dedo
      for (var y = from.dy; y > to.dy - 30; y -= 20) {
        await gesture.moveTo(Offset(from.dx, y));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(c.sizes, ['Única', 'M', 'L']);
      expect(tester.takeException(), isNull);
    });
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets('fila con − y + sin desbordes a 360 px, letra x$scale y color largo', (tester) async {
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = VariantEditorController()..addSize('S, M');
      c.addColorTo('M', VariantColor('Azul oscuro con rayas blancas y bolsillo', hex: '#1F2F5A'));
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(size: const Size(360, 2400), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: SingleChildScrollView(child: VariantEditor(controller: c))),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Sumar uno'), findsNWidgets(2));
    });
  }
}
