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
      version: '0.16.8',
      title: 'Íconos, fiado en el pago mixto y más',
      items: [
        'Cada categoría tiene su ícono en la tienda, Vender y Productos; tócalo en Categorías para cambiarlo.',
        'En el pago mixto puedes dejar una parte fiada: se suma a lo que debe el cliente.',
        'Reportes resta los gastos que registras en Caja de la ganancia neta.',
        'Los valores se ven con puntos de mil mientras escribes.',
        'Las fechas de Promociones y Ventas se eligen con atajos como «Esta semana» o «Este mes».',
        'Ventas y Reportes muestran el nombre actual de cada producto; el recibo, el del día de la venta.',
      ],
    ),
    (
      version: '0.16.7',
      title: 'Todo más ordenado',
      items: [
        'En el computador, el detalle y la edición de productos, la entrada de mercancía, Promociones y Equipo se abren a la derecha con el menú a la vista.',
        'Stock es una lista con lo agotado y lo bajo arriba, y «Ajustar» en cada producto.',
        'El stock ya no se cambia en Editar producto: se ajusta y queda en el historial.',
        'Registrar un abono usa los mismos medios de pago que Vender, con atajos de valor.',
        'Equipo tiene un solo botón «Invitar» y los permisos del Dueño muestran un candado.',
        'Los textos ya no se cortan al achicar la ventana y Escape cierra el menú.',
      ],
    ),
    (
      version: '0.16.6',
      title: 'Vender más fácil y la hora de tu negocio',
      items: [
        'En Vender tienes a mano las ventas en espera y las cotizaciones, también en el celular.',
        '«Cobrar» queda siempre a la vista y los descuentos avisan si pasan el valor o dejan pérdida.',
        '«Nueva venta» guarda la cuenta que tenías en espera y abre una vacía.',
        'El buscador encuentra clientes y más funciones, y Ctrl K funciona en toda la app.',
        'La hora de recibos, caja y reportes es la del país de tu negocio; en EE. UU. y México eliges la zona.',
        'El comprobante, el vendedor y el descuento de cada venta se ven en todos tus equipos.',
        'En el computador puedes hacer scroll en toda la pantalla.',
      ],
    ),
    (
      version: '0.16.5',
      title: 'Devoluciones en orden',
      items: [
        'Las devoluciones siguen en su propia tarjeta en Ventas después de recargar la app.',
        'Ya no se puede devolver más de lo que se vendió.',
      ],
    ),
    (
      version: '0.16.4',
      title: 'La caja y las cuentas, al día',
      items: [
        'La caja muestra bien la hora en que se abrió y no deja sacar más plata de la que hay.',
        'Si te equivocas en una entrada o salida de caja, tócala para anularla.',
        'Al devolver algo de un pago mixto, eliges si devuelves en efectivo o por otro medio.',
        'Ventas muestra una tarjeta por venta, y Reportes, Caja y Stocky dan las mismas cifras.',
        'Lo que cambias en una pantalla (productos, abonos, mercancía) se ve al instante en las demás.',
      ],
    ),
    (
      version: '0.16.3',
      title: 'Arreglos y detalles',
      items: [
        'Reportes cuenta bien las ventas: una venta con varios productos es una sola.',
        'En el celular, Stocky ya no tapa el botón de cobrar ni «Publicar mi tienda».',
        'Contar la caja por billetes es más claro y no dice «Faltan» antes de contar.',
        'El nombre del negocio y los textos ya no se cortan, y la hora sale igual en toda la app.',
      ],
    ),
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
