import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_tokens.dart';

/// Contador «− 2 +» en una cajita con borde (0.16.3). Lo usan el carrito de Vender
/// y el conteo por billetes al cerrar la caja, para que se vean iguales.
///
/// [onRemove] en null deja el «−» apagado. Con [removeDeletes] el «−» se vuelve
/// la caneca (quitar la línea), como en el carrito cuando queda 1.
///
/// [QtyStepper.field] (0.18.7) es el mismo contador con el número escribible, para
/// cantidades grandes (las existencias de cada talla al crear un producto): − y +
/// suman de a uno, dejarlos presionados sigue sumando cada vez más rápido, y en el
/// computador las flechas ↑ y ↓ del teclado también suben y bajan.
class QtyStepper extends StatelessWidget {
  final int value;
  final VoidCallback? onRemove;
  final VoidCallback? onAdd;
  final bool removeDeletes;

  /// Qué se cuenta, para los lectores de pantalla («Billetes de $ 50.000»)
  final String? label;

  /// Solo en [QtyStepper.field]: el número que se escribe
  final TextEditingController? controller;

  const QtyStepper({
    super.key,
    required this.value,
    this.onRemove,
    this.onAdd,
    this.removeDeletes = false,
    this.label,
  }) : controller = null;

  /// Número escribible con − y +; nunca baja de 0
  const QtyStepper.field({super.key, required TextEditingController this.controller, this.label})
      : value = 0,
        onRemove = null,
        onAdd = null,
        removeDeletes = false;

  /// Lo que se suma o resta (sin bajar de 0)
  static void step(TextEditingController controller, int delta) {
    final now = int.tryParse(controller.text.trim()) ?? 0;
    final next = (now + delta).clamp(0, 999999);
    if (next == now && controller.text.trim().isNotEmpty) return;
    controller.value = TextEditingValue(
      text: '$next',
      selection: TextSelection.collapsed(offset: '$next'.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final field = controller;
    return Semantics(
      label: label,
      value: field == null ? '$value' : null,
      container: true,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(AppRadius.tile)),
        child: field == null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _button(removeDeletes ? Icons.delete_outline : Icons.remove_outlined, removeDeletes ? 'Quitar' : 'Quitar uno', onRemove),
                  SizedBox(
                    width: 26,
                    child: Text('$value', textAlign: TextAlign.center, style: AppText.body(context, weight: FontWeight.w700)),
                  ),
                  _button(Icons.add_outlined, 'Agregar uno', onAdd),
                ],
              )
            : ValueListenableBuilder<TextEditingValue>(
                valueListenable: field,
                builder: (context, v, _) {
                  final n = int.tryParse(v.text.trim()) ?? 0;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HoldButton(icon: Icons.remove_outlined, tooltip: 'Restar uno', onStep: n > 0 ? () => step(field, -1) : null),
                      SizedBox(
                        width: 52,
                        child: CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.arrowUp): () => step(field, 1),
                            const SingleActivator(LogicalKeyboardKey.arrowDown): () => step(field, -1),
                          },
                          child: TextField(
                            controller: field,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                            textAlign: TextAlign.center,
                            style: AppText.body(context, weight: FontWeight.w700),
                            onTap: () => field.selection = TextSelection(baseOffset: 0, extentOffset: field.text.length),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '0',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ),
                      _HoldButton(icon: Icons.add_outlined, tooltip: 'Sumar uno', onStep: () => step(field, 1)),
                    ],
                  );
                },
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

/// Botón − o + que, dejado presionado, sigue sumando cada vez más rápido
class _HoldButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onStep;

  const _HoldButton({required this.icon, required this.tooltip, required this.onStep});

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  Timer? _timer;
  int _ticks = 0;

  void _start() {
    if (widget.onStep == null) return;
    _ticks = 0;
    widget.onStep!();
    _next();
  }

  void _next() {
    // Primero despacio y luego más rápido: 300 ms, 150 ms y desde la décima, 60 ms
    final wait = _ticks == 0 ? 300 : (_ticks < 10 ? 150 : 60);
    _timer = Timer(Duration(milliseconds: wait), () {
      if (!mounted || widget.onStep == null) return _stop();
      widget.onStep!();
      _ticks++;
      _next();
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = widget.onStep != null;
    // Sin el tooltip del IconButton: en el celular también usa «dejar presionado»
    // y le quitaría el gesto a la repetición
    return Semantics(
      button: true,
      enabled: on,
      label: widget.tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onStep,
          child: GestureDetector(
            onLongPressStart: (_) => _start(),
            onLongPressEnd: (_) => _stop(),
            onLongPressCancel: _stop,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(widget.icon, size: 18, color: on ? c.ink : c.inkMuted.withValues(alpha: .4)),
            ),
          ),
        ),
      ),
    );
  }
}
