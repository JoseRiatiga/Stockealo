import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// Un acceso rápido: ícono, nombre y una línea de ayuda opcional
class QuickAccessItem {
  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback onTap;

  const QuickAccessItem({required this.icon, required this.label, this.caption, required this.onTap});
}

/// Fila de accesos rápidos de V1 (Inventario: catálogo, Excel, pedido; Ventas:
/// clientes, cotizaciones, Excel). Tarjetas iguales que se desplazan si no caben.
class QuickAccessRow extends StatelessWidget {
  final List<QuickAccessItem> items;

  const QuickAccessRow({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (context, i) {
          final item = items[i];
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: Row(
                  children: [
                    Icon(item.icon, size: 22, color: c.accent),
                    const SizedBox(width: AppSpace.sm),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
                        if (item.caption != null)
                          Text(item.caption!, style: TextStyle(fontSize: 12, color: c.inkMuted)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
