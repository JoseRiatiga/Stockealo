import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Pestañas para filtrar una lista («Todos · Con deuda · Al día»), del diseño aprobado:
/// una franja gris y la opción elegida en blanco con sombra suave. Se desplaza de lado
/// si no cabe (celular). Re-diseño 0.13.4, segunda pasada.
class FilterTabs<T> extends StatelessWidget {
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Si no caben: false (por defecto) se desplazan de lado; true pasan a otra línea
  final bool wrap;

  const FilterTabs({super.key, required this.options, required this.value, required this.onChanged, this.wrap = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tabs = Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: c.line),
        ),
        child: Wrap(
          spacing: 0,
          runSpacing: 2,
          children: [
            for (final e in options.entries)
              Semantics(
                selected: e.key == value,
                button: true,
                child: Material(
                  color: e.key == value ? c.surface : Colors.transparent,
                  elevation: e.key == value ? 1 : 0,
                  shadowColor: c.ink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.control - 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.control - 3),
                    onTap: () => onChanged(e.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm - 2),
                      child: Text(
                        e.value,
                        style: AppText.small(
                          context,
                          weight: FontWeight.w700,
                          color: e.key == value ? c.ink : c.inkMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    return wrap ? tabs : SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs);
  }
}
