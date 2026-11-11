import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/theme_controller.dart';

/// Acceso rápido al lado de la campana: pasa de claro a oscuro (o al revés) y lo
/// guarda en el acto. Lo pidió el dueño (0.12.1); el interruptor «Modo oscuro»
/// sigue en Ajustes › Apariencia.
class ThemeModeButton extends StatelessWidget {
  final double size;

  const ThemeModeButton({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final dark = context.isDarkTheme;
        return IconButton(
          tooltip: dark ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro',
          onPressed: () => ThemeController.instance.toggleTheme(current: Theme.of(context).brightness),
          icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: size, color: context.colors.inkMuted),
        );
      },
    );
  }
}
