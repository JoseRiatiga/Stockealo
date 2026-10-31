import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';
import 'glass_surface.dart';

/// La acción principal de una pantalla ("+ Nueva venta", "+ Agregar producto"):
/// cristal teñido con el acento. Debe haber una sola por pantalla.
class PrimaryActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const PrimaryActionButton({
    super.key,
    required this.label,
    this.icon = Icons.add_rounded,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const radius = BorderRadius.all(Radius.circular(AppRadius.sheet));
    return Semantics(
      button: true,
      label: label,
      child: GlassSurface(
        tint: c.accent,
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onPressed!();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: c.onAccent),
                  const SizedBox(width: AppSpace.sm),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppText.fontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.onAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
