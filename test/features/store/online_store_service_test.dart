import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/store/data/online_store_service.dart';
import 'package:stockealo/store_web/store_page.dart';

void main() {
  group('dirección de la tienda', () {
    test('se sugiere desde el nombre del negocio, sin tildes ni símbolos', () {
      expect(OnlineStoreService.suggestSlug('Tienda Doña Ána'), 'tienda-dona-ana');
      expect(OnlineStoreService.suggestSlug('  Miscelánea #1 · El Sol  '), 'miscelanea-1-el-sol');
      expect(OnlineStoreService.suggestSlug('A'), 'mi-tienda');
      expect(OnlineStoreService.suggestSlug('x' * 60).length, lessThanOrEqualTo(40));
    });

    test('valida las mismas reglas que el servidor', () {
      expect(OnlineStoreService.isValidSlug('tienda-dona-ana'), isTrue);
      expect(OnlineStoreService.isValidSlug('ab'), isFalse);
      expect(OnlineStoreService.isValidSlug('-tienda'), isFalse);
      expect(OnlineStoreService.isValidSlug('Tienda'), isFalse);
      expect(OnlineStoreService.isValidSlug('admin'), isFalse);
    });

    test('se lee de /tienda/<slug> o de ?t=<slug>', () {
      expect(slugFromUri(Uri.parse('https://stockealo.online/tienda/dona-ana')), 'dona-ana');
      expect(slugFromUri(Uri.parse('https://stockealo.online/tienda/?t=Dona-Ana')), 'dona-ana');
      expect(slugFromUri(Uri.parse('https://stockealo.online/tienda/')), isNull);
    });
  });

  test('la tienda pública se lee del servidor', () {
    final store = PublicStore.fromJson({
      'slug': 'dona-ana',
      'whatsapp': '573001234567',
      'welcome': 'Domicilios gratis',
      'business': {'name': 'Doña Ana', 'color': '#1D5FA8', 'currency': 'COP'},
      'products': [
        {'id': '1', 'name': 'Arroz', 'category': 'Granos', 'price': 5000, 'image_url': null, 'stock': null},
        {'id': '2', 'name': 'Café', 'category': 'Bebidas', 'price': 12000, 'image_url': 'https://x/y.jpg', 'stock': 3},
        {'id': '3', 'name': 'Fríjol', 'category': 'Granos', 'price': 7000},
      ],
    });
    expect(store.businessName, 'Doña Ana');
    expect(store.products, hasLength(3));
    expect(store.products[1].stock, 3);
    expect(store.categories, ['Granos', 'Bebidas']);
  });

  test('el pedido de WhatsApp lleva productos, total, nombre y nota', () {
    const arroz = StoreProduct(id: '1', name: 'Arroz', category: '', price: 5000);
    const cafe = StoreProduct(id: '2', name: 'Café', category: '', price: 12000);
    final text = OnlineStoreService.orderMessage(
      businessName: 'Doña Ana',
      lines: const [CartLine(arroz, 2), CartLine(cafe, 1)],
      currency: 'COP',
      customerName: 'Luis',
      note: 'Calle 5 #2-10',
    );
    expect(text, startsWith('Hola Doña Ana'));
    expect(text, contains('2 × Arroz'));
    expect(text, contains('10.000'));
    expect(text, contains('Total: \$22.000'));
    expect(text, contains('A nombre de: Luis'));
    expect(text, contains('Nota: Calle 5 #2-10'));
  });

  test('cada error del servidor tiene su mensaje', () {
    expect(OnlineStoreService.errorMessage('slug_taken'), contains('ya la usa'));
    expect(OnlineStoreService.errorMessage('pro_required'), contains('Stockealo Pro'));
    expect(OnlineStoreService.errorMessage('not_allowed'), contains('dueño'));
    expect(OnlineStoreService.errorMessage('otra cosa'), contains('Inténtalo'));
  });
}
