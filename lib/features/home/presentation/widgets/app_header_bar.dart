import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../dashboard/presentation/widgets/stocky_face_button.dart';

/// Encabezado de la versión de escritorio y web: título de la sección, buscador
/// (Ctrl K), Stocky, venta rápida, avisos y modo claro u oscuro
class AppHeaderBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onQuickSale;
  final VoidCallback? onSearchTap;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onStockyAssistantTap;
  final int alertCount;

  const AppHeaderBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onQuickSale,
    this.onSearchTap,
    this.onNotificationsTap,
    this.onStockyAssistantTap,
    this.alertCount = 0,
  });

  @override
  Size get preferredSize => const Size.fromHeight(72.0);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: c.ink),
                ),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 1, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.xl),

          // Buscador tipo paleta de comandos
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Semantics(
                  button: true,
                  label: 'Buscar producto, cliente o venta. Atajo Control K',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: onSearchTap,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(color: c.line),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, size: 19, color: c.inkMuted),
                          const SizedBox(width: AppSpace.sm + 2),
                          Expanded(
                            child: Text(
                              'Buscar producto, cliente o venta…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13.5, color: c.inkFaint),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: c.surfaceMuted,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: c.line),
                            ),
                            child: Text(
                              'Ctrl K',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.inkMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.lg),

          // Stocky (no en Ajustes)
          if (onStockyAssistantTap != null) ...[
            StockyFaceButton(showLabel: true, onTap: onStockyAssistantTap),
            const SizedBox(width: AppSpace.md),
          ],

          if (onQuickSale != null) ...[
            FilledButton.icon(
              onPressed: onQuickSale,
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
              label: const Text('Venta rápida'),
            ),
            const SizedBox(width: AppSpace.sm),
          ],

          // Avisos
          IconButton(
            tooltip: alertCount > 0 ? '$alertCount avisos' : 'Avisos',
            onPressed: onNotificationsTap,
            icon: Badge(
              isLabelVisible: alertCount > 0,
              backgroundColor: c.danger,
              label: Text(alertCount > 99 ? '99+' : '$alertCount'),
              child: Icon(Icons.notifications_outlined, size: 22, color: c.inkMuted),
            ),
          ),

          // Modo claro u oscuro (se guarda al instante)
          IconButton(
            tooltip: isDark ? 'Modo claro' : 'Modo oscuro',
            onPressed: () => ThemeController.instance.toggleTheme(),
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 22, color: c.inkMuted),
          ),
        ],
      ),
    );
  }
}
