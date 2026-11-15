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

  /// Los botones rápidos del editor de variantes, para cualquier negocio
  static const all = [clothes, shoes, bottles, nicotine];
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
  );

  static const drogueria = ProductTemplate(
    code: 'drogueria',
    label: 'Droguería',
    icon: Icons.local_pharmacy_outlined,
    summary: 'Medicamentos, vitaminas, cuidado personal… · tienda Mercado',
    categories: ['Medicamentos', 'Vitaminas', 'Cuidado personal', 'Bebés', 'Primeros auxilios', 'Higiene', 'Dermocosmética'],
    storeTemplate: StoreTemplate.market,
    usesBrand: true,
  );

  static const ropa = ProductTemplate(
    code: 'ropa',
    label: 'Ropa y calzado',
    icon: Icons.checkroom_outlined,
    summary: 'Camisetas, pantalones, calzado… · tallas y colores · tienda Moda',
    categories: ['Camisetas', 'Pantalones', 'Vestidos', 'Chaquetas', 'Ropa interior', 'Calzado', 'Accesorios'],
    preset: VariantPreset.clothes,
    storeTemplate: StoreTemplate.fashion,
  );

  static const comidas = ProductTemplate(
    code: 'comidas',
    label: 'Comidas y panadería',
    icon: Icons.restaurant_menu_outlined,
    summary: 'Desayunos, almuerzos, panes, postres… · descripción del plato · tienda Menú',
    categories: ['Desayunos', 'Almuerzos', 'Panes', 'Postres', 'Bebidas', 'Adicionales'],
    storeTemplate: StoreTemplate.menu,
  );

  static const barrio = ProductTemplate(
    code: 'barrio',
    label: 'Tienda de barrio o miscelánea',
    icon: Icons.storefront_outlined,
    summary: 'Granos, lácteos, aseo, bebidas, snacks… · tienda Mercado',
    categories: ['Granos', 'Lácteos y huevos', 'Aseo', 'Bebidas', 'Snacks y dulces', 'Enlatados', 'Panadería', 'Carnes frías'],
    storeTemplate: StoreTemplate.market,
  );

  static const all = [licorera, vapers, drogueria, ropa, comidas, barrio];

  static ProductTemplate? of(String? code) => all.where((t) => t.code == code).firstOrNull;

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
