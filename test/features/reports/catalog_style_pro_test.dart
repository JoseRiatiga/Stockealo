import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_tokens.dart';
import 'package:stockealo/features/reports/models/catalog_style.dart';

void main() {
  final freeHex = AppPalette.toHex(AppPalette.businessColors['azul']!);
  final proHex = AppPalette.toHex(AppPalette.businessColors['morado']!);

  group('paleta', () {
    test('la corta es parte de la completa y es más pequeña', () {
      final free = CatalogStyle.paletteHexes(pro: false);
      final full = CatalogStyle.paletteHexes(pro: true);
      expect(full, containsAll(free));
      expect(free.length, lessThan(full.length));
      expect(full.length, AppPalette.businessColors.length);
    });
  });

  group('opciones Pro', () {
    test('el estilo por defecto es gratis', () {
      expect(const CatalogStyle().usesProFeatures, isFalse);
      expect(CatalogStyle(colorHex: freeHex).usesProFeatures, isFalse);
    });

    test('plantillas extra, fondo oscuro, color de la paleta completa y quitar el pie son Pro', () {
      expect(const CatalogStyle(template: 'vitrina').usesProFeatures, isTrue);
      expect(const CatalogStyle(template: 'lista').usesProFeatures, isTrue);
      expect(const CatalogStyle(template: 'promo').usesProFeatures, isTrue);
      expect(const CatalogStyle(darkBackground: true).usesProFeatures, isTrue);
      expect(const CatalogStyle(showBranding: false).usesProFeatures, isTrue);
      expect(CatalogStyle(colorHex: proHex).usesProFeatures, isTrue);
    });

    test('sin Pro vuelve a lo gratis y conserva lo demás', () {
      final chosen = CatalogStyle(
        template: 'promo',
        darkBackground: true,
        showBranding: false,
        colorHex: proHex,
        title: 'Ofertas',
        itemsPerPage: 2,
      );
      final free = chosen.effective(pro: false);
      expect(free.template, 'clasica');
      expect(free.darkBackground, isFalse);
      expect(free.showBranding, isTrue);
      expect(free.colorHex, isNull);
      expect(free.title, 'Ofertas');
      expect(free.itemsPerPage, 2);
      expect(free.usesProFeatures, isFalse);
    });

    test('sin Pro un color de la paleta corta se respeta', () {
      final free = CatalogStyle(template: 'vitrina', colorHex: freeHex).effective(pro: false);
      expect(free.colorHex, freeHex);
    });

    test('con Pro el estilo queda tal cual', () {
      final chosen = CatalogStyle(template: 'lista', darkBackground: true, showBranding: false, colorHex: proHex);
      expect(identical(chosen.effective(pro: true), chosen), isTrue);
    });
  });

  group('nombres de las opciones Pro', () {
    test('explica qué opciones Pro usa el estilo', () {
      final names = CatalogStyle(template: 'vitrina', darkBackground: true, colorHex: proHex).proFeatureNames;
      expect(names, ['la plantilla Vitrina', 'un color de la paleta completa', 'fondo oscuro']);
      expect(const CatalogStyle(showBranding: false).proFeatureNames, ['el catálogo sin el pie de Stockealo']);
      expect(const CatalogStyle().proFeatureNames, isEmpty);
    });
  });

  group('guardado', () {
    test('la plantilla y el pie se guardan y se leen', () {
      const style = CatalogStyle(template: 'vitrina', showBranding: false);
      final back = CatalogStyle.decode(style.encode());
      expect(back.template, 'vitrina');
      expect(back.showBranding, isFalse);
    });

    test('una plantilla desconocida vuelve a la clásica', () {
      expect(CatalogStyle.fromJson({'template': 'otra'}).template, 'clasica');
    });

    test('copyWith cambia el pie', () {
      expect(const CatalogStyle().copyWith(showBranding: false).showBranding, isFalse);
      expect(const CatalogStyle(showBranding: false).copyWith(title: 'x').showBranding, isFalse);
    });
  });
}
