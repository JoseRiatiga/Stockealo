import 'package:flutter/material.dart';
import '../../../core/permissions/permissions.dart';

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

  /// Permiso que necesita (0.15.0); null = lo ve cualquiera
  final Perm? perm;

  /// Solo con Pro Servicios
  final bool needsServices;

  const AppFunction({
    required this.id,
    required this.title,
    required this.where,
    required this.tab,
    required this.icon,
    required this.keywords,
    this.perm,
    this.needsServices = false,
  });
}

const kAppFunctions = <AppFunction>[
  AppFunction(id: 'new_sale', title: 'Nueva venta', where: 'Vender', tab: 6, icon: Icons.point_of_sale_outlined,
      keywords: ['venta', 'vender', 'cobrar', 'factura']),
  // Ventas en espera, a mano en Vender (0.16.6, hallazgo 47)
  AppFunction(id: 'held_sales', title: 'Ventas en espera', where: 'Vender › En espera', tab: 6, icon: Icons.pause_circle_outline,
      keywords: ['espera', 'pausa', 'despues', 'guardar venta', 'pendiente', 'retomar']),
  AppFunction(id: 'sales_list', title: 'Ventas registradas', where: 'Ventas', tab: 2, icon: Icons.receipt_long_outlined,
      keywords: ['historial', 'ventas', 'recibo', 'comprobante', 'ticket', 'vendido']),
  AppFunction(id: 'returns', title: 'Devoluciones', where: 'Ventas › abre la venta › Devolver', tab: 2, icon: Icons.undo_outlined,
      keywords: ['devolucion', 'devolver', 'cambio', 'reembolso', 'garantia', 'danado']),
  AppFunction(id: 'void_sale', title: 'Anular venta', where: 'Ventas › abre la venta › Anular', tab: 2, icon: Icons.block_outlined,
      keywords: ['anular', 'cancelar venta', 'borrar venta', 'equivocada'], perm: Perm.voidSale),
  AppFunction(id: 'customers', title: 'Clientes y fiados', where: 'Clientes y proveedores', tab: 9, icon: Icons.people_alt_outlined,
      keywords: ['cliente', 'fiado', 'deuda', 'abono', 'debe']),
  AppFunction(id: 'quotes', title: 'Cotizaciones', where: 'Ventas › Cotizaciones', tab: 2, icon: Icons.request_quote_outlined,
      keywords: ['cotizacion', 'proforma', 'presupuesto']),
  AppFunction(id: 'cash', title: 'Caja', where: 'Caja', tab: 7, icon: Icons.point_of_sale_outlined,
      keywords: ['caja', 'arqueo', 'efectivo', 'cierre', 'base', 'turno', 'abrir caja']),
  AppFunction(id: 'close_cash', title: 'Cerrar caja', where: 'Caja › Cerrar caja', tab: 7, icon: Icons.lock_clock_outlined,
      keywords: ['cerrar caja', 'cierre', 'cuadre', 'cuadrar', 'arqueo', 'fin del dia', 'caja']),
  AppFunction(id: 'cash_in', title: 'Entrada de dinero', where: 'Caja › Entrada', tab: 7, icon: Icons.south_west_outlined,
      keywords: ['entrada', 'ingreso', 'meter plata', 'dinero', 'plata', 'caja', 'sencillo'], perm: Perm.cashMoves),
  AppFunction(id: 'cash_out', title: 'Salida de dinero', where: 'Caja › Salida', tab: 7, icon: Icons.north_east_outlined,
      keywords: ['salida', 'retiro', 'gasto', 'sacar plata', 'dinero', 'plata', 'caja', 'pago'], perm: Perm.cashMoves),
  AppFunction(id: 'new_product', title: 'Nuevo producto', where: 'Productos', tab: 1, icon: Icons.add_box_outlined,
      keywords: ['producto', 'agregar', 'nuevo', 'inventario', 'crear']),
  AppFunction(id: 'import_excel', title: 'Importar desde Excel', where: 'Productos › Importar desde Excel', tab: 1, icon: Icons.upload_file_outlined,
      keywords: ['importar', 'excel', 'cargar', 'subir', 'plantilla'], perm: Perm.importExcel),
  AppFunction(id: 'suppliers', title: 'Proveedores y entradas', where: 'Clientes y proveedores › Proveedores', tab: 9,
      icon: Icons.move_to_inbox_outlined, keywords: ['proveedor', 'pedido', 'entrada', 'mercancia', 'compra', 'pagar'],
      perm: Perm.suppliers),
  AppFunction(id: 'stock', title: 'Stock por reponer', where: 'Stock', tab: 8, icon: Icons.layers_outlined,
      keywords: ['stock', 'reponer', 'agotado', 'falta', 'minimo', 'pedir', 'faltante']),
  // 0.17.0: conteo de inventario (bloque C) y pedido sugerido (bloque D)
  AppFunction(id: 'stock_count', title: 'Contar inventario', where: 'Stock › Contar inventario', tab: 8,
      icon: Icons.fact_check_outlined, keywords: ['contar', 'conteo', 'inventario', 'fisico', 'diferencia', 'cuadrar'],
      perm: Perm.stockAdjust),
  AppFunction(id: 'restock_order', title: 'Pedido al proveedor', where: 'Stock › Pedir al proveedor', tab: 8,
      icon: Icons.local_shipping_outlined, keywords: ['pedido', 'proveedor', 'sugerido', 'pedir', 'reponer'],
      perm: Perm.productsEdit),
  AppFunction(id: 'catalog', title: 'Catálogo', where: 'Productos › Catálogo', tab: 1, icon: Icons.menu_book_outlined,
      keywords: ['catalogo', 'pdf', 'historia', 'compartir']),
  AppFunction(id: 'promotions', title: 'Promociones', where: 'Productos › Promociones', tab: 1, icon: Icons.local_offer_outlined,
      keywords: ['promocion', 'descuento', 'oferta', '2x1', '3x2', 'rebaja', 'black friday'], perm: Perm.promotions),
  AppFunction(id: 'online_store', title: 'Tienda en línea', where: 'Tienda en línea', tab: 10, icon: Icons.storefront_outlined,
      keywords: ['tienda', 'online', 'web', 'carrito', 'pedido en linea', 'cupon', 'cupones', 'codigo de descuento'],
      perm: Perm.store),
  AppFunction(id: 'profits', title: 'Ganancias', where: 'Reportes › Ganancias', tab: 4, icon: Icons.insights_outlined,
      keywords: ['ganancia', 'perdida', 'utilidad', 'reporte', 'margen'], perm: Perm.profits),
  AppFunction(id: 'goals', title: 'Metas de ventas', where: 'Reportes › Metas', tab: 4, icon: Icons.flag_outlined,
      keywords: ['meta', 'metas', 'objetivo', 'semanal', 'mensual', 'avance', 'vendedor'], perm: Perm.reportsSales),
  AppFunction(id: 'excel', title: 'Descargar Excel', where: 'Reportes › Descargar Excel', tab: 4, icon: Icons.table_chart_outlined,
      keywords: ['excel', 'descargar', 'exportar', 'reporte', 'xlsx'], perm: Perm.exportExcel),
  AppFunction(id: 'services', title: 'Servicios', where: 'Servicios', tab: 5, icon: Icons.view_kanban_outlined,
      keywords: ['servicio', 'tablero', 'lavado', 'turno', 'cola', 'asistencia', 'comision', 'placa'], needsServices: true),
  AppFunction(id: 'agenda', title: 'Agenda de citas', where: 'Servicios › Agenda', tab: 5, icon: Icons.event_outlined,
      keywords: ['agenda', 'cita', 'citas', 'reserva', 'turno', 'calendario'], needsServices: true),
  AppFunction(id: 'team', title: 'Equipo', where: 'Ajustes › Equipo', tab: 3, icon: Icons.groups_2_outlined,
      keywords: ['equipo', 'empleado', 'cajero', 'invitar']),
  AppFunction(id: 'roles', title: 'Roles y permisos', where: 'Ajustes › Equipo › Roles', tab: 3, icon: Icons.tune_outlined,
      keywords: ['rol', 'roles', 'permiso', 'permisos', 'acceso', 'vendedor', 'bodega'], perm: Perm.team),
  AppFunction(id: 'modules', title: 'Módulos', where: 'Ajustes › Módulos', tab: 3, icon: Icons.widgets_outlined,
      keywords: ['modulo', 'activar', 'encender', 'funciones']),
  // Sedes (0.18.0)
  AppFunction(id: 'branches', title: 'Sedes', where: 'Ajustes › Módulos › Sedes', tab: 3, icon: Icons.place_outlined,
      keywords: ['sede', 'sedes', 'local', 'sucursal', 'locales', 'punto'], perm: Perm.modules),
  AppFunction(id: 'pro', title: 'Stockealo Pro', where: 'Ajustes › Stockealo Pro', tab: 3, icon: Icons.workspace_premium_outlined,
      keywords: ['pro', 'plan', 'codigo', 'canjear', 'suscripcion', 'cupon pro']),
  AppFunction(id: 'appearance', title: 'Apariencia', where: 'Ajustes › Apariencia', tab: 3, icon: Icons.palette_outlined,
      keywords: ['oscuro', 'claro', 'color', 'tema', 'letra', 'apariencia']),
  AppFunction(id: 'cloud', title: 'Nube y respaldo', where: 'Ajustes › Nube y respaldo', tab: 3, icon: Icons.cloud_outlined,
      keywords: ['nube', 'respaldo', 'copia', 'sincronizar', 'backup']),
];

/// Minúsculas y sin tildes, para buscar sin importar cómo se escribió
String foldText(String s) {
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
  final q = foldText(query.trim());
  return [
    for (final f in kAppFunctions)
      if ((f.perm == null || Permissions.can(role, f.perm!)) &&
          (!f.needsServices || services) &&
          (q.isEmpty || foldText(f.title).contains(q) || f.keywords.any((k) => k.contains(q) || (k.length >= 4 && q.contains(k)))))
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
