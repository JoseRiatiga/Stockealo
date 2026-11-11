import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// Decide si se dibuja el cristal. Desde el re-diseño siempre es no (barras sólidas).
bool useGlassEffect(BuildContext context) {
  // Re-diseño 0.13.0: el diseño aprobado no usa cristal ni desenfoque. Encabezado,
  // barras y botones son superficies sólidas con borde fino.
  return false;
}

/// Superficie de cristal para lo que flota sobre el contenido: encabezado, barra de
/// pestañas, botón principal. El contenido (listas, cifras) va siempre en tarjetas sólidas.
///
/// [tint] tiñe el cristal (el acento para el botón principal o la pestaña activa);
/// sin tinte usa el cristal claro u oscuro del tema.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final Color? tint;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  const GlassSurface({
    super.key,
    required this.child,
    this.tint,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.sheet)),
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final glass = useGlassEffect(context);
    // Sin cristal, el fondo es opaco para no perder legibilidad
    final background = tint != null
        ? tint!.withValues(alpha: glass ? 0.84 : 1)
        : (glass ? c.glass : c.surface);
    final borderColor = tint != null ? Colors.white.withValues(alpha: 0.28) : c.line;

    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor),
      ),
      child: padding != null ? Padding(padding: padding!, child: child) : child,
    );

    if (!glass) return content;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: content,
      ),
    );
  }
}
