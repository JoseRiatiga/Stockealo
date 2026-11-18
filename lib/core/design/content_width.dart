import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Ancho máximo de las pantallas de lectura y ajustes (Pro, Legal, Ajustes,
/// Tienda). En la web y en tablets el contenido queda centrado en vez de
/// estirarse de borde a borde; en el celular no cambia nada.
///
/// Para una lista que llena la pantalla se usa [ContentListView]: así la rueda del
/// mouse y la barra de desplazamiento funcionan en todo el ancho (0.16.6, hallazgo 61).
/// [ContentWidth] queda para lo que no hace scroll (pestañas, encabezados) y las hojas.
class ContentWidth extends StatelessWidget {
  static const double max = 720;

  final Widget child;

  /// Ancho máximo; [max] salvo pantallas que van junto a otras más anchas
  final double maxWidth;

  const ContentWidth({super.key, required this.child, this.maxWidth = max});

  /// Lo que sobra a cada lado para que el contenido mida como mucho [limit]
  static double gutter(double width, [double limit = max]) => math.max(0, (width - limit) / 2);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

/// Lista a todo el ancho con el contenido centrado en [ContentWidth.max]: el
/// relleno de los costados es parte de la lista, así que se puede hacer scroll
/// con el puntero en cualquier lado y la barra queda en el borde de la pantalla.
class ContentListView extends StatelessWidget {
  final EdgeInsets padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final List<Widget> children;

  /// Ancho máximo del contenido
  final double maxWidth;

  /// Para listas largas: se arman los elementos a medida que se ven
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;

  const ContentListView({
    super.key,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.physics,
    this.maxWidth = ContentWidth.max,
    required this.children,
  })  : itemCount = null,
        itemBuilder = null,
        separatorBuilder = null;

  const ContentListView.separated({
    super.key,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.physics,
    this.maxWidth = ContentWidth.max,
    required int this.itemCount,
    required IndexedWidgetBuilder this.itemBuilder,
    required IndexedWidgetBuilder this.separatorBuilder,
  }) : children = const [];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final side = ContentWidth.gutter(box.maxWidth, maxWidth);
        final pad = padding.copyWith(left: padding.left + side, right: padding.right + side);
        if (itemBuilder != null) {
          return ListView.separated(
            controller: controller,
            physics: physics,
            padding: pad,
            itemCount: itemCount!,
            itemBuilder: itemBuilder!,
            separatorBuilder: separatorBuilder!,
          );
        }
        return ListView(controller: controller, physics: physics, padding: pad, children: children);
      },
    );
  }
}
