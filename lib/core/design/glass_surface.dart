import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_controller.dart';

/// Decide si se dibuja el cristal. Se apaga (barras sólidas) si el usuario lo pidió en
/// Ajustes o si el sistema pide alto contraste o reducir animaciones.
bool useGlassEffect(BuildContext context) {
  final media = MediaQuery.maybeOf(context);
  if (ThemeController.instance.reduceTransparency) return false;
  if (media != null && (media.highContrast || media.disableAnimations)) return false;
  return true;
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
        ? tint!.withOpacity(glass ? 0.84 : 1)
        : (glass ? c.glass : c.surface);
    final borderColor = tint != null ? Colors.white.withOpacity(0.28) : c.line;

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
