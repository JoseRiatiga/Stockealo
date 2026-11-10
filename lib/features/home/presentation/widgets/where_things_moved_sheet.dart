import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_tokens.dart';

/// «Dónde quedó cada cosa» (0.12.0): cada función vive en un solo lugar y varias
/// cambiaron de sitio. Sale una vez al abrir la versión; se vuelve a ver en
/// Ajustes › Acerca de.
class WhereThingsMovedSheet {
  WhereThingsMovedSheet._();

  /// Lo marca la actualización de la base a la versión 12 (solo quien ya usaba la app)
  static const pendingKey = 'where_moved_pending';

  static const changes = <(IconData, String, String)>[
    (Icons.point_of_sale_rounded, 'Nueva venta', 'Ventas. Ya no está en el encabezado ni en Inicio.'),
    (Icons.point_of_sale_outlined, 'Caja', 'Ventas › Caja. Se enciende en Ajustes › Módulos.'),
    (Icons.insights_rounded, 'Ganancias', 'Pestaña Reportes, junto a Descargar Excel.'),
    (Icons.upload_file_outlined, 'Importar desde Excel', 'Inventario. Ahora te guía paso a paso.'),
    (Icons.move_to_inbox_outlined, 'Pedido a proveedor', 'Inventario › Proveedores y entradas.'),
    (Icons.groups_2_outlined, 'Equipo y actividad', 'Ajustes › Tu negocio.'),
    (Icons.widgets_outlined, 'Módulos', 'Ajustes › Tu negocio › Módulos: todo lo que ofrece Stockealo.'),
    (Icons.dark_mode_outlined, 'Modo oscuro', 'Ajustes › Apariencia.'),
    (Icons.dashboard_outlined, 'Inicio', 'Ahora es el resumen del día. Toca cada cifra para ir a su lugar.'),
    (Icons.search_rounded, 'Buscador', 'También encuentra funciones: escribe «caja» o «proveedores».'),
  ];

  /// La primera vez después de actualizar
  static Future<void> showOnce(BuildContext context) async {
    final db = AppDatabase.instance;
    if (await db.getSetting(pendingKey) != '1') return;
    await db.setSetting(pendingKey, '0');
    if (context.mounted) await show(context);
  }

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (ctx) {
          final c = ctx.colors;
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
            children: [
              Text('Dónde quedó cada cosa', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: AppSpace.xs),
              Text('Ordenamos la app: cada cosa tiene un solo lugar.', style: TextStyle(color: c.inkMuted)),
              const SizedBox(height: AppSpace.md),
              for (final (icon, title, where) in changes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 20, color: c.accent),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: '$title: ', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                          TextSpan(text: where, style: TextStyle(color: c.inkMuted)),
                        ])),
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
