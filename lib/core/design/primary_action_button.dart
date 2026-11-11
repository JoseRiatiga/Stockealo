import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';

/// La acción principal de una pantalla ("+ Nueva venta", "+ Agregar producto"):
/// botón sólido con el color del negocio. Debe haber una sola por pantalla.
class PrimaryActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const PrimaryActionButton({
    super.key,
    required this.label,
    this.icon = Icons.add_outlined,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: FilledButton.icon(
        onPressed: enabled
            ? () {
                HapticFeedback.selectionClick();
                onPressed!();
              }
            : null,
        icon: Icon(icon, size: 18),
        label: Text(label, style: AppText.body(context, weight: FontWeight.w600, color: enabled ? c.onAccent : c.inkFaint)),
      ),
    );
  }
}
