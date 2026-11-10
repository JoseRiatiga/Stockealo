import 'package:flutter/material.dart';

/// Una función de la app con su único lugar (0.12.0, «nada duplicado»).
/// El buscador y Stocky solo llevan a la pestaña donde vive; no abren copias.
class AppFunction {
  final String title;

  /// Dónde vive, con las palabras de la app ("Ventas › Caja")
  final String where;

  /// Número de pestaña: 0 Inicio, 1 Inventario, 2 Ventas, 3 Ajustes, 4 Reportes, 5 Servicios
  final int tab;
  final IconData icon;
  final List<String> keywords;

  /// Solo dueño o administrador
  final bool managersOnly;

  /// Solo con Pro Servicios
  final bool needsServices;

  const AppFunction({
    required this.title,
    required this.where,
    required this.tab,
    required this.icon,
    required this.keywords,
    this.managersOnly = false,
    this.needsServices = false,
  });
}

const kAppFunctions = <AppFunction>[
  AppFunction(title: 'Nueva venta', where: 'Ventas', tab: 2, icon: Icons.point_of_sale_rounded,
      keywords: ['venta', 'vender', 'cobrar', 'factura']),
  AppFunction(title: 'Clientes y fiados', where: 'Ventas › Clientes y fiados', tab: 2, icon: Icons.people_alt_outlined,
      keywords: ['cliente', 'fiado', 'deuda', 'abono', 'debe']),
  AppFunction(title: 'Cotizaciones', where: 'Ventas › Cotizaciones', tab: 2, icon: Icons.request_quote_outlined,
      keywords: ['cotizacion', 'proforma', 'presupuesto']),
  AppFunction(title: 'Caja', where: 'Ventas › Caja', tab: 2, icon: Icons.point_of_sale_outlined,
      keywords: ['caja', 'arqueo', 'efectivo', 'cierre', 'base', 'turno']),
  AppFunction(title: 'Nuevo producto', where: 'Inventario', tab: 1, icon: Icons.add_box_outlined,
      keywords: ['producto', 'agregar', 'stock', 'inventario', 'existencia']),
  AppFunction(title: 'Importar desde Excel', where: 'Inventario › Importar desde Excel', tab: 1, icon: Icons.upload_file_outlined,
      keywords: ['importar', 'excel', 'cargar', 'subir', 'plantilla'], managersOnly: true),
  AppFunction(title: 'Proveedores y entradas', where: 'Inventario › Proveedores y entradas', tab: 1,
      icon: Icons.move_to_inbox_outlined, keywords: ['proveedor', 'pedido', 'entrada', 'mercancia', 'compra', 'pagar'],
      managersOnly: true),
  AppFunction(title: 'Catálogo', where: 'Inventario › Catálogo', tab: 1, icon: Icons.menu_book_rounded,
      keywords: ['catalogo', 'pdf', 'historia', 'compartir']),
  AppFunction(title: 'Tienda en línea', where: 'Inventario › Tienda en línea', tab: 1, icon: Icons.storefront_outlined,
      keywords: ['tienda', 'online', 'web', 'carrito', 'pedido en linea'], managersOnly: true),
  AppFunction(title: 'Ganancias', where: 'Reportes › Ganancias', tab: 4, icon: Icons.insights_rounded,
      keywords: ['ganancia', 'perdida', 'utilidad', 'reporte', 'margen'], managersOnly: true),
  AppFunction(title: 'Descargar Excel', where: 'Reportes › Descargar Excel', tab: 4, icon: Icons.table_chart_outlined,
      keywords: ['excel', 'descargar', 'exportar', 'reporte', 'xlsx'], managersOnly: true),
  AppFunction(title: 'Servicios', where: 'Servicios', tab: 5, icon: Icons.view_kanban_outlined,
      keywords: ['servicio', 'tablero', 'lavado', 'turno', 'cola', 'asistencia', 'comision', 'placa'], needsServices: true),
  AppFunction(title: 'Equipo', where: 'Ajustes › Equipo', tab: 3, icon: Icons.groups_2_outlined,
      keywords: ['equipo', 'empleado', 'cajero', 'invitar', 'permiso', 'rol']),
  AppFunction(title: 'Módulos', where: 'Ajustes › Módulos', tab: 3, icon: Icons.widgets_outlined,
      keywords: ['modulo', 'activar', 'encender', 'funciones']),
  AppFunction(title: 'Stockealo Pro', where: 'Ajustes › Stockealo Pro', tab: 3, icon: Icons.workspace_premium_outlined,
      keywords: ['pro', 'plan', 'codigo', 'canjear', 'suscripcion']),
  AppFunction(title: 'Apariencia', where: 'Ajustes › Apariencia', tab: 3, icon: Icons.palette_outlined,
      keywords: ['oscuro', 'claro', 'color', 'tema', 'letra', 'apariencia']),
  AppFunction(title: 'Nube y respaldo', where: 'Ajustes › Nube y respaldo', tab: 3, icon: Icons.cloud_outlined,
      keywords: ['nube', 'respaldo', 'copia', 'sincronizar', 'backup']),
];

String _fold(String s) {
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString();
}

/// Funciones que puede ver la persona y que coinciden con lo escrito (vacío = todas)
List<AppFunction> findFunctions(String query, {required String role, required bool services}) {
  final q = _fold(query.trim());
  final managers = role == 'OWNER' || role == 'ADMIN';
  return [
    for (final f in kAppFunctions)
      if ((!f.managersOnly || managers) &&
          (!f.needsServices || services) &&
          (q.isEmpty || _fold(f.title).contains(q) || f.keywords.any((k) => k.contains(q) || (k.length >= 4 && q.contains(k)))))
        f,
  ];
}
