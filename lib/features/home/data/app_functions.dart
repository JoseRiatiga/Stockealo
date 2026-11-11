import 'package:flutter/material.dart';

/// Una función de la app con su único lugar (0.12.0, «nada duplicado»).
/// Esta lista alimenta el buscador y los accesos rápidos de Inicio (0.12.1):
/// **al añadir una función o un módulo nuevo, se agrega aquí** y aparece sola
/// en los dos. El buscador lleva a la pestaña; el acceso rápido abre la función.
class AppFunction {
  /// Identificador fijo: con él se guardan los accesos rápidos de Inicio
  final String id;
  final String title;

  /// Dónde vive, con las palabras del menú ("Productos › Catálogo")
  final String where;

  /// Número del lugar donde vive (ver AppPlace en home/navigation/app_places.dart)
  final int tab;
  final IconData icon;
  final List<String> keywords;

  /// Solo dueño o administrador
  final bool managersOnly;

  /// Solo con Pro Servicios
  final bool needsServices;

  const AppFunction({
    required this.id,
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
  AppFunction(id: 'new_sale', title: 'Nueva venta', where: 'Vender', tab: 6, icon: Icons.point_of_sale_outlined,
      keywords: ['venta', 'vender', 'cobrar', 'factura']),
  AppFunction(id: 'customers', title: 'Clientes y fiados', where: 'Clientes y proveedores', tab: 9, icon: Icons.people_alt_outlined,
      keywords: ['cliente', 'fiado', 'deuda', 'abono', 'debe']),
  AppFunction(id: 'quotes', title: 'Cotizaciones', where: 'Ventas › Cotizaciones', tab: 2, icon: Icons.request_quote_outlined,
      keywords: ['cotizacion', 'proforma', 'presupuesto']),
  AppFunction(id: 'cash', title: 'Caja', where: 'Caja', tab: 7, icon: Icons.point_of_sale_outlined,
      keywords: ['caja', 'arqueo', 'efectivo', 'cierre', 'base', 'turno']),
  AppFunction(id: 'new_product', title: 'Nuevo producto', where: 'Productos', tab: 1, icon: Icons.add_box_outlined,
      keywords: ['producto', 'agregar', 'nuevo', 'inventario', 'crear']),
  AppFunction(id: 'import_excel', title: 'Importar desde Excel', where: 'Productos › Importar desde Excel', tab: 1, icon: Icons.upload_file_outlined,
      keywords: ['importar', 'excel', 'cargar', 'subir', 'plantilla'], managersOnly: true),
  AppFunction(id: 'suppliers', title: 'Proveedores y entradas', where: 'Clientes y proveedores › Proveedores', tab: 9,
      icon: Icons.move_to_inbox_outlined, keywords: ['proveedor', 'pedido', 'entrada', 'mercancia', 'compra', 'pagar'],
      managersOnly: true),
  AppFunction(id: 'stock', title: 'Stock por reponer', where: 'Stock', tab: 8, icon: Icons.layers_outlined,
      keywords: ['stock', 'reponer', 'agotado', 'falta', 'minimo', 'pedir', 'faltante']),
  AppFunction(id: 'catalog', title: 'Catálogo', where: 'Productos › Catálogo', tab: 1, icon: Icons.menu_book_outlined,
      keywords: ['catalogo', 'pdf', 'historia', 'compartir']),
  AppFunction(id: 'online_store', title: 'Tienda en línea', where: 'Tienda en línea', tab: 10, icon: Icons.storefront_outlined,
      keywords: ['tienda', 'online', 'web', 'carrito', 'pedido en linea'], managersOnly: true),
  AppFunction(id: 'profits', title: 'Ganancias', where: 'Reportes › Ganancias', tab: 4, icon: Icons.insights_outlined,
      keywords: ['ganancia', 'perdida', 'utilidad', 'reporte', 'margen'], managersOnly: true),
  AppFunction(id: 'excel', title: 'Descargar Excel', where: 'Reportes › Descargar Excel', tab: 4, icon: Icons.table_chart_outlined,
      keywords: ['excel', 'descargar', 'exportar', 'reporte', 'xlsx'], managersOnly: true),
  AppFunction(id: 'services', title: 'Servicios', where: 'Servicios', tab: 5, icon: Icons.view_kanban_outlined,
      keywords: ['servicio', 'tablero', 'lavado', 'turno', 'cola', 'asistencia', 'comision', 'placa'], needsServices: true),
  AppFunction(id: 'team', title: 'Equipo', where: 'Ajustes › Equipo', tab: 3, icon: Icons.groups_2_outlined,
      keywords: ['equipo', 'empleado', 'cajero', 'invitar', 'permiso', 'rol']),
  AppFunction(id: 'modules', title: 'Módulos', where: 'Ajustes › Módulos', tab: 3, icon: Icons.widgets_outlined,
      keywords: ['modulo', 'activar', 'encender', 'funciones']),
  AppFunction(id: 'pro', title: 'Stockealo Pro', where: 'Ajustes › Stockealo Pro', tab: 3, icon: Icons.workspace_premium_outlined,
      keywords: ['pro', 'plan', 'codigo', 'canjear', 'suscripcion']),
  AppFunction(id: 'appearance', title: 'Apariencia', where: 'Ajustes › Apariencia', tab: 3, icon: Icons.palette_outlined,
      keywords: ['oscuro', 'claro', 'color', 'tema', 'letra', 'apariencia']),
  AppFunction(id: 'cloud', title: 'Nube y respaldo', where: 'Ajustes › Nube y respaldo', tab: 3, icon: Icons.cloud_outlined,
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

/// Accesos rápidos que trae Inicio la primera vez
const kDefaultShortcutIds = ['new_sale', 'new_product', 'customers', 'catalog'];

/// Máximo de accesos en Inicio, para que no se llene la pantalla
const kMaxShortcuts = 8;

/// Nombres de los accesos de antes de la 0.12.0, para no perder lo que eligió cada negocio
const _legacyShortcutIds = {
  'sell': 'new_sale',
  'add_product': 'new_product',
  'alerts': 'suppliers',
  'sales_history': 'new_sale',
  'excel_export': 'excel',
  'profit_report': 'profits',
  'catalog_pdf': 'catalog',
};

/// Convierte lo guardado en funciones que la persona puede ver (sin repetir y en orden)
List<AppFunction> resolveShortcuts(List<String> saved, {required String role, required bool services}) {
  final allowed = {for (final f in findFunctions('', role: role, services: services)) f.id: f};
  final out = <AppFunction>[];
  for (final raw in saved) {
    final f = allowed[_legacyShortcutIds[raw] ?? raw];
    if (f != null && !out.contains(f) && out.length < kMaxShortcuts) out.add(f);
  }
  if (out.isEmpty) {
    for (final id in kDefaultShortcutIds) {
      final f = allowed[id];
      if (f != null) out.add(f);
    }
  }
  return out;
}
