import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'pro_crown.dart';

/// Un acceso rápido: ícono, nombre y una línea de ayuda opcional
class QuickAccessItem {
  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback onTap;

  /// Número en la esquina (por ejemplo, pedidos sin ver); 0 no se muestra
  final int badge;

  /// Función de Pro: muestra la corona
  final bool pro;

  const QuickAccessItem({
    required this.icon,
    required this.label,
    this.caption,
    required this.onTap,
    this.pro = false,
    this.badge = 0,
  });
}

/// Accesos de una pestaña (0.12.0): todos se ven sin deslizar. Cuadrícula que se
/// acomoda al ancho: 2 por fila en celulares (para que «Promociones» no se parta),
/// 3 en tabletas angostas y hasta 4 en pantallas grandes. Los de una fila miden lo
/// mismo, y si en 2 columnas sobra uno, ocupa todo el ancho (0.16.3).
class QuickAccessRow extends StatelessWidget {
  final List<QuickAccessItem> items;

  const QuickAccessRow({super.key, required this.items});

  static int columnsFor(double width) => width < 420 ? 2 : (width < 600 ? 3 : 4);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth);
        const gap = AppSpace.sm;
        final rows = <List<QuickAccessItem>>[
          for (var i = 0; i < items.length; i += columns) items.sublist(i, (i + columns).clamp(0, items.length)),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < rows[r].length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      Expanded(child: _QuickAccessTile(item: rows[r][i])),
                    ],
                    // La última fila incompleta con 3 o 4 columnas deja su hueco (no se estira)
                    if (columns > 2 && rows[r].length < columns)
                      for (var i = rows[r].length; i < columns; i++) ...[
                        const SizedBox(width: gap),
                        const Expanded(child: SizedBox()),
                      ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _QuickAccessTile extends StatelessWidget {
  final QuickAccessItem item;

  const _QuickAccessTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
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
                  Badge(
                    isLabelVisible: item.badge > 0,
                    label: Text(item.badge > 99 ? '99+' : '${item.badge}'),
                    child: Icon(item.icon, size: 22, color: c.accent),
                  ),
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
    );
  }
}
