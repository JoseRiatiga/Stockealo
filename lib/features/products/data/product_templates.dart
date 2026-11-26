import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../store/data/online_store_service.dart';
import 'product_repository.dart';

/// Variantes listas para un tipo de negocio: cómo se llama la primera lista, sus
/// valores y cómo se llama la segunda (Color o Sabor)
class VariantPreset {
  final String label;
  final String attributeName;
  final List<String> values;
  final String secondName;

  const VariantPreset({required this.label, required this.attributeName, required this.values, this.secondName = 'Color'});

  static const clothes = VariantPreset(label: 'Ropa', attributeName: 'Talla', values: ['S', 'M', 'L', 'XL']);
  static const shoes = VariantPreset(label: 'Calzado', attributeName: 'Talla', values: ['36', '37', '38', '39', '40']);
  static const bottles = VariantPreset(label: 'Presentación', attributeName: 'Presentación', values: ['375 ml', '750 ml', '1 L', '1,75 L']);
  static const nicotine = VariantPreset(
    label: 'Nicotina · sabor',
    attributeName: 'Nicotina',
    values: ['0 mg', '20 mg', '50 mg'],
    secondName: 'Sabor',
  );

  /// Pantalón (0.18.7): las tallas van por número y cambian según para quién es.
  /// El botón «Pantalón» pregunta cuál.
  static const pantsMen = VariantPreset(label: 'Hombre', attributeName: 'Talla', values: ['28', '30', '32', '34', '36', '38']);
  static const pantsWomen =
      VariantPreset(label: 'Dama', attributeName: 'Talla', values: ['4', '6', '8', '10', '12', '14', '16']);
  static const pantsKids =
      VariantPreset(label: 'Niños', attributeName: 'Talla', values: ['2', '4', '6', '8', '10', '12', '14', '16']);
  static const pants = [pantsMen, pantsWomen, pantsKids];

  /// Los botones rápidos del editor de variantes, para cualquier negocio
  /// («Pantalón» va aparte, después de «Ropa», porque pregunta antes)
  static const all = [clothes, shoes, bottles, nicotine];
}

/// Dónde va una talla nueva (0.18.7): si es conocida, en su lugar y no al final.
/// Se olvidó la S y se agrega después de M y L → queda antes de la M. Con números
/// igual (el 30 entre el 28 y el 32). Si la lista mezcla cosas que no se conocen
/// («Única», «32 largo») o la talla nueva no se conoce, va al final como antes.
abstract final class SizeOrder {
  /// Tallas en letra, de la más pequeña a la más grande
  static const letters = ['XXS', 'XS', 'S', 'M', 'L', 'XL', 'XXL', '3XL', '4XL', '5XL'];

  static const _aliases = {'XXXL': '3XL', 'XXXXL': '4XL', '2XL': 'XXL', '2XS': 'XXS'};

  /// Puesto de una talla en letra, o null si no lo es
  static int? letterRank(String size) {
    final s = size.trim().toUpperCase();
    final i = letters.indexOf(_aliases[s] ?? s);
    return i < 0 ? null : i;
  }

  /// Valor de una talla en número («32», «7,5»), o null si no lo es
  static double? numberValue(String size) {
    final s = size.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) return null;
    return double.tryParse(s);
  }

  /// Posición donde se inserta [size] en [current]: antes de la primera talla más
  /// grande. Solo si todas las de la lista son del mismo tipo que la nueva (letras
  /// o números); si no, al final.
  static int insertIndex(List<String> current, String size) {
    final letter = letterRank(size);
    if (letter != null) {
      final ranks = current.map(letterRank).toList();
      if (ranks.any((r) => r == null)) return current.length;
      final i = ranks.indexWhere((r) => r! > letter);
      return i < 0 ? current.length : i;
    }
    final number = numberValue(size);
    if (number != null) {
      final values = current.map(numberValue).toList();
      if (values.any((v) => v == null)) return current.length;
      final i = values.indexWhere((v) => v! > number);
      return i < 0 ? current.length : i;
    }
    return current.length;
  }
}

/// Plantilla de productos de un tipo de negocio (0.16.0, fase 2a, punto 16): carga
/// categorías sugeridas (se pueden quitar), dice qué variantes usar, si la tienda pide
/// el aviso +18 y qué plantilla de tienda le queda. No crea productos.
class ProductTemplate {
  final String code;
  final String label;
  final IconData icon;

  /// Lo que carga, en una línea
  final String summary;
  final List<String> categories;
  final VariantPreset? preset;

  /// La tienda en línea pregunta «¿Tienes 18 años o más?»
  final bool adult;
  final String storeTemplate;

  /// Usa la marca del producto (la tienda filtra por marca)
  final bool usesBrand;

  /// Hashtags sugeridos para Instagram (fase 3)
  final List<String> hashtags;

  const ProductTemplate({
    required this.code,
    required this.label,
    required this.icon,
    required this.summary,
    required this.categories,
    required this.storeTemplate,
    this.preset,
    this.adult = false,
    this.usesBrand = false,
    this.hashtags = const ['#Domicilios'],
  });

  static const licorera = ProductTemplate(
    code: 'licorera',
    label: 'Licorera',
    icon: Icons.liquor_outlined,
    summary: 'Aguardiente, ron, whisky, cerveza… · presentación en ml · aviso +18 · tienda Mercado',
    categories: ['Aguardiente', 'Ron', 'Whisky', 'Vodka', 'Tequila', 'Cerveza', 'Vinos', 'Mezcladores', 'Snacks', 'Hielo'],
    preset: VariantPreset.bottles,
    adult: true,
    storeTemplate: StoreTemplate.market,
    usesBrand: true,
    hashtags: ['#Licorera', '#Licores', '#Domicilios'],
  );

  static const vapers = ProductTemplate(
    code: 'vapers',
    label: 'Vapers',
    icon: Icons.air_outlined,
    summary: 'Desechables, pods, líquidos, accesorios · marca, nicotina y sabor · aviso +18 · tienda Boutique',
    categories: ['Desechables', 'Pods', 'Líquidos', 'Resistencias', 'Kits y baterías', 'Accesorios'],
    preset: VariantPreset.nicotine,
    adult: true,
    storeTemplate: StoreTemplate.boutique,
    usesBrand: true,
    hashtags: ['#Vape', '#Vapers', '#Pods'],
  );

  static const drogueria = ProductTemplate(
    code: 'drogueria',
    label: 'Droguería',
    icon: Icons.local_pharmacy_outlined,
    summary: 'Medicamentos, vitaminas, cuidado personal… · tienda Mercado',
    categories: ['Medicamentos', 'Vitaminas', 'Cuidado personal', 'Bebés', 'Primeros auxilios', 'Higiene', 'Dermocosmética'],
    storeTemplate: StoreTemplate.market,
    usesBrand: true,
    hashtags: ['#Droguería', '#Farmacia', '#Domicilios'],
  );

  static const ropa = ProductTemplate(
    code: 'ropa',
    label: 'Ropa y calzado',
    icon: Icons.checkroom_outlined,
    summary: 'Camisetas, pantalones, calzado… · tallas y colores · tienda Moda',
    categories: ['Camisetas', 'Pantalones', 'Vestidos', 'Chaquetas', 'Ropa interior', 'Calzado', 'Accesorios'],
    preset: VariantPreset.clothes,
    storeTemplate: StoreTemplate.fashion,
    hashtags: ['#Moda', '#Ropa', '#Outfit'],
  );

  static const comidas = ProductTemplate(
    code: 'comidas',
    label: 'Comidas y panadería',
    icon: Icons.restaurant_menu_outlined,
    summary: 'Desayunos, almuerzos, panes, postres… · descripción del plato · tienda Menú',
    categories: ['Desayunos', 'Almuerzos', 'Panes', 'Postres', 'Bebidas', 'Adicionales'],
    storeTemplate: StoreTemplate.menu,
    hashtags: ['#Comida', '#Antojos', '#Domicilios'],
  );

  static const barrio = ProductTemplate(
    code: 'barrio',
    label: 'Tienda de barrio o miscelánea',
    icon: Icons.storefront_outlined,
    summary: 'Granos, lácteos, aseo, bebidas, snacks… · tienda Mercado',
    categories: ['Granos', 'Lácteos y huevos', 'Aseo', 'Bebidas', 'Snacks y dulces', 'Enlatados', 'Panadería', 'Carnes frías'],
    storeTemplate: StoreTemplate.market,
    hashtags: ['#TiendaDeBarrio', '#Mercado', '#Domicilios'],
  );

  static const all = [licorera, vapers, drogueria, ropa, comidas, barrio];

  static ProductTemplate? of(String? code) => all.where((t) => t.code == code).firstOrNull;

  /// Categorías de la tienda de barrio que se vencen pronto (0.16.3)
  static const perishables = ['Lácteos y huevos', 'Panadería', 'Carnes frías'];

  /// Si un producto nuevo viene con «Controla vencimiento por lote» encendido: en la
  /// droguería siempre; en la tienda de barrio solo en lo perecedero (no en bebidas ni aseo)
  bool expiryByDefault(String? category) {
    if (this == drogueria) return true;
    if (this != barrio || category == null) return false;
    final c = category.trim().toLowerCase();
    return perishables.any((p) => p.toLowerCase() == c);
  }

  /// La que le queda según «¿Para qué usarás Stockealo?»; null = ninguna en especial
  static ProductTemplate? suggestedFor(String? businessKind) => switch (businessKind) {
        'licores' || 'vinos' || 'cerveza' || 'bar' => licorera,
        'vapers' => vapers,
        'drogueria' || 'medicamentos' => drogueria,
        'ropa' || 'bebes' || 'marroquineria' || 'zapatos' => ropa,
        'comida' || 'casera' || 'sopas' || 'cafe' || 'desayunos' || 'panaderia' || 'postres' || 'heladeria' || 'pizza' ||
        'comida_rapida' || 'fastfood' || 'para_llevar' || 'asados' || 'asiatica' =>
          comidas,
        'tienda' || 'miscelanea' || 'supermercado' || 'canasta' || 'fruver' || 'huevos' => barrio,
        _ => null,
      };

  // ---------------------------------------------------------------------------

  static String _key(String businessId) => 'product_template_$businessId';
  static String _dismissKey(String businessId) => 'product_template_hidden_$businessId';

  /// La plantilla que ya cargó el negocio en este celular; null = ninguna
  static Future<ProductTemplate?> applied(String businessId) async => of(await AppDatabase.instance.getSetting(_key(businessId)));

  /// La tarjeta de Productos se cerró sin cargar nada
  static Future<bool> dismissed(String businessId) async => await AppDatabase.instance.getSetting(_dismissKey(businessId)) == '1';
  static Future<void> dismiss(String businessId) => AppDatabase.instance.setSetting(_dismissKey(businessId), '1');

  /// Agrega las [categories] que falten (sin repetir, sin importar mayúsculas ni tildes)
  /// y deja anotado que se cargó. Devuelve cuántas categorías nuevas quedaron.
  Future<int> apply(String businessId, {required List<String> categories, ProductRepository? repository}) async {
    final repo = repository ?? ProductRepository();
    final have = {for (final c in await repo.getCategories(businessId)) plain(c.name)};
    var added = 0;
    for (final name in categories) {
      if (name.trim().isEmpty || !have.add(plain(name))) continue;
      await repo.addCategory(name, businessId);
      added++;
    }
    await AppDatabase.instance.setSetting(_key(businessId), code);
    return added;
  }

  static String plain(String s) {
    const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
    return s.trim().toLowerCase().split('').map((ch) => accents[ch] ?? ch).join().replaceAll(RegExp(r'\s+'), ' ');
  }
}
