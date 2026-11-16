import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Contador «− 2 +» en una cajita con borde (0.16.3). Lo usan el carrito de Vender
/// y el conteo por billetes al cerrar la caja, para que se vean iguales.
///
/// [onRemove] en null deja el «−» apagado. Con [removeDeletes] el «−» se vuelve
/// la caneca (quitar la línea), como en el carrito cuando queda 1.
class QtyStepper extends StatelessWidget {
  final int value;
  final VoidCallback? onRemove;
  final VoidCallback? onAdd;
  final bool removeDeletes;

  /// Qué se cuenta, para los lectores de pantalla («Billetes de $ 50.000»)
  final String? label;

  const QtyStepper({
    super.key,
    required this.value,
    this.onRemove,
    this.onAdd,
    this.removeDeletes = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: label,
      value: '$value',
      container: true,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(AppRadius.tile)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _button(removeDeletes ? Icons.delete_outline : Icons.remove_outlined, removeDeletes ? 'Quitar' : 'Quitar uno', onRemove),
            SizedBox(
              width: 26,
              child: Text('$value', textAlign: TextAlign.center, style: AppText.body(context, weight: FontWeight.w700)),
            ),
            _button(Icons.add_outlined, 'Agregar uno', onAdd),
          ],
        ),
      ),
    );
  }

  Widget _button(IconData icon, String tooltip, VoidCallback? onTap) => SizedBox(
        width: 34,
        height: 34,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          iconSize: 17,
          onPressed: onTap,
          icon: Icon(icon),
        ),
      );
}
