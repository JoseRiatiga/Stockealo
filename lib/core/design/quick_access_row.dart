import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'pro_crown.dart';

/// Un acceso rápido: ícono, nombre y una línea de ayuda opcional
class QuickAccessItem {
  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback onTap;

  /// Función de Pro: muestra la corona
  final bool pro;

  const QuickAccessItem({required this.icon, required this.label, this.caption, required this.onTap, this.pro = false});
}

/// Accesos de una pestaña (0.12.0): todos se ven sin deslizar. Cuadrícula que se
/// acomoda al ancho: 2 por fila en celulares angostos, 3 en celulares y hasta 4
/// en pantallas grandes.
class QuickAccessRow extends StatelessWidget {
  final List<QuickAccessItem> items;

  const QuickAccessRow({super.key, required this.items});

  static int columnsFor(double width) => width < 340 ? 2 : (width < 600 ? 3 : 4);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth);
        const gap = AppSpace.sm;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: Material(
                  color: c.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    side: BorderSide(color: c.line),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    onTap: item.onTap,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(item.icon, size: 22, color: c.accent),
                              const Spacer(),
                              if (item.pro) const ProCrown(size: 16),
                            ],
                          ),
                          const SizedBox(height: AppSpace.sm),
                          Text(item.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(context, weight: FontWeight.w600)),
                          if (item.caption != null)
                            Text(item.caption!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption(context)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
