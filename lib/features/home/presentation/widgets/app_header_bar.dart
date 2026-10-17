import 'package:flutter/material.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../dashboard/presentation/widgets/stocky_face_button.dart';

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
  Size get preferredSize => const Size.fromHeight(68.0);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0E1D) : Colors.white;
    final borderColor = isDark ? const Color(0xFF262046) : const Color(0xFFE2E8F0);

    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: borderColor, width: 1.2)),
      ),
      child: Row(
        children: [
          // Título de la sección
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(width: 28),

          // Barra de Búsqueda Flotante tipo Command Palette (Bento / Nuxt)
          Expanded(
            child: InkWell(
              onTap: onSearchTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF181530) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF2B254E) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Buscar producto, cliente o venta...',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF231E44) : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Ctrl K',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),

          // Botón Asistente Stocky (solo en módulos activos, no en Ajustes)
          if (onStockyAssistantTap != null) ...[
            StockyFaceButton(
              showLabel: true,
              onTap: onStockyAssistantTap,
            ),
            const SizedBox(width: 12),
          ],

          // Botón Acción Rápida + Vender
          if (onQuickSale != null)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onPressed: onQuickSale,
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 16, color: Colors.white),
              label: const Text(
                'Venta Rápida',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
            ),
          const SizedBox(width: 12),

          // Botón Notificaciones / Alertas con Badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, size: 20),
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                onPressed: onNotificationsTap,
                splashRadius: 20,
              ),
              if (alertCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDC2626),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$alertCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // Alternador de Modo Oscuro / Claro
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 20,
            ),
            color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF475569),
            tooltip: isDark ? 'Modo Claro' : 'Modo Oscuro',
            onPressed: () => ThemeController.instance.toggleTheme(),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}
