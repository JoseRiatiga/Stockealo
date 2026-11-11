import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/business.dart';
import '../../products/presentation/widgets/product_image_view.dart';

/// Ícono que identifica al negocio cuando no tiene logo. En la cuadrícula solo se
/// ve el ícono; el nombre sale al mantener presionado, en los lectores de pantalla
/// y sirve (junto con [tags]) para el buscador.
class BusinessKind {
  final String key;
  final String label;
  final IconData icon;
  final String group;

  /// Otras palabras con las que se puede buscar
  final String tags;

  const BusinessKind(this.key, this.label, this.icon, this.group, [this.tags = '']);
}

const _tiendas = 'Tiendas';
const _comida = 'Comida';
const _moda = 'Moda y belleza';
const _salud = 'Salud';
const _hogar = 'Hogar y ferretería';
const _tecno = 'Tecnología';
const _motor = 'Transporte';
const _agro = 'Agro y campo';
const _oficina = 'Educación y oficina';
const _ocio = 'Ocio y eventos';
const _viajes = 'Viajes';
const _servicios = 'Servicios';

/// Íconos que se pueden elegir para un negocio, por rubro. La clave es lo que se
/// guarda en `businesses.icon` (las claves de antes de la 0.9.0 no cambian); un
/// valor desconocido se muestra como tienda.
const List<BusinessKind> kBusinessKinds = [
  // Tiendas
  BusinessKind('tienda', 'Tienda', Icons.storefront_outlined, _tiendas, 'barrio abarrotes'),
  BusinessKind('miscelanea', 'Miscelánea', Icons.local_convenience_store_outlined, _tiendas, 'minimercado'),
  BusinessKind('supermercado', 'Supermercado', Icons.shopping_cart_outlined, _tiendas, 'mercado'),
  BusinessKind('canasta', 'Plaza de mercado', Icons.shopping_basket_outlined, _tiendas, 'canasta'),
  BusinessKind('bolsa', 'Almacén', Icons.shopping_bag_outlined, _tiendas, 'boutique'),
  BusinessKind('local', 'Local comercial', Icons.store_mall_directory_outlined, _tiendas, 'centro comercial'),
  BusinessKind('mayorista', 'Mayorista', Icons.inventory_2_outlined, _tiendas, 'distribuidora bodega cajas'),
  BusinessKind('bodega', 'Bodega', Icons.warehouse_outlined, _tiendas, 'almacenamiento'),
  BusinessKind('ofertas', 'Ofertas', Icons.local_offer_outlined, _tiendas, 'descuentos precios'),
  BusinessKind('regalos', 'Regalos', Icons.redeem_outlined, _tiendas, 'detalles sorpresas'),
  BusinessKind('domicilios', 'Domicilios', Icons.delivery_dining_outlined, _tiendas, 'envios entregas'),
  BusinessKind('caja', 'Punto de venta', Icons.point_of_sale_outlined, _tiendas, 'caja registradora'),
  BusinessKind('tienda_online', 'Tienda en línea', Icons.language_outlined, _tiendas, 'internet web virtual'),
  // Comida
  BusinessKind('comida', 'Restaurante', Icons.restaurant_outlined, _comida, 'almuerzos corrientazo'),
  BusinessKind('casera', 'Comida casera', Icons.dinner_dining_outlined, _comida, 'menu del dia pasta'),
  BusinessKind('sopas', 'Sopas', Icons.soup_kitchen_outlined, _comida, 'cocina caldos'),
  BusinessKind('cafe', 'Cafetería', Icons.local_cafe_outlined, _comida, 'tinto cafe'),
  BusinessKind('desayunos', 'Desayunos', Icons.brunch_dining_outlined, _comida, 'brunch'),
  BusinessKind('panaderia', 'Panadería', Icons.bakery_dining_outlined, _comida, 'pan pasteleria'),
  BusinessKind('postres', 'Postres', Icons.cake_outlined, _comida, 'tortas reposteria'),
  BusinessKind('heladeria', 'Heladería', Icons.icecream_outlined, _comida, 'helados'),
  BusinessKind('pizza', 'Pizzería', Icons.local_pizza_outlined, _comida, 'pizza'),
  BusinessKind('comida_rapida', 'Hamburguesas', Icons.lunch_dining_outlined, _comida, 'comida rapida'),
  BusinessKind('fastfood', 'Comida rápida', Icons.fastfood_outlined, _comida, 'perros papas'),
  BusinessKind('para_llevar', 'Para llevar', Icons.takeout_dining_outlined, _comida, 'domicilio empaques'),
  BusinessKind('asados', 'Asados', Icons.kebab_dining_outlined, _comida, 'carne parrilla carniceria'),
  BusinessKind('pescaderia', 'Pescadería', Icons.set_meal_outlined, _comida, 'pescado mariscos'),
  BusinessKind('asiatica', 'Comida asiática', Icons.ramen_dining_outlined, _comida, 'sushi ramen china'),
  BusinessKind('huevos', 'Huevos y lácteos', Icons.egg_alt_outlined, _comida, 'leche queso'),
  BusinessKind('fruver', 'Frutas y verduras', Icons.eco_outlined, _comida, 'fruver organico'),
  BusinessKind('bebidas', 'Bebidas', Icons.local_drink_outlined, _comida, 'jugos gaseosas agua'),
  BusinessKind('licores', 'Licores', Icons.liquor_outlined, _comida, 'licorera trago'),
  BusinessKind('vinos', 'Vinos', Icons.wine_bar_outlined, _comida, 'vino'),
  BusinessKind('cerveza', 'Cervecería', Icons.sports_bar_outlined, _comida, 'cerveza pola'),
  BusinessKind('bar', 'Bar', Icons.local_bar_outlined, _comida, 'cocteles'),
  // Moda y belleza
  BusinessKind('ropa', 'Ropa', Icons.checkroom_outlined, _moda, 'boutique prendas'),
  BusinessKind('sastreria', 'Sastrería', Icons.dry_cleaning_outlined, _moda, 'arreglos costura modisteria'),
  BusinessKind('bebes', 'Bebés', Icons.child_friendly_outlined, _moda, 'ninos coches'),
  BusinessKind('marroquineria', 'Marroquinería', Icons.work_outlined, _moda, 'bolsos maletas cuero'),
  BusinessKind('belleza', 'Peluquería', Icons.content_cut_outlined, _moda, 'salon belleza corte'),
  BusinessKind('barberia', 'Barbería', Icons.face_outlined, _moda, 'barba'),
  BusinessKind('unas', 'Uñas', Icons.back_hand_outlined, _moda, 'manicure pedicure'),
  BusinessKind('cosmeticos', 'Cosméticos', Icons.face_retouching_natural_outlined, _moda, 'maquillaje'),
  BusinessKind('perfumeria', 'Perfumería', Icons.water_drop_outlined, _moda, 'perfumes fragancias'),
  BusinessKind('spa', 'Spa', Icons.spa_outlined, _moda, 'masajes relajacion'),
  BusinessKind('joyeria', 'Joyería', Icons.diamond_outlined, _moda, 'joyas oro bisuteria'),
  BusinessKind('relojeria', 'Relojería', Icons.watch_outlined, _moda, 'relojes'),
  // Salud
  BusinessKind('drogueria', 'Droguería', Icons.local_pharmacy_outlined, _salud, 'farmacia'),
  BusinessKind('medicamentos', 'Medicamentos', Icons.medication_outlined, _salud, 'remedios pastillas'),
  BusinessKind('salud', 'Consultorio', Icons.medical_services_outlined, _salud, 'medico doctor'),
  BusinessKind('clinica', 'Clínica', Icons.local_hospital_outlined, _salud, 'hospital urgencias'),
  BusinessKind('laboratorio', 'Laboratorio', Icons.science_outlined, _salud, 'examenes'),
  BusinessKind('vacunas', 'Vacunación', Icons.vaccines_outlined, _salud, 'vacunas inyecciones'),
  BusinessKind('primeros_auxilios', 'Primeros auxilios', Icons.healing_outlined, _salud, 'curas'),
  BusinessKind('optica', 'Óptica', Icons.visibility_outlined, _salud, 'gafas lentes'),
  BusinessKind('gimnasio', 'Gimnasio', Icons.fitness_center_outlined, _salud, 'gym pesas'),
  BusinessKind('yoga', 'Yoga', Icons.self_improvement_outlined, _salud, 'meditacion bienestar'),
  BusinessKind('mascotas', 'Mascotas', Icons.pets_outlined, _salud, 'veterinaria perros gatos'),
  // Hogar y ferretería
  BusinessKind('ferreteria', 'Ferretería', Icons.handyman_outlined, _hogar, 'herramientas'),
  BusinessKind('construccion', 'Construcción', Icons.hardware_outlined, _hogar, 'materiales martillo'),
  BusinessKind('obra', 'Obra', Icons.construction_outlined, _hogar, 'construccion obras'),
  BusinessKind('pinturas', 'Pinturas', Icons.format_paint_outlined, _hogar, 'pintura'),
  BusinessKind('electricos', 'Eléctricos', Icons.electrical_services_outlined, _hogar, 'electricidad cables'),
  BusinessKind('iluminacion', 'Iluminación', Icons.lightbulb_outlined, _hogar, 'bombillos lamparas'),
  BusinessKind('plomeria', 'Plomería', Icons.plumbing_outlined, _hogar, 'tuberia'),
  BusinessKind('cerrajeria', 'Cerrajería', Icons.key_outlined, _hogar, 'llaves chapas'),
  BusinessKind('vidrios', 'Vidrios', Icons.window_outlined, _hogar, 'ventanas vidrieria'),
  BusinessKind('muebles', 'Muebles', Icons.chair_outlined, _hogar, 'muebleria sillas'),
  BusinessKind('colchones', 'Colchones', Icons.bed_outlined, _hogar, 'camas'),
  BusinessKind('electrodomesticos', 'Electrodomésticos', Icons.kitchen_outlined, _hogar, 'neveras cocina'),
  BusinessKind('hogar', 'Hogar', Icons.home_outlined, _hogar, 'casa decoracion'),
  BusinessKind('jardin', 'Vivero', Icons.yard_outlined, _hogar, 'jardin plantas'),
  BusinessKind('aseo', 'Aseo', Icons.cleaning_services_outlined, _hogar, 'limpieza'),
  // Tecnología
  BusinessKind('tecnologia', 'Tecnología', Icons.devices_outlined, _tecno, 'electronica'),
  BusinessKind('celulares', 'Celulares', Icons.smartphone_outlined, _tecno, 'telefonos moviles'),
  BusinessKind('accesorios', 'Accesorios', Icons.battery_charging_full_outlined, _tecno, 'cargadores baterias'),
  BusinessKind('computadores', 'Computadores', Icons.computer_outlined, _tecno, 'portatiles pc'),
  BusinessKind('electronica', 'Electrónica', Icons.memory_outlined, _tecno, 'componentes'),
  BusinessKind('audio', 'Audio', Icons.headphones_outlined, _tecno, 'audifonos parlantes sonido'),
  BusinessKind('tv', 'Televisores', Icons.tv_outlined, _tecno, 'tv pantallas'),
  BusinessKind('videojuegos', 'Videojuegos', Icons.sports_esports_outlined, _tecno, 'consolas juegos'),
  BusinessKind('fotografia', 'Fotografía', Icons.photo_camera_outlined, _tecno, 'fotos camaras'),
  BusinessKind('camaras', 'Cámaras de seguridad', Icons.videocam_outlined, _tecno, 'video vigilancia'),
  BusinessKind('impresion', 'Impresiones', Icons.print_outlined, _tecno, 'fotocopias impresora'),
  BusinessKind('servicio_tecnico', 'Servicio técnico', Icons.build_outlined, _tecno, 'reparacion arreglos'),
  BusinessKind('internet', 'Internet', Icons.wifi_outlined, _tecno, 'cafe internet wifi'),
  // Transporte
  BusinessKind('taller', 'Taller', Icons.car_repair_outlined, _motor, 'mecanica carros'),
  BusinessKind('repuestos', 'Repuestos', Icons.settings_outlined, _motor, 'autopartes'),
  BusinessKind('llantas', 'Llantería', Icons.tire_repair_outlined, _motor, 'llantas montallantas'),
  BusinessKind('lavadero', 'Lavadero', Icons.local_car_wash_outlined, _motor, 'lavado carros'),
  BusinessKind('gasolina', 'Estación de gasolina', Icons.local_gas_station_outlined, _motor, 'combustible bomba'),
  BusinessKind('parqueadero', 'Parqueadero', Icons.local_parking_outlined, _motor, 'parking'),
  BusinessKind('motos', 'Motos', Icons.two_wheeler_outlined, _motor, 'motocicletas'),
  BusinessKind('bicicletas', 'Bicicletas', Icons.pedal_bike_outlined, _motor, 'bici cicla'),
  BusinessKind('taxi', 'Taxi', Icons.local_taxi_outlined, _motor, 'transporte pasajeros'),
  BusinessKind('transporte', 'Transporte y envíos', Icons.local_shipping_outlined, _motor, 'camion carga mudanzas'),
  // Agro y campo
  BusinessKind('agro', 'Agro', Icons.agriculture_outlined, _agro, 'finca tractor campo'),
  BusinessKind('agroinsumos', 'Agroinsumos', Icons.grass_outlined, _agro, 'semillas abonos'),
  BusinessKind('floristeria', 'Floristería', Icons.local_florist_outlined, _agro, 'flores'),
  BusinessKind('madera', 'Maderas', Icons.forest_outlined, _agro, 'aserrio carpinteria'),
  BusinessKind('pesca', 'Pesca', Icons.phishing_outlined, _agro, 'anzuelos'),
  BusinessKind('granja', 'Granja', Icons.cruelty_free_outlined, _agro, 'animales conejos'),
  // Educación y oficina
  BusinessKind('papeleria', 'Papelería', Icons.edit_note_outlined, _oficina, 'utiles cuadernos'),
  BusinessKind('libreria', 'Librería', Icons.menu_book_outlined, _oficina, 'libros'),
  BusinessKind('educacion', 'Educación', Icons.school_outlined, _oficina, 'colegio cursos clases'),
  BusinessKind('idiomas', 'Idiomas', Icons.translate_outlined, _oficina, 'ingles traduccion'),
  BusinessKind('oficina', 'Oficina', Icons.business_center_outlined, _oficina, 'empresa'),
  BusinessKind('contabilidad', 'Contabilidad', Icons.calculate_outlined, _oficina, 'contador impuestos'),
  BusinessKind('legal', 'Asesoría legal', Icons.gavel_outlined, _oficina, 'abogados notaria'),
  BusinessKind('diseno', 'Diseño', Icons.design_services_outlined, _oficina, 'grafico publicidad'),
  BusinessKind('arte', 'Arte', Icons.palette_outlined, _oficina, 'pintura cuadros'),
  BusinessKind('manualidades', 'Manualidades', Icons.brush_outlined, _oficina, 'artesanias'),
  // Ocio y eventos
  BusinessKind('juguetes', 'Juguetería', Icons.toys_outlined, _ocio, 'juguetes ninos'),
  BusinessKind('deportes', 'Deportes', Icons.sports_soccer_outlined, _ocio, 'futbol balones'),
  BusinessKind('fiestas', 'Fiestas', Icons.celebration_outlined, _ocio, 'eventos decoracion globos'),
  BusinessKind('musica', 'Música', Icons.music_note_outlined, _ocio, 'instrumentos'),
  BusinessKind('cine', 'Cine', Icons.movie_outlined, _ocio, 'peliculas'),
  BusinessKind('teatro', 'Teatro', Icons.theater_comedy_outlined, _ocio, 'shows'),
  BusinessKind('discoteca', 'Discoteca', Icons.nightlife_outlined, _ocio, 'rumba baile'),
  BusinessKind('piscina', 'Piscina', Icons.pool_outlined, _ocio, 'natacion'),
  BusinessKind('apuestas', 'Apuestas y lotería', Icons.casino_outlined, _ocio, 'chance juegos azar'),
  // Viajes
  BusinessKind('hotel', 'Hotel', Icons.hotel_outlined, _viajes, 'hospedaje hostal'),
  BusinessKind('viajes', 'Agencia de viajes', Icons.flight_outlined, _viajes, 'tiquetes vuelos'),
  BusinessKind('turismo', 'Turismo', Icons.beach_access_outlined, _viajes, 'playa vacaciones'),
  BusinessKind('tours', 'Tours', Icons.map_outlined, _viajes, 'guia excursiones'),
  BusinessKind('equipaje', 'Equipaje', Icons.luggage_outlined, _viajes, 'maletas'),
  // Servicios
  BusinessKind('lavanderia', 'Lavandería', Icons.local_laundry_service_outlined, _servicios, 'lavado ropa'),
  BusinessKind('pagos', 'Pagos y giros', Icons.payments_outlined, _servicios, 'recargas giros'),
  BusinessKind('corresponsal', 'Corresponsal bancario', Icons.account_balance_outlined, _servicios, 'banco'),
  BusinessKind('ahorro', 'Cooperativa', Icons.savings_outlined, _servicios, 'ahorro credito'),
  BusinessKind('mensajeria', 'Mensajería', Icons.local_post_office_outlined, _servicios, 'correo paquetes'),
  BusinessKind('inmobiliaria', 'Inmobiliaria', Icons.real_estate_agent_outlined, _servicios, 'arriendos casas'),
  BusinessKind('publicidad', 'Publicidad', Icons.campaign_outlined, _servicios, 'marketing'),
  BusinessKind('vigilancia', 'Vigilancia', Icons.security_outlined, _servicios, 'seguridad'),
  BusinessKind('iglesia', 'Iglesia', Icons.church_outlined, _servicios, 'fundacion'),
  BusinessKind('otro', 'Otro', Icons.category_outlined, _servicios, 'general varios'),
];

/// Rubros en el orden en que aparecen en el panel
List<String> get kBusinessKindGroups => kBusinessKinds.map((k) => k.group).toSet().toList();

String _plain(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[áà]'), 'a')
    .replaceAll(RegExp('[éè]'), 'e')
    .replaceAll(RegExp('[íì]'), 'i')
    .replaceAll(RegExp('[óò]'), 'o')
    .replaceAll(RegExp('[úùü]'), 'u')
    .replaceAll('ñ', 'n');

/// Íconos que coinciden con lo buscado, sin importar tildes ni mayúsculas. Cada
/// palabra buscada debe ser el comienzo de alguna palabra del nombre, el rubro o
/// las palabras extra. Primero salen los que coinciden por el nombre; vacío
/// devuelve todos.
List<BusinessKind> searchBusinessKinds(String query) {
  final words = _plain(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return kBusinessKinds;

  List<String> split(String text) => _plain(text).split(RegExp(r'[^a-z0-9]+'));
  bool matches(List<String> haystack, String word) => haystack.any((h) => h.startsWith(word));

  final scored = <(BusinessKind, int)>[];
  for (final k in kBusinessKinds) {
    final name = split(k.label);
    final all = [...name, ...split(k.group), ...split(k.tags)];
    if (!words.every((w) => matches(all, w))) continue;
    // 0: el nombre empieza igual · 1: alguna palabra del nombre · 2: rubro o extras
    final score = _plain(k.label).startsWith(words.first) ? 0 : (words.every((w) => matches(name, w)) ? 1 : 2);
    scored.add((k, score));
  }
  scored.sort((x, y) => x.$2.compareTo(y.$2));
  return [for (final e in scored) e.$1];
}

/// Resultado del buscador separado en dos: los que coinciden por el nombre y los
/// relacionados (por el rubro o las palabras extra), que van abajo con su título
({List<BusinessKind> byName, List<BusinessKind> related}) searchBusinessKindsSplit(String query) {
  final words = _plain(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final results = searchBusinessKinds(query);
  if (words.isEmpty) return (byName: results, related: const []);
  bool inName(BusinessKind k) {
    final name = _plain(k.label).split(RegExp(r'[^a-z0-9]+'));
    return words.every((w) => name.any((n) => n.startsWith(w)));
  }

  return (byName: results.where(inName).toList(), related: results.where((k) => !inName(k)).toList());
}

/// Fila del formulario con el ícono actual; al tocarla abre el panel para elegir
class BusinessIconField extends StatelessWidget {
  final String selected;
  final Color color;
  final ValueChanged<String> onSelected;

  const BusinessIconField({super.key, required this.selected, required this.color, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kind = businessKindFor(selected);
    final radius = BorderRadius.circular(AppRadius.control);
    return Semantics(
      button: true,
      label: 'Ícono del negocio: ${kind.label}. Cambiar',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: radius,
        onTap: () async {
          final key = await BusinessIconPickerSheet.show(context, selected: selected, color: color);
          if (key != null) onSelected(key);
        },
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: c.lineStrong)),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                child: Icon(kind.icon, color: Colors.white),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ícono del negocio', style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
                    Text(kind.label, style: TextStyle(fontSize: AppText.sizeTitle, fontWeight: FontWeight.w600, color: c.ink)),
                  ],
                ),
              ),
              Text('Cambiar', style: TextStyle(fontWeight: FontWeight.w600, color: c.accent)),
              Icon(Icons.chevron_right_outlined, color: c.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel "Elegir ícono": buscador y cuadrícula solo de íconos, separada por rubros. Devuelve la
/// clave elegida (o null si se cierra sin elegir).
class BusinessIconPickerSheet extends StatefulWidget {
  final String selected;
  final Color color;

  const BusinessIconPickerSheet({super.key, required this.selected, required this.color});

  static Future<String?> show(BuildContext context, {required String selected, required Color color}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BusinessIconPickerSheet(selected: selected, color: color),
    );
  }

  @override
  State<BusinessIconPickerSheet> createState() => _BusinessIconPickerSheetState();
}

class _BusinessIconPickerSheetState extends State<BusinessIconPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final searching = _query.trim().isNotEmpty;
    final found = searchBusinessKindsSplit(_query);
    final empty = found.byName.isEmpty && found.related.isEmpty;

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.85,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.sm, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('Elegir ícono', style: TextStyle(fontSize: AppText.sizeHeading, fontWeight: FontWeight.w700, color: c.ink)),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_outlined, color: c.inkMuted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Buscar: pan, ropa, moto…',
                prefixIcon: Icon(Icons.search_outlined),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Expanded(
            child: empty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    child: Text(
                      'No encontramos ese ícono. Prueba con otra palabra o elige "Otro".',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.inkMuted),
                    ),
                  )
                : CustomScrollView(
                    slivers: [
                      // Sin búsqueda: todos los íconos, cada rubro con su título
                      if (!searching)
                        for (final group in kBusinessKindGroups) ...[
                          _heading(group.toUpperCase(), c),
                          _grid(kBusinessKinds.where((k) => k.group == group).toList()),
                        ]
                      else ...[
                        if (found.byName.isNotEmpty) _grid(found.byName),
                        if (found.related.isNotEmpty) ...[
                          _heading(
                            '${found.byName.isEmpty ? 'Íconos' : 'Otros íconos'} relacionados con «${_query.trim()}»',
                            c,
                          ),
                          _grid(found.related),
                        ],
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _heading(String text, StockealoColors c) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.sm),
        sliver: SliverToBoxAdapter(
          child: Text(
            text,
            style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.inkFaint),
          ),
        ),
      );

  Widget _grid(List<BusinessKind> kinds) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, 0),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 64,
            mainAxisSpacing: AppSpace.sm,
            crossAxisSpacing: AppSpace.sm,
          ),
          itemCount: kinds.length,
          itemBuilder: (context, i) => _IconTile(
            kind: kinds[i],
            selected: kinds[i].key == widget.selected,
            color: widget.color,
            onTap: () => Navigator.pop(context, kinds[i].key),
          ),
        ),
      );
}

class _IconTile extends StatelessWidget {
  final BusinessKind kind;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _IconTile({required this.kind, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.control);
    return Tooltip(
      message: kind.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Ícono ${kind.label}',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            decoration: BoxDecoration(
              color: selected ? color : c.surfaceMuted,
              borderRadius: radius,
              border: Border.all(color: selected ? color : c.line),
            ),
            child: Icon(kind.icon, size: 24, color: selected ? Colors.white : c.inkMuted),
          ),
        ),
      ),
    );
  }
}

BusinessKind businessKindFor(String? key) =>
    kBusinessKinds.firstWhere((k) => k.key == key, orElse: () => kBusinessKinds.first);

/// Logo, o ícono con el color del negocio, o su inicial: lo que identifica al negocio
/// en el selector, Ajustes y lo que se comparte.
class BusinessAvatar extends StatelessWidget {
  final Business business;
  final double size;

  const BusinessAvatar({super.key, required this.business, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = AppPalette.fromHex(business.color) ?? c.accent;
    final radius = BorderRadius.circular(size * 0.3);

    if (business.logoUrl != null && business.logoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          business.logoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _iconAvatar(color, radius),
        ),
      );
    }
    return _iconAvatar(color, radius);
  }

  Widget _iconAvatar(Color color, BorderRadius radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, borderRadius: radius),
      alignment: Alignment.center,
      child: business.icon == null
          ? Text(
              business.name.isNotEmpty ? business.name.characters.first.toUpperCase() : '?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.42),
            )
          : Icon(businessKindFor(business.icon).icon, color: Colors.white, size: size * 0.55),
    );
  }
}

/// Logo del negocio en catálogos y comprobantes; sin logo, la inicial en un cuadro blanco con
/// el color del catálogo
class CatalogLogo extends StatelessWidget {
  final Business business;
  final Color color;
  final double size;

  const CatalogLogo({super.key, required this.business, required this.color, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.28);
    final logo = business.logoUrl;
    if (logo != null && logo.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: ProductImageView(imagePath: logo, width: size, height: size, iconSize: size / 2),
      );
    }
    final name = business.name.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.white, borderRadius: radius),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'S',
        style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}
