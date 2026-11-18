import 'package:flutter/material.dart';

/// Lista ÚNICA de permisos de Stockealo (0.15.0, `docs/plan-roles.md`).
///
/// Cada módulo o función nueva registra aquí sus permisos: así aparecen solos en la
/// pantalla de roles y se revisan con [Permissions.can] en un solo lugar. Nunca se
/// vuelve a escribir `role == 'OWNER' || role == 'ADMIN'` en una pantalla.
enum PermGroup {
  sales('Ventas', Icons.point_of_sale_outlined),
  cash('Caja', Icons.account_balance_wallet_outlined),
  inventory('Inventario', Icons.inventory_2_outlined),
  customers('Clientes', Icons.people_alt_outlined),
  reports('Reportes', Icons.insert_chart_outlined),
  services('Servicios', Icons.view_kanban_outlined),
  settings('Ajustes', Icons.settings_outlined);

  final String label;
  final IconData icon;
  const PermGroup(this.label, this.icon);
}

/// Un permiso: su grupo, su nombre y la frase que explica qué permite.
/// El nombre del valor (`Perm.costs.name`) es la clave que se guarda: no se cambia.
enum Perm {
  // Ventas
  sell(PermGroup.sales, 'Vender', 'Hacer ventas y cobrar'),
  discount(PermGroup.sales, 'Dar descuento', 'Bajar el precio de una venta'),
  sellBelowCost(PermGroup.sales, 'Vender por debajo del costo', 'Autorizar un descuento que deja pérdida'),
  credit(PermGroup.sales, 'Fiar', 'Vender para que el cliente pague después'),
  voidSale(PermGroup.sales, 'Anular venta', 'Deshacer una venta y devolver el stock'),
  refund(PermGroup.sales, 'Devolver', 'Recibir productos de vuelta y devolver el dinero'),
  allSales(PermGroup.sales, 'Ver las ventas de todos', 'Si está apagado, solo ve sus propias ventas'),
  quotations(PermGroup.sales, 'Cotizaciones', 'Crear cotizaciones y atender los pedidos de la tienda'),

  // Caja
  cashOwn(PermGroup.cash, 'Abrir y cerrar mi caja', 'Su propio turno de caja'),
  cashOthers(PermGroup.cash, 'Cerrar la caja de otros', 'Cerrar un turno que abrió otra persona'),
  cashMoves(PermGroup.cash, 'Entradas y salidas de dinero', 'Registrar plata que entra o sale de la caja'),
  cashExpected(PermGroup.cash, 'Ver lo esperado en caja', 'Si está apagado, cuenta la plata sin ver cuánto debería haber'),

  // Inventario
  productsEdit(PermGroup.inventory, 'Crear y editar productos', 'Agregar productos, cambiar precios y fotos'),
  costs(PermGroup.inventory, 'Ver costos', 'El precio al que compras cada producto y cuánto ganas'),
  stockAdjust(PermGroup.inventory, 'Ajustar stock', 'Corregir las unidades a mano'),
  suppliers(PermGroup.inventory, 'Proveedores y entradas', 'Recibir mercancía, pedidos y pagos a proveedores'),
  importExcel(PermGroup.inventory, 'Importar desde Excel', 'Cargar muchos productos de una vez'),
  catalog(PermGroup.inventory, 'Catálogo', 'Crear y compartir el catálogo en PDF'),
  promotions(PermGroup.inventory, 'Promociones', 'Crear descuentos, 2x1 y ofertas'),

  // Clientes
  customersEdit(PermGroup.customers, 'Crear y editar clientes', 'Agregar clientes y cambiar sus datos'),
  collectDebts(PermGroup.customers, 'Cobrar fiados', 'Registrar los abonos de los clientes'),
  allDebts(PermGroup.customers, 'Ver deudas de todos', 'Cuánto debe cada cliente'),

  // Reportes
  reportsSales(PermGroup.reports, 'Ver reportes', 'Ventas por día, por producto y por persona'),
  profits(PermGroup.reports, 'Ver ganancias', 'Cuánto gana el negocio'),
  exportExcel(PermGroup.reports, 'Descargar Excel', 'Bajar los reportes con costos y márgenes'),

  // Servicios
  servicesWork(PermGroup.services, 'Recibir y mover trabajos', 'Usar el tablero: recibir, empezar y terminar'),
  servicesCharge(PermGroup.services, 'Cobrar trabajos', 'Cobrar las órdenes listas'),
  appointments(PermGroup.services, 'Agendar citas', 'Crear y mover citas de la agenda'),
  myCommissions(PermGroup.services, 'Ver mis comisiones', 'Lo que lleva ganado'),
  allCommissions(PermGroup.services, 'Comisiones de todos', 'Ver y liquidar lo de cada empleado'),
  servicesSetup(PermGroup.services, 'Catálogo de servicios', 'Servicios, precios y mensajes de WhatsApp'),

  // Ajustes
  team(PermGroup.settings, 'Equipo e invitar', 'Invitar personas y cambiar su rol'),
  activity(PermGroup.settings, 'Actividad del equipo', 'Quién vendió, cambió precios o ajustó el stock'),
  authorize(PermGroup.settings, 'Autorizar a otros', 'Aprobar una acción que el rol de otra persona no permite'),
  modules(PermGroup.settings, 'Módulos', 'Encender o apagar módulos'),
  businessInfo(PermGroup.settings, 'Datos del negocio', 'Nombre, logo, dirección y recibo'),
  store(PermGroup.settings, 'Tienda en línea', 'Configurar la tienda y su diseño'),
  cloud(PermGroup.settings, 'Nube y respaldo', 'Sincronizar y hacer copias');

  final PermGroup group;
  final String label;
  final String help;
  const Perm(this.group, this.label, this.help);

  static Perm? byName(String name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// Límites con números (0.15.0, Pro): pasar de ahí pide autorización
enum RoleLimit {
  discountPct('Descuento máximo', 'Más de este porcentaje pide autorización', '%'),
  creditMax('Fiado máximo por cliente', 'Lo que puede quedar debiendo cada cliente', '\$'),
  voidHours('Anular solo ventas recientes', 'Horas desde la venta; más viejas piden autorización', 'h'),
  cashOutMax('Salida de caja máxima', 'Por cada salida de dinero', '\$');

  final String label;
  final String help;
  final String unit;
  const RoleLimit(this.label, this.help, this.unit);

  static RoleLimit? byName(String name) {
    for (final l in values) {
      if (l.name == name) return l;
    }
    return null;
  }
}

/// Plantilla para crear un rol propio más rápido (no es un rol aparte)
class RoleTemplate {
  final String id;
  final String name;
  final String forWho;
  final IconData icon;
  final Set<Perm> perms;
  const RoleTemplate({required this.id, required this.name, required this.forWho, required this.icon, required this.perms});
}

class Permissions {
  Permissions._();

  static const owner = 'OWNER';
  static const admin = 'ADMIN';
  static const cashier = 'CASHIER';

  /// Lo que el Administrador no tiene: el equipo lo maneja solo el dueño
  static const _notAdmin = {Perm.team};

  /// El Cajero de siempre: vende, fía, maneja su caja y atiende servicios.
  /// Son los mismos permisos que tenía antes de la 0.15.0.
  static const _cashierPerms = {
    Perm.sell,
    Perm.discount,
    Perm.credit,
    Perm.allSales,
    Perm.quotations,
    Perm.cashOwn,
    Perm.cashMoves,
    Perm.cashExpected,
    Perm.catalog,
    Perm.customersEdit,
    Perm.collectDebts,
    Perm.allDebts,
    Perm.servicesWork,
    Perm.servicesCharge,
    Perm.appointments,
    Perm.myCommissions,
  };

  /// Un permiso necesita otro: al encenderlo se enciende el otro
  static const dependsOn = <Perm, Set<Perm>>{
    Perm.discount: {Perm.sell},
    Perm.sellBelowCost: {Perm.sell, Perm.discount, Perm.costs},
    Perm.credit: {Perm.sell},
    Perm.voidSale: {Perm.sell},
    Perm.refund: {Perm.sell},
    Perm.cashOthers: {Perm.cashOwn},
    Perm.importExcel: {Perm.productsEdit},
    Perm.promotions: {Perm.productsEdit},
    Perm.profits: {Perm.reportsSales, Perm.costs},
    Perm.exportExcel: {Perm.reportsSales, Perm.costs},
    Perm.servicesCharge: {Perm.servicesWork},
    Perm.allCommissions: {Perm.myCommissions},
  };

  /// Lo que trae de fábrica cada rol por defecto (sin los ajustes del negocio)
  static Set<Perm> factoryDefaults(String role) => switch (role.toUpperCase()) {
        owner => Perm.values.toSet(),
        admin => Perm.values.where((p) => !_notAdmin.contains(p)).toSet(),
        _ => _cashierPerms,
      };

  // ---------------------------------------------------------------------------
  // Roles del negocio activo (0.15.0, etapa 2): los ajustes del Administrador y del
  // Cajero, y los roles propios. Los carga RolesRepository.apply al abrir el negocio.
  // ---------------------------------------------------------------------------

  /// Un rol propio se lee como 'ROLE:<id>'
  static const customPrefix = 'ROLE:';
  static String customRole(String id) => '$customPrefix$id';
  static bool isCustom(String? role) => role?.startsWith(customPrefix) ?? false;
  static String? customId(String? role) => isCustom(role) ? role!.substring(customPrefix.length) : null;

  static final Map<String, Set<Perm>> _builtins = {};
  static final Map<String, ({String name, Set<Perm> perms})> _custom = {};
  static final Map<String, Map<RoleLimit, double>> _limits = {};

  /// Pone los roles del negocio activo (reemplaza los del negocio anterior).
  /// [limits] va por rol: 'ADMIN', 'CASHIER' o 'ROLE:<id>'.
  static void applyBusiness({
    Map<String, Set<Perm>> builtins = const {},
    Map<String, ({String name, Set<Perm> perms})> custom = const {},
    Map<String, Map<RoleLimit, double>> limits = const {},
  }) {
    _limits
      ..clear()
      ..addAll(limits);
    _builtins
      ..clear()
      ..addAll({
        for (final e in builtins.entries)
          if (e.key == admin || e.key == cashier) e.key: e.value,
      });
    _custom
      ..clear()
      ..addAll(custom);
  }

  /// Los permisos de un rol: el Dueño todo; el Administrador y el Cajero los suyos
  /// (con los ajustes del negocio); un rol propio los que le dio el dueño. Un rol que
  /// no se conoce nunca gana nada: queda como el Cajero de fábrica.
  static Set<Perm> defaultsFor(String? role) {
    final r = role ?? cashier;
    if (isCustom(r)) return _custom[customId(r)]?.perms ?? _cashierPerms;
    final up = r.toUpperCase();
    if (up == owner) return Perm.values.toSet();
    if (up == admin) return _builtins[admin] ?? factoryDefaults(admin);
    if (up == cashier) return _builtins[cashier] ?? _cashierPerms;
    return _cashierPerms;
  }

  /// ¿Puede este rol hacer esto?
  static bool can(String? role, Perm perm) => defaultsFor(role).contains(perm);

  /// El límite de un rol; null = sin límite. El Dueño nunca tiene límites.
  static double? limitOf(String? role, RoleLimit limit) {
    final r = role ?? cashier;
    if (!isCustom(r) && r.toUpperCase() == owner) return null;
    return _limits[isCustom(r) ? r : r.toUpperCase()]?[limit];
  }

  /// El nombre del rol para mostrar
  static String labelOf(String? role) {
    if (isCustom(role)) return _custom[customId(role)]?.name ?? 'Rol propio';
    return switch ((role ?? cashier).toUpperCase()) {
      owner => 'Dueño',
      admin => 'Administrador',
      _ => 'Cajero',
    };
  }

  /// En qué rol de la nube se apoya un rol propio: si todo lo que tiene lo puede un
  /// Cajero, en el Cajero; si no, en el Administrador (para que la nube lo deje trabajar)
  static String baseFor(Set<Perm> perms) => perms.every(_cashierPerms.contains) ? cashier : admin;

  /// Apagar un permiso apaga también los que lo necesitan (al revés de [withDependencies])
  static Set<Perm> dependentsOf(Perm perm) => {
        for (final p in Perm.values)
          if (p != perm && withDependencies({p}).contains(perm)) p,
      };

  /// «Ver como» (0.15.0): el dueño ve la app como la vería ese rol. null = su propio rol
  static final viewAs = ValueNotifier<String?>(null);

  /// El rol de la persona en el negocio activo (lo pone el menú principal)
  static String current = owner;

  /// ¿El rol activo puede hacer esto? Tiene en cuenta «Ver como»
  static bool mine(Perm perm) => can(viewAs.value ?? current, perm);

  /// El límite del rol activo; null = sin límite
  static double? myLimit(RoleLimit limit) => limitOf(viewAs.value ?? current, limit);

  /// Enciende también los permisos de los que depende (en cadena)
  static Set<Perm> withDependencies(Set<Perm> perms) {
    final out = {...perms};
    var grew = true;
    while (grew) {
      grew = false;
      for (final p in [...out]) {
        for (final d in dependsOn[p] ?? const <Perm>{}) {
          if (out.add(d)) grew = true;
        }
      }
    }
    return out;
  }

  /// Plantillas para crear roles propios (sección 2.1 del plan)
  static const templates = <RoleTemplate>[
    RoleTemplate(
      id: 'vendedor',
      name: 'Vendedor',
      forWho: 'Quien atiende sin manejar plata',
      icon: Icons.storefront_outlined,
      perms: {Perm.sell, Perm.credit, Perm.quotations, Perm.catalog, Perm.customersEdit},
    ),
    RoleTemplate(
      id: 'bodega',
      name: 'Bodega',
      forWho: 'Quien recibe mercancía',
      icon: Icons.move_to_inbox_outlined,
      perms: {Perm.stockAdjust, Perm.suppliers, Perm.productsEdit},
    ),
    RoleTemplate(
      id: 'solo_ver',
      name: 'Solo ver',
      forWho: 'Contador o socio',
      icon: Icons.visibility_outlined,
      perms: {Perm.allSales, Perm.allDebts, Perm.costs, Perm.reportsSales, Perm.profits, Perm.exportExcel, Perm.activity},
    ),
    RoleTemplate(
      id: 'encargado',
      name: 'Encargado',
      forWho: 'Quien queda a cargo del local',
      icon: Icons.supervisor_account_outlined,
      perms: {..._cashierPerms, Perm.cashOthers, Perm.authorize, Perm.voidSale, Perm.activity},
    ),
    RoleTemplate(
      id: 'servicios',
      name: 'Atiende servicios',
      forWho: 'Lavador, barbero o técnico',
      icon: Icons.handyman_outlined,
      perms: {Perm.servicesWork, Perm.appointments, Perm.myCommissions},
    ),
  ];
}
