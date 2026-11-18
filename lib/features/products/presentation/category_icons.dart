import 'package:flutter/material.dart';

/// Íconos de categoría (0.16.8, #28, decisión A1 a): dibujos de línea como el resto de
/// la app, en el color del negocio. La clave es lo que se guarda en `categories.icon`
/// y en la tienda pública; una clave desconocida se muestra como [fallback].
class CategoryIcon {
  final String key;
  final String label;
  final IconData icon;

  /// Palabras del nombre de la categoría que sugieren este ícono (sin tildes)
  final List<String> words;

  const CategoryIcon(this.key, this.label, this.icon, this.words);

  static const fallback = Icons.sell_outlined;

  /// «Todas» en los filtros
  static const all = Icons.apps_outlined;

  /// El dibujo de esa clave; null si no hay clave
  static IconData? of(String? key) {
    if (key == null || key.isEmpty) return null;
    return kCategoryIcons.where((c) => c.key == key).firstOrNull?.icon ?? fallback;
  }

  /// Sugerencia por el nombre («Bebidas» → vaso); null si ninguna palabra coincide
  static String? suggest(String name) {
    final words = _plain(name).split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 1).toList();
    for (final c in kCategoryIcons) {
      for (final w in words) {
        if (c.words.any((k) => w == k || (k.length >= 4 && w.startsWith(k)))) return c.key;
      }
    }
    return null;
  }

  static String _plain(String s) {
    const from = 'áéíóúüñ';
    const to = 'aeiouun';
    var out = s.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      out = out.replaceAll(from[i], to[i]);
    }
    return out;
  }
}

const List<CategoryIcon> kCategoryIcons = [
  CategoryIcon('drink', 'Bebidas', Icons.local_drink_outlined, ['bebida', 'gaseosa', 'jugo', 'agua', 'refresco', 'soda']),
  CategoryIcon('liquor', 'Licores', Icons.liquor_outlined, ['licor', 'trago', 'ron', 'aguardiente', 'whisky', 'vodka', 'tequila']),
  CategoryIcon('beer', 'Cerveza', Icons.sports_bar_outlined, ['cerveza', 'pola', 'birra']),
  CategoryIcon('wine', 'Vinos', Icons.wine_bar_outlined, ['vino', 'vinos']),
  CategoryIcon('coffee', 'Café', Icons.local_cafe_outlined, ['cafe', 'tinto', 'te', 'aromatica']),
  CategoryIcon('snack', 'Mecato', Icons.cookie_outlined, ['mecato', 'snack', 'paquete', 'galleta', 'dulce', 'golosina', 'confite', 'chocolate']),
  CategoryIcon('bakery', 'Panadería', Icons.bakery_dining_outlined, ['pan', 'panaderia', 'arepa', 'pasteleria']),
  CategoryIcon('cake', 'Postres', Icons.cake_outlined, ['postre', 'torta', 'ponque']),
  CategoryIcon('icecream', 'Helados', Icons.icecream_outlined, ['helado', 'paleta']),
  CategoryIcon('food', 'Comidas', Icons.restaurant_outlined, ['comida', 'almuerzo', 'plato', 'menu', 'corriente']),
  CategoryIcon('fastfood', 'Comida rápida', Icons.lunch_dining_outlined, ['hamburguesa', 'perro', 'rapida', 'sandwich']),
  CategoryIcon('pizza', 'Pizza', Icons.local_pizza_outlined, ['pizza']),
  CategoryIcon('meat', 'Carnes', Icons.kebab_dining_outlined, ['carne', 'pollo', 'cerdo', 'res', 'carnes', 'embutido']),
  CategoryIcon('fish', 'Pescados', Icons.set_meal_outlined, ['pescado', 'mariscos', 'atun']),
  CategoryIcon('dairy', 'Lácteos y huevos', Icons.egg_alt_outlined, ['lacteo', 'leche', 'queso', 'huevo', 'yogur', 'yogurt']),
  CategoryIcon('produce', 'Frutas y verduras', Icons.eco_outlined, ['fruta', 'verdura', 'fruver', 'hortaliza', 'legumbre']),
  CategoryIcon('grocery', 'Abarrotes', Icons.shopping_basket_outlined, ['abarrote', 'grano', 'arroz', 'aceite', 'azucar', 'mercado', 'despensa', 'enlatado', 'pasta']),
  CategoryIcon('cleaning', 'Aseo', Icons.cleaning_services_outlined, ['aseo', 'limpieza', 'detergente', 'jabon', 'desinfectante']),
  CategoryIcon('personal', 'Cuidado personal', Icons.soap_outlined, ['personal', 'higiene', 'shampoo', 'champu', 'desodorante', 'crema']),
  CategoryIcon('medicine', 'Medicamentos', Icons.medication_outlined, ['medicamento', 'drogueria', 'farmacia', 'pastilla', 'remedio', 'analgesico']),
  CategoryIcon('health', 'Salud', Icons.health_and_safety_outlined, ['salud', 'vitamina', 'suplemento', 'botiquin']),
  CategoryIcon('baby', 'Bebés', Icons.child_friendly_outlined, ['bebe', 'panal', 'infantil']),
  CategoryIcon('pet', 'Mascotas', Icons.pets_outlined, ['mascota', 'perro', 'gato', 'concentrado', 'veterinaria']),
  CategoryIcon('clothes', 'Ropa', Icons.checkroom_outlined, ['ropa', 'camisa', 'camiseta', 'pantalon', 'jean', 'vestido', 'blusa', 'prenda', 'buzo', 'chaqueta']),
  CategoryIcon('shoe', 'Calzado', Icons.hiking_outlined, ['calzado', 'zapato', 'tenis', 'bota', 'sandalia', 'chancla']),
  CategoryIcon('bag', 'Bolsos', Icons.shopping_bag_outlined, ['bolso', 'cartera', 'maleta', 'morral', 'mochila']),
  CategoryIcon('accessory', 'Accesorios', Icons.watch_outlined, ['accesorio', 'reloj', 'gafa', 'cinturon', 'gorra']),
  CategoryIcon('jewelry', 'Joyería', Icons.diamond_outlined, ['joya', 'joyeria', 'bisuteria', 'anillo', 'collar', 'arete']),
  CategoryIcon('beauty', 'Belleza', Icons.face_retouching_natural_outlined, ['belleza', 'maquillaje', 'cosmetico', 'perfume', 'una', 'unas']),
  CategoryIcon('vape', 'Vapers', Icons.air_outlined, ['vape', 'vaper', 'pod', 'pods', 'liquido', 'cigarrillo', 'tabaco']),
  CategoryIcon('phone', 'Celulares', Icons.smartphone_outlined, ['celular', 'telefono', 'movil', 'cargador', 'cable', 'forro']),
  CategoryIcon('tech', 'Tecnología', Icons.devices_outlined, ['tecnologia', 'computador', 'electronica', 'audifono', 'parlante', 'tecno']),
  CategoryIcon('tool', 'Herramientas', Icons.handyman_outlined, ['herramienta', 'ferreteria', 'tornillo', 'clavo']),
  CategoryIcon('paint', 'Pinturas', Icons.format_paint_outlined, ['pintura', 'brocha', 'rodillo']),
  CategoryIcon('electric', 'Eléctricos', Icons.electrical_services_outlined, ['electrico', 'bombillo', 'luz', 'iluminacion']),
  CategoryIcon('home', 'Hogar', Icons.chair_outlined, ['hogar', 'casa', 'mueble', 'cocina', 'decoracion']),
  CategoryIcon('stationery', 'Papelería', Icons.edit_outlined, ['papeleria', 'cuaderno', 'lapiz', 'utiles', 'escolar', 'oficina']),
  CategoryIcon('toy', 'Juguetes', Icons.toys_outlined, ['juguete', 'juego', 'nino', 'ninos']),
  CategoryIcon('sport', 'Deportes', Icons.sports_soccer_outlined, ['deporte', 'balon', 'gimnasio', 'fitness']),
  CategoryIcon('gift', 'Regalos', Icons.redeem_outlined, ['regalo', 'detalle', 'sorpresa', 'flor', 'flores']),
  CategoryIcon('car', 'Vehículos', Icons.directions_car_outlined, ['carro', 'moto', 'repuesto', 'llanta', 'lubricante', 'aceite_motor']),
  CategoryIcon('farm', 'Agro', Icons.agriculture_outlined, ['agro', 'semilla', 'abono', 'fertilizante', 'campo']),
  CategoryIcon('service', 'Servicios', Icons.room_service_outlined, ['servicio', 'servicios', 'lavado', 'corte']),
  CategoryIcon('offer', 'Ofertas', Icons.local_offer_outlined, ['oferta', 'promocion', 'descuento', 'combo']),
  CategoryIcon('box', 'Varios', Icons.inventory_2_outlined, ['varios', 'general', 'otros', 'otro']),
];
