import 'package:flutter/widgets.dart';

/// Ancho máximo de las pantallas de lectura y ajustes (Pro, Legal, Ajustes,
/// Tienda). En la web y en tablets el contenido queda centrado en vez de
/// estirarse de borde a borde; en el celular no cambia nada.
class ContentWidth extends StatelessWidget {
  static const double max = 720;

  final Widget child;

  const ContentWidth({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: max), child: child),
    );
  }
}
