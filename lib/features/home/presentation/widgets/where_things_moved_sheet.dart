import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/theme/app_tokens.dart';

/// «Dónde quedó cada cosa»: sale UNA vez por versión del menú a quien ya usaba la
/// app (no a quien se acaba de registrar). Se vuelve a ver en Ajustes › Acerca de.
///
/// Versión 2 del mapa = re-diseño 0.13.0: el menú sigue el día del negocio.
class WhereThingsMovedSheet {
  WhereThingsMovedSheet._();

  /// Lo marcó la actualización de la base a la versión 12 (quien ya usaba la 0.11)
  static const pendingKey = 'where_moved_pending';

  /// Última versión del mapa que esta persona ya vio
  static const seenKey = 'where_moved_version';
  static const mapVersion = '2';

  static const changes = <(IconData, String, String)>[
    (Icons.menu_outlined, 'Menú nuevo', 'Sigue el día: Inicio, Vender, Ventas, Caja, Productos, Stock, Clientes y proveedores, Reportes y Ajustes. En el celular se abre con ☰.'),
    (Icons.add_outlined, 'Nueva venta', 'Siempre arriba, en el encabezado, en todas las pantallas.'),
    (Icons.point_of_sale_outlined, 'Caja', 'Tiene su propio lugar en el menú, y su estado se ve arriba («Caja abierta desde 8:05»).'),
    (Icons.receipt_long_outlined, 'Ventas', 'Es lo vendido y las cotizaciones.'),
    (Icons.layers_outlined, 'Stock', 'Lugar nuevo: lo que falta, el proveedor que pasa hoy y «Pedir al proveedor».'),
    (Icons.people_alt_outlined, 'Clientes y proveedores', 'Fiados, abonos y proveedores, juntos.'),
    (Icons.storefront_outlined, 'Tienda en línea', 'Tiene su propio lugar en el menú.'),
    (Icons.search_outlined, 'Buscador', 'Arriba (o Ctrl K): encuentra productos, clientes y funciones.'),
  ];

  /// La primera vez con esta versión del menú, solo si ya usaba la app antes
  static Future<void> showOnce(BuildContext context) async {
    final db = AppDatabase.instance;
    if (await db.getSetting(seenKey) == mapVersion) return;
    await db.setSetting(seenKey, mapVersion);
    if (!await _usedBefore(db)) return;
    if (context.mounted) await show(context);
  }

  /// Ya usaba la app: vio el aviso de la 0.12 o tiene un negocio de hace más de un día
  static Future<bool> _usedBefore(AppDatabase db) async {
    if (await db.getSetting(pendingKey) != null) return true;
    try {
      final d = await db.database;
      final cutoff = DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
      final rows = await d.rawQuery('SELECT COUNT(*) AS n FROM businesses WHERE created_at < ?', [cutoff]);
      return ((rows.first['n'] as int?) ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> show(BuildContext context) => AppSheet.show<void>(
        context: context,
        title: 'Dónde quedó cada cosa',
        subtitle: 'Ordenamos Stockealo para que siga el día de tu negocio.',
        builder: (ctx) {
          final c = ctx.colors;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (icon, title, where) in changes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.sm - 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.tile)),
                        child: Icon(icon, size: 18, color: c.accent),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: AppText.body(ctx, weight: FontWeight.w600)),
                            Text(where, style: AppText.small(ctx)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpace.lg),
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
            ],
          );
        },
      );
}
