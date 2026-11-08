import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/products/data/product_image_service.dart';

void main() {
  test('toma el enlace aunque venga dentro de un texto compartido', () {
    expect(
      ProductImageService.normalizeLink('Mira esta blusa https://co.shein.com/blusa-p-123.html?src=app'),
      'https://co.shein.com/blusa-p-123.html?src=app',
    );
    expect(ProductImageService.normalizeLink('  https://temu.com/x  '), 'https://temu.com/x');
    expect(ProductImageService.normalizeLink('shein.com/blusa'), isNull);
    expect(ProductImageService.normalizeLink('ftp://algo.com/foto.jpg'), isNull);
  });

  test('reconoce el tipo real de la imagen por sus primeros bytes', () {
    Uint8List head(List<int> b) => Uint8List.fromList([...b, ...List.filled(16, 0)]);
    expect(ProductImageService.imageTypeOf(head([0xFF, 0xD8, 0xFF])), 'image/jpeg');
    expect(ProductImageService.imageTypeOf(head([0x89, 0x50, 0x4E, 0x47])), 'image/png');
    expect(ProductImageService.imageTypeOf(head([0x47, 0x49, 0x46])), 'image/gif');
    expect(
      ProductImageService.imageTypeOf(head([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])),
      'image/webp',
    );
    expect(ProductImageService.imageTypeOf(head('<html>'.codeUnits)), isNull);
  });

  test('cada error del servidor tiene un mensaje con salida', () {
    expect(ProductImageService.errorMessage('no_image'), contains('súbela desde la galería'));
    expect(ProductImageService.errorMessage('fetch_failed'), contains('pégala'));
    expect(ProductImageService.errorMessage('blocked'), contains('pégala'));
    expect(ProductImageService.errorMessage('daily_limit'), contains('Mañana'));
    expect(ProductImageService.errorMessage('otra'), contains('Inténtalo de nuevo'));
    final shein = ProductImageService.errorMessage('store_blocked', store: 'Shein');
    expect(shein, startsWith('Shein no deja'));
    expect(shein, contains('Windows + Shift + S'));
    expect(ProductImageService.errorMessage('store_blocked'), startsWith('Esa tienda'));
  });
}
