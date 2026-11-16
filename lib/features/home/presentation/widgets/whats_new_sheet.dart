import 'package:flutter/material.dart';

import '../../../../core/app_version.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/theme/app_tokens.dart';
import 'where_things_moved_sheet.dart';

/// Una versión publicada y lo más importante que trajo
typedef WhatsNewEntry = ({String version, String title, List<String> items});

/// «Lo nuevo» (0.16.0, fase 7): sale UNA vez después de actualizar, con lo de esta
/// versión, a quien ya usaba la app. La lista completa está en Ajustes › Acerca de.
/// Va dentro de la app para que se vea también sin conexión y en la web.
class WhatsNewSheet {
  WhatsNewSheet._();

  /// Última versión cuyas novedades ya vio esta persona
  static const seenKey = 'whats_new_version';

  /// La más nueva primero. Al publicar, se agrega aquí la versión nueva.
  static const entries = <WhatsNewEntry>[
    (
      version: '0.16.2',
      title: 'Detalles de la tienda',
      items: [
        'En la plantilla Moda, las ofertas se filtran desde el lateral.',
        'Las opciones elegidas se leen bien, como los días del horario.',
        'El aviso de mayores de 18 aparece sobre la tienda difuminada.',
      ],
    ),
    (
      version: '0.16.1',
      title: 'Inicio más ordenado',
      items: [
        'Los accesos rápidos ahora están arriba, en una sola fila.',
        'La actividad del equipo se lee más clara: qué pasó, cuánto y quién.',
        '«Salir» en rojo y con confirmación, para no cerrar sesión por accidente.',
        'El botón de Google lleva su «G» de colores.',
      ],
    ),
    (
      version: '0.16.0',
      title: 'Tienda a tu estilo, metas y más seguridad',
      items: [
        'Metas de ventas del negocio y por empleado, con su gráfica.',
        'Cinco estilos para la tienda en línea, horario, destacados y estadísticas de visitas.',
        'Cupones para tu tienda: crea «BIENVENIDA10» y compártelo.',
        'Comparte en Instagram, código QR de la tienda y catálogo con promociones.',
        'Lotes con fecha de vencimiento y cambio al distribuidor.',
        'Plantillas de producto por tipo de negocio y marca en el producto.',
        'Bloquea la app con PIN o huella y entra con Google.',
        'En un agotado: «Recordarme si no llega» y «Ocultarlo en Vender».',
        'En el computador, arrastra o pega la foto del código en el lector.',
      ],
    ),
    (
      version: '0.15.1',
      title: 'Arreglo de roles',
      items: ['Los roles propios ahora suben a la nube.'],
    ),
    (
      version: '0.15.0',
      title: 'Equipo, planes y devoluciones',
      items: [
        'Devolución parcial: al inventario o como dañado, con caja y fiado al día.',
        'Permisos y límites de cada rol, también en la nube.',
        'Horario de acceso por persona (Pro Servicios).',
        'Descuento por línea en Vender y precio sugerido por margen.',
        'Las ventas en espera ya no se pierden al cerrar la app.',
        'Recordatorio para cerrar la caja y cierre del día por WhatsApp.',
        'Tiquete con NIT, dirección, teléfono y despedida propia.',
      ],
    ),
    (
      version: '0.14.0',
      title: 'Servicios para tu equipo',
      items: [
        'Servicios gratis hasta 3 empleados: catálogo, tablero, agenda y cobro.',
        'Comisiones, horarios, alquiler de silla y mensajes con Pro Servicios.',
        'Agenda de citas y reservas en línea desde la tienda.',
        'Taller, servicio técnico y lavandería con sus propios estados.',
        'Pago mixto, abono y productos que se cobran con el servicio.',
        'Historial del cliente: visitas, gasto y qué pide.',
      ],
    ),
    (
      version: '0.13.5',
      title: 'Avisos de pedidos',
      items: ['Te avisa al llegar un pedido de la tienda y muestra cuántos no has visto.'],
    ),
    (
      version: '0.13.4',
      title: 'Promociones y pedidos',
      items: [
        'Promociones (% y «lleva X, paga Y») en Vender, tiquete, tienda y reportes.',
        'Pedidos de la tienda con código T-0001 y «Por entregar».',
        'Funciona mejor sin conexión.',
      ],
    ),
    (
      version: '0.13.0',
      title: 'Stockealo con diseño nuevo',
      items: [
        'Menú que sigue el día de tu negocio y el color de tu negocio en toda la app.',
        'Caja con su propio lugar y su estado siempre a la vista.',
      ],
    ),
  ];

  /// Lo de una versión, si está en la lista
  static WhatsNewEntry? entryFor(String version) {
    for (final e in entries) {
      if (e.version == version) return e;
    }
    return null;
  }

  /// La primera vez con esta versión, solo si ya usaba la app antes
  static Future<void> showOnce(BuildContext context, {String version = kAppVersion}) async {
    final db = AppDatabase.instance;
    if (await db.getSetting(seenKey) == version) return;
    await db.setSetting(seenKey, version);
    final current = entryFor(version);
    if (current == null || !await WhereThingsMovedSheet.usedBefore(db)) return;
    if (context.mounted) await show(context, only: current);
  }

  /// Todas las novedades, o solo las de una versión
  static Future<void> show(BuildContext context, {WhatsNewEntry? only}) => AppSheet.show<void>(
        context: context,
        title: only != null ? 'Lo nuevo en Stockealo ${only.version}' : 'Novedades',
        subtitle: only?.title,
        builder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (only != null)
              _Items(only)
            else
              for (final e in entries) ...[
                Text('${e.version} · ${e.title}', style: AppText.body(ctx, weight: FontWeight.w600)),
                const SizedBox(height: AppSpace.xs),
                _Items(e),
                const SizedBox(height: AppSpace.md),
              ],
            const SizedBox(height: AppSpace.md),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
          ],
        ),
      );
}

class _Items extends StatelessWidget {
  final WhatsNewEntry entry;
  const _Items(this.entry);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in entry.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_circle_outline, size: 16, color: c.accent),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(item, style: AppText.small(context, color: c.ink))),
              ],
            ),
          ),
      ],
    );
  }
}
