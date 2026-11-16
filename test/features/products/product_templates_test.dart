import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/maintenance_service.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/products/data/product_repository.dart';
import 'package:stockealo/features/products/data/product_templates.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/products/presentation/screens/product_form_screen.dart';
import 'package:stockealo/features/products/presentation/widgets/product_template_sheet.dart';
import 'package:stockealo/features/products/presentation/widgets/variant_editor.dart';
import 'package:stockealo/features/store/data/online_store_service.dart';
import 'package:stockealo/store_web/store_page.dart';

/// 0.16.0, fase 2a: tipos de negocio que venden productos
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'templates-test';
  const businessId = 'biz-tpl';
  final appDb = AppDatabase.instance;

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    dbDir = await Directory.systemTemp.createTemp('stockealo_tpl_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
    }
    await loader.load();
  });

  setUp(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    final db = await appDb.database;
    await db.insert('users', {'id': 'u1', 'email': 'rosa@x.com', 'password': authManagedPassword, 'created_at': '2026-10-01'});
    await db.insert('businesses', Business(id: businessId, userId: 'u1', name: 'Licores La 14', icon: 'licores', createdAt: DateTime(2026)).toMap());
  });

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('la plantilla sugerida sale de «¿Para qué usarás Stockealo?»', () {
    expect(ProductTemplate.suggestedFor('licores'), ProductTemplate.licorera);
    expect(ProductTemplate.suggestedFor('vapers'), ProductTemplate.vapers);
    expect(ProductTemplate.suggestedFor('drogueria'), ProductTemplate.drogueria);
    expect(ProductTemplate.suggestedFor('ropa'), ProductTemplate.ropa);
    expect(ProductTemplate.suggestedFor('panaderia'), ProductTemplate.comidas);
    expect(ProductTemplate.suggestedFor('miscelanea'), ProductTemplate.barrio);
    expect(ProductTemplate.suggestedFor('ferreteria'), isNull);
    expect(ProductTemplate.licorera.adult, isTrue);
    expect(ProductTemplate.vapers.storeTemplate, StoreTemplate.boutique);
    expect(ProductTemplate.comidas.storeTemplate, StoreTemplate.menu);
  });

  test('cargar la plantilla agrega solo las categorías que faltan, sin repetir', () async {
    final repo = ProductRepository();
    await repo.addCategory('cerveza', businessId); // ya la tenía, en minúscula
    expect(await ProductTemplate.applied(businessId), isNull);
    final added = await ProductTemplate.licorera.apply(businessId, categories: ['Ron', 'Cerveza', 'Whisky']);
    expect(added, 2);
    final names = (await repo.getCategories(businessId)).map((c) => c.name).toList();
    expect(names.where((n) => n.toLowerCase() == 'cerveza').length, 1);
    expect(names, containsAll(['Ron', 'Whisky']));
    expect(await ProductTemplate.applied(businessId), ProductTemplate.licorera);
    // Cargarla otra vez no duplica nada
    expect(await ProductTemplate.licorera.apply(businessId, categories: ['Ron']), 0);
    expect(ProductTemplate.plain('Lácteos  y huevos'), 'lacteos y huevos');
  });

  test('lote encendido por defecto: droguería siempre, barrio solo en lo perecedero (0.16.3)', () {
    expect(ProductTemplate.drogueria.expiryByDefault('Analgésicos'), isTrue);
    expect(ProductTemplate.barrio.expiryByDefault('Lácteos y huevos'), isTrue);
    expect(ProductTemplate.barrio.expiryByDefault('panadería'), isTrue);
    expect(ProductTemplate.barrio.expiryByDefault('Carnes frías'), isTrue);
    expect(ProductTemplate.barrio.expiryByDefault('Bebidas'), isFalse);
    expect(ProductTemplate.barrio.expiryByDefault('Aseo'), isFalse);
    expect(ProductTemplate.barrio.expiryByDefault(null), isFalse);
    expect(ProductTemplate.licorera.expiryByDefault('Ron'), isFalse);
  });

  testWidgets('Nuevo producto: el lote no salta al escribir precios y en Bebidas viene apagado', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => ProductTemplate.barrio.apply(businessId, categories: ['Bebidas', 'Lácteos y huevos']));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: const ProductFormScreen(businessId: businessId)));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    final lot = find.widgetWithText(SwitchListTile, 'Controla vencimiento por lote');
    expect(lot, findsOneWidget);
    // La primera categoría es Bebidas: apagado
    expect(tester.widget<SwitchListTile>(lot).value, isFalse);
    final before = tester.getTopLeft(lot).dy;
    expect(find.text('Escribe el costo para ver precios sugeridos'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Precio de Compra'), '2000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Precio de Venta *'), '3000');
    await tester.pump();
    expect(find.text('Precio para ganar'), findsOneWidget);
    expect(tester.getTopLeft(lot).dy, before);
    expect(tester.takeException(), isNull);
  });

  test('la marca se guarda en el producto', () {
    final now = DateTime(2026, 11, 15);
    final prod = Product(
      id: 'p1', businessId: businessId, code: 'V1', name: 'Elf Bar BC5000', category: 'Desechables',
      purchasePrice: 30000, salePrice: 55000, stock: 10, createdAt: now, updatedAt: now, brand: ' Elf Bar ',
    );
    expect(Product.fromMap(prod.toMap()).brand, 'Elf Bar');
    expect(Product.fromMap({...prod.toMap(), 'brand': '  '}).brand, isNull);
    expect(prod.copyWith(clearBrand: true).brand, isNull);
  });

  test('vapers: nicotina y sabor; el sabor no lleva muestra de color', () {
    final ctrl = VariantEditorController();
    ctrl.applyPreset(VariantPreset.nicotine);
    expect(ctrl.attributeName, 'Nicotina');
    expect(ctrl.secondName, 'Sabor');
    expect(ctrl.secondPlural, 'Sabores');
    expect(ctrl.sizes, ['0 mg', '20 mg', '50 mg']);
    ctrl.addOption('Mango, Uva');
    ctrl.addOption('Menta', size: '50 mg');
    expect(ctrl.combos.length, 7); // 3 × 2 + la menta de 50 mg
    final built = ctrl.build(businessId: businessId, productId: 'p1', now: DateTime(2026));
    expect(built.every((v) => v.attribute2Name == 'Sabor' && v.colorHex == null), isTrue);
    expect(built.map((v) => '${v.attributeValue} · ${v.attribute2Value}'), contains('50 mg · Menta'));
    // Al abrirlo otra vez, sigue siendo nicotina y sabor
    final again = VariantEditorController()..load(built);
    expect(again.attributeName, 'Nicotina');
    expect(again.secondName, 'Sabor');
    expect(again.usesColor, isFalse);
    // Ropa sigue con talla y color
    expect((VariantEditorController()..applyPreset(VariantPreset.clothes)).usesColor, isTrue);
  });

  const vapeStore = PublicStore(
    slug: 'vape-house',
    whatsapp: '573001234567',
    businessName: 'Vape House',
    currency: 'COP',
    template: StoreTemplate.classic,
    look: StoreLook(adult: true),
    products: [
      StoreProduct(
        id: 'elf',
        name: 'Elf Bar BC5000',
        category: 'Desechables',
        price: 55000,
        brand: 'Elf Bar',
        variants: [
          StoreVariant(id: 'v1', size: '20 mg', color: 'Mango', sizeName: 'Nicotina', optionName: 'Sabor'),
          StoreVariant(id: 'v2', size: '50 mg', color: 'Uva', sizeName: 'Nicotina', optionName: 'Sabor'),
        ],
      ),
      StoreProduct(id: 'lost', name: 'Lost Mary', category: 'Desechables', price: 48000, brand: 'Lost Mary'),
    ],
  );

  Future<void> pumpStore(WidgetTester tester, PublicStore store) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: StorePage(slug: store.slug, loader: (_) async => store, maintenanceLoader: () async => MaintenanceState.none),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('aviso +18: no deja ver la tienda hasta decir que sí', (tester) async {
    await pumpStore(tester, vapeStore);
    expect(find.text('Esta tienda vende productos para mayores de 18 años'), findsOneWidget);
    // La tienda se ve detrás, difuminada, pero no se puede tocar (0.16.2)
    expect(find.byKey(const ValueKey('adult-gate-blur')), findsOneWidget);
    expect(find.text('Elf Bar BC5000'), findsOneWidget);
    expect(find.text('Elf Bar BC5000').hitTestable(), findsNothing);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(find.text('Lo sentimos: solo pueden entrar mayores de edad.'), findsOneWidget);
    expect(find.text('Elf Bar BC5000').hitTestable(), findsNothing);
    expect(find.byKey(const ValueKey('adult-gate-blur')), findsOneWidget);
  });

  testWidgets('vapers en la tienda: se entra con «Sí», pide nicotina y sabor, y filtra por marca', (tester) async {
    await pumpStore(tester, vapeStore);
    await tester.tap(find.text('Sí, entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Elf Bar BC5000'), findsOneWidget);
    expect(find.textContaining('nicotina y sabor'), findsOneWidget);
    expect(find.text('Mango'), findsOneWidget, reason: 'el sabor sale con su nombre, sin muestra de color');
    // 0.16.3: sin foto se ve una caja, no la percha de la ropa
    expect(find.byIcon(NoPhotoIcon.icon), findsWidgets);
    expect(find.byIcon(Icons.checkroom_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Productos: la tarjeta, elegir Licorera y revisar lo que se carga', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final biz = Business(id: businessId, userId: 'u1', name: 'Licores La 14', icon: 'licores', createdAt: DateTime(2026));
    var applied = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: ProductTemplateCard(business: biz, onApplied: () => applied++)),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.text('Arma tu inventario de licorera'), findsOneWidget);
    await tester.tap(find.text('Arma tu inventario de licorera'));
    await tester.pumpAndSettle();
    expect(find.text('¿Qué tipo de negocio es?'), findsOneWidget);
    expect(find.text('Sugerida'), findsOneWidget);
    await tester.tap(find.text('Licorera'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Tequila'));
    await tester.pumpAndSettle();
    expect(find.text('Aviso +18 en la tienda'), findsOneWidget);
    // Cargar (agregar las categorías) ya se prueba arriba con la base real
    expect(find.text('Cargar plantilla'), findsOneWidget);
    expect(applied, 0);
    expect(tester.takeException(), isNull);
  });

  test('el filtro por marca', () {
    final f = StoreFilters()..brand = 'Lost Mary';
    expect(vapeStore.products.where(f.matches).map((x) => x.id), ['lost']);
    expect(vapeStore.brands, ['Elf Bar', 'Lost Mary']);
    expect((StoreFilters()..query = 'elf').matches(vapeStore.products.first), isTrue);
    expect(const StoreLook(adult: true).toJson()['adult'], isTrue);
    expect(StoreLook.fromJson({'adult': true}).adult, isTrue);
  });
}
