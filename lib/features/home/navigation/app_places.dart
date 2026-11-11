import 'package:flutter/material.dart';

/// Los lugares de la app: UNA lista para el menú del computador, el menú del
/// celular (☰), los títulos del encabezado, el buscador, los accesos rápidos,
/// Stocky y los avisos. El menú sigue el día del negocio (re-diseño 0.13.0,
/// docs/plan-rediseno.md): Inicio · Vender · Ventas · Caja · Servicios ·
/// Productos · Stock · Clientes y proveedores · Tienda · Reportes · Ajustes.
///
/// Los números 0 a 5 son los de antes y significan lo mismo (Stocky, los avisos
/// y los accesos guardados los usan): 1 era «Inventario» y ahora es Productos.
/// Cada función sigue teniendo UN solo lugar (regla «nada duplicado»).
class AppPlace {
  final int id;
  final String label;
  final IconData icon;
  final String group;

  /// Línea de contexto debajo del título en el encabezado
  final String subtitle;

  /// Solo dueño o administrador
  final bool managersOnly;

  /// Solo con Pro Servicios
  final bool needsServices;

  const AppPlace({
    required this.id,
    required this.label,
    required this.icon,
    required this.group,
    required this.subtitle,
    this.managersOnly = false,
    this.needsServices = false,
  });

  /// Pedido de ir a un lugar desde una pantalla que está encima del marco (el
  /// detalle de un producto, el buscador). El marco lo atiende y lo vuelve null.
  static final request = ValueNotifier<int?>(null);

  /// Lleva a ese lugar del menú desde cualquier parte
  static void go(int id) => request.value = id;

  static const int inicio = 0;
  static const int productos = 1;
  static const int ventas = 2;
  static const int ajustes = 3;
  static const int reportes = 4;
  static const int servicios = 5;
  static const int vender = 6;
  static const int caja = 7;
  static const int stock = 8;
  static const int personas = 9;
  static const int tienda = 10;

  static const String groupDay = 'Día a día';
  static const String groupInventory = 'Inventario';
  static const String groupMore = 'Personas y más';

  /// En el orden del menú. Ajustes va aparte, abajo, junto a la persona.
  static const List<AppPlace> menu = [
    AppPlace(id: inicio, label: 'Inicio', icon: Icons.space_dashboard_outlined, group: groupDay, subtitle: 'Resumen del día'),
    AppPlace(id: vender, label: 'Vender', icon: Icons.shopping_cart_outlined, group: groupDay, subtitle: 'Toca o escanea, cobra y sigue'),
    AppPlace(id: ventas, label: 'Ventas', icon: Icons.receipt_long_outlined, group: groupDay, subtitle: 'Lo vendido y las cotizaciones'),
    AppPlace(id: caja, label: 'Caja', icon: Icons.point_of_sale_outlined, group: groupDay, subtitle: 'Abrir, movimientos y cierre'),
    AppPlace(
      id: servicios,
      label: 'Servicios',
      icon: Icons.view_kanban_outlined,
      group: groupDay,
      subtitle: 'Tablero, asistencia y precios',
      needsServices: true,
    ),
    AppPlace(id: productos, label: 'Productos', icon: Icons.inventory_2_outlined, group: groupInventory, subtitle: 'Catálogo, precios, tallas y colores'),
    AppPlace(id: stock, label: 'Stock', icon: Icons.layers_outlined, group: groupInventory, subtitle: 'Lo que falta y lo que llega'),
    AppPlace(id: personas, label: 'Clientes y proveedores', icon: Icons.people_alt_outlined, group: groupMore, subtitle: 'Fiados, abonos y proveedores'),
    AppPlace(
      id: tienda,
      label: 'Tienda en línea',
      icon: Icons.storefront_outlined,
      group: groupMore,
      subtitle: 'Tu catálogo con carrito',
      managersOnly: true,
    ),
    AppPlace(
      id: reportes,
      label: 'Reportes',
      icon: Icons.insert_chart_outlined,
      group: groupMore,
      subtitle: 'Ganancias y descargas',
      managersOnly: true,
    ),
  ];

  static const AppPlace settings =
      AppPlace(id: ajustes, label: 'Ajustes', icon: Icons.settings_outlined, group: '', subtitle: 'Tu negocio, tu equipo y la app');

  static bool _isManager(String role) => role == 'OWNER' || role == 'ADMIN';

  /// ¿Esta persona puede ver este lugar?
  bool visibleFor({required String role, required bool services}) =>
      (!managersOnly || _isManager(role)) && (!needsServices || services);

  /// Los lugares del menú que ve esta persona, en orden
  static List<AppPlace> visible({required String role, required bool services}) =>
      [for (final p in menu) if (p.visibleFor(role: role, services: services)) p];

  /// El lugar con ese número (Ajustes incluido); Inicio si no existe
  static AppPlace byId(int id) =>
      id == ajustes ? settings : menu.firstWhere((p) => p.id == id, orElse: () => menu.first);
}
