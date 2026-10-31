import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/reports/data/catalog_pdf_service.dart';
import 'package:stockealo/features/reports/models/catalog_style.dart';

Product _product(String id, {String category = 'General', int stock = 3, String? photo, String? description}) {
  final now = DateTime(2026, 10, 30);
  return Product(
    id: id,
    businessId: 'b1',
    code: 'SKU-$id',
    name: 'Producto $id',
    description: description,
    category: category,
    purchasePrice: 1000,
    salePrice: 2500,
    stock: stock,
    photoPath: photo,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // El PDF se escribe en la carpeta temporal del sistema
  late Directory tempDir;
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('catalogo_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
  });
  tearDownAll(() => tempDir.delete(recursive: true));

  group('CatalogStyle', () {
    test('se guarda y se lee igual', () {
      const style = CatalogStyle(
        colorHex: '#1D5FA8',
        darkBackground: true,
        itemsPerPage: 2,
        title: 'Temporada',
        whatsapp: '+57 300 000 0000',
        address: 'Calle 1',
        hours: 'Lun a Sáb',
        social: '@tienda',
        showPrice: false,
        showExactStock: true,
        showCode: true,
        showDescription: false,
        showCategory: false,
        onlyWithPhoto: true,
        selectedProductIds: {'a', 'b'},
      );
      final back = CatalogStyle.decode(style.encode());
      expect(back.toJson(), style.toJson());
    });

    test('un valor dañado o vacío da el estilo por defecto', () {
      expect(CatalogStyle.decode(null).toJson(), const CatalogStyle().toJson());
      expect(CatalogStyle.decode('{no es json').toJson(), const CatalogStyle().toJson());
      expect(CatalogStyle.decode('{"itemsPerPage": 5}').itemsPerPage, 4);
    });

    test('el pie "Hecho con Stockealo" va siempre en el plan gratis', () {
      expect(const CatalogStyle().showBranding, isTrue);
      // Quitarlo es de Pro: sin Pro el estilo que se usa lo vuelve a poner
      expect(CatalogStyle.decode('{"showBranding": false}').effective(pro: false).showBranding, isTrue);
    });

    test('la clave es por negocio', () {
      expect(CatalogStyle.settingsKey('b1'), isNot(CatalogStyle.settingsKey('b2')));
    });
  });

  group('selectProducts', () {
    final products = [
      _product('a', category: 'Bebidas', photo: 'https://x/a.jpg'),
      _product('b', category: 'Bebidas'),
      _product('c', category: 'Snacks', photo: 'https://x/c.jpg'),
      _product('d', category: 'Snacks', stock: 0),
    ];
    List<String> ids(CatalogStyle style, {String? category}) =>
        CatalogPdfService.selectProducts(products, style, categoryFilter: category).map((p) => p.id).toList();

    test('sin filtros entran todos los que tienen stock', () {
      expect(ids(const CatalogStyle()), ['a', 'b', 'c']);
      expect(ids(const CatalogStyle(), category: 'Todas'), ['a', 'b', 'c']);
    });

    test('filtra por categoría sin importar mayúsculas', () {
      expect(ids(const CatalogStyle(), category: 'bebidas'), ['a', 'b']);
    });

    test('los elegidos a mano mandan sobre la categoría', () {
      expect(ids(const CatalogStyle(selectedProductIds: {'c', 'd'}), category: 'Bebidas'), ['c']);
    });

    test('solo con foto', () {
      expect(ids(const CatalogStyle(onlyWithPhoto: true)), ['a', 'c']);
    });
  });

  test('arma el PDF con fondo oscuro, contacto y todas las densidades', () async {
    final business = Business(id: 'b1', userId: 'u1', name: 'Tienda Olinda · Ñandú', color: '#BE185D', createdAt: DateTime(2026));
    final products = [
      for (var i = 0; i < 7; i++)
        _product('$i', description: i.isEven ? 'Una descripción larga para ver que no se sale de la tarjeta' : null),
    ];
    for (final perPage in [1, 2, 4, 6]) {
      final file = await CatalogPdfService.instance.generateCatalogPdf(
        business: business,
        products: products,
        style: CatalogStyle(
          itemsPerPage: perPage,
          darkBackground: perPage.isEven,
          whatsapp: '+57 300 000 0000',
          address: 'Calle 1 # 2-3',
          hours: 'Lun a Sáb',
          social: '@olinda',
          showExactStock: true,
          showCode: true,
        ),
      );
      final bytes = await file.readAsBytes();
      expect(bytes.length, greaterThan(1000));
      // Lleva la letra Inter incrustada (no la Helvetica sin tildes ni símbolos)
      expect(String.fromCharCodes(bytes).contains('Inter'), isTrue);
      await file.delete();
    }
  });
}
