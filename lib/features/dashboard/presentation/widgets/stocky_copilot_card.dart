import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../auth/presentation/widgets/stocky_mascot.dart';

class StockyCopilotCard extends StatefulWidget {
  final int lowStockCount;
  final int outOfStockCount;
  final double totalSalesToday;
  final int salesCountToday;
  final double pendingFiados;
  final VoidCallback onNavigateToInventory;
  final VoidCallback onNavigateToSales;
  final VoidCallback? onRestockOrder;
  final VoidCallback? onOpenCatalog;
  final VoidCallback? onQuickSale;
  final VoidCallback? onNavigateToCustomers;

  const StockyCopilotCard({
    super.key,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.totalSalesToday,
    required this.salesCountToday,
    required this.pendingFiados,
    required this.onNavigateToInventory,
    required this.onNavigateToSales,
    this.onRestockOrder,
    this.onOpenCatalog,
    this.onQuickSale,
    this.onNavigateToCustomers,
  });

  @override
  State<StockyCopilotCard> createState() => _StockyCopilotCardState();
}

class _StockyCopilotCardState extends State<StockyCopilotCard> {
  StockyState _mascotState = StockyState.idle;
  String? _easterEggMessage;
  int _easterEggIndex = 0;

  static const List<String> _tips = [
    '¡Al 100% para registrar todas tus ventas hoy! 🚀',
    'Tip Pro: Presiona Ctrl + K en PC para buscar cualquier producto o cliente en 1 segundo.',
    'Recuerda que puedes descargar el catálogo en PDF o crear Historias 9:16 para WhatsApp e Instagram.',
    'Todo lo que registres se sincroniza en tiempo real con Supabase y tu equipo.',
  ];

  void _triggerEasterEgg() {
    HapticFeedback.mediumImpact();
    setState(() {
      _mascotState = StockyState.success;
      _easterEggMessage = _tips[_easterEggIndex % _tips.length];
      _easterEggIndex++;
    });

    Future.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) {
        setState(() {
          _mascotState = StockyState.idle;
          _easterEggMessage = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalAlerts = widget.lowStockCount + widget.outOfStockCount;

    // Colores Obsidian Violet Bento
    final bgColor = isDark ? const Color(0xFF131126) : Colors.white;
    final borderColor = isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0);
    final textMain = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    // Determinamos el diagnóstico del Copiloto
    String insightTitle;
    String insightText;
    List<Widget> actionButtons = [];

    if (_easterEggMessage != null) {
      insightTitle = 'Stocky dice:';
      insightText = _easterEggMessage!;
    } else if (totalAlerts > 0) {
      insightTitle = 'Inventario Crítico';
      insightText = 'Hay $totalAlerts productos agotados o con stock bajo. ¿Hacemos el pedido a proveedores para no detener ventas?';
      if (widget.onRestockOrder != null) {
        actionButtons.add(
          _buildActionButton(
            label: 'Pedido Proveedor',
            icon: Icons.local_shipping_outlined,
            color: const Color(0xFFDC2626),
            onPressed: widget.onRestockOrder!,
          ),
        );
      }
      actionButtons.add(
        _buildActionButton(
          label: 'Ver Stock',
          icon: Icons.inventory_2_outlined,
          color: const Color(0xFF2563EB),
          onPressed: widget.onNavigateToInventory,
        ),
      );
    } else if (widget.pendingFiados > 0) {
      insightTitle = 'Cuentas por Cobrar';
      insightText = 'Tienes ${CurrencyFormatter.format(widget.pendingFiados)} pendientes de cobro en fiados. ¿Revisamos la lista de clientes?';
      if (widget.onNavigateToCustomers != null) {
        actionButtons.add(
          _buildActionButton(
            label: 'Ver Clientes',
            icon: Icons.people_outline_rounded,
            color: const Color(0xFFD97706),
            onPressed: widget.onNavigateToCustomers!,
          ),
        );
      }
      if (widget.onQuickSale != null) {
        actionButtons.add(
          _buildActionButton(
            label: 'Vender',
            icon: Icons.add_shopping_cart_rounded,
            color: const Color(0xFF10B981),
            onPressed: widget.onQuickSale!,
          ),
        );
      }
    } else if (widget.salesCountToday > 0) {
      insightTitle = '¡Buen Ritmo Hoy!';
      insightText = 'Llevas ${widget.salesCountToday} ventas (${CurrencyFormatter.format(widget.totalSalesToday)}). Comparte historias para seguir impulsando el negocio.';
      if (widget.onOpenCatalog != null) {
        actionButtons.add(
          _buildActionButton(
            label: 'Historias Redes',
            icon: Icons.auto_awesome,
            color: const Color(0xFF8B5CF6),
            onPressed: widget.onOpenCatalog!,
          ),
        );
      }
      if (widget.onQuickSale != null) {
        actionButtons.add(
          _buildActionButton(
            label: 'Venta Rápida',
            icon: Icons.point_of_sale_rounded,
            color: const Color(0xFF10B981),
            onPressed: widget.onQuickSale!,
          ),
        );
      }
    } else {
      insightTitle = 'Copiloto Comercial Activo';
      insightText = 'Tu base de datos y catálogo están sincronizados. ¡Comencemos el turno con una venta rápida o creando historias!';
      if (widget.onQuickSale != null) {
        actionButtons.add(
          _buildActionButton(
            label: 'Venta Rápida',
            icon: Icons.add_shopping_cart_rounded,
            color: const Color(0xFF10B981),
            onPressed: widget.onQuickSale!,
          ),
        );
      }
      if (widget.onOpenCatalog != null) {
        actionButtons.add(
          _buildActionButton(
            label: 'Crear Historias',
            icon: Icons.auto_awesome,
            color: const Color(0xFF8B5CF6),
            onPressed: widget.onOpenCatalog!,
          ),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0xFF8B5CF6).withOpacity(0.04) : Colors.black.withOpacity(0.02),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Mascota Interactiva Stocky con Tooltip y Tap
          Tooltip(
            message: 'Toca a Stocky para recibir un consejo',
            child: GestureDetector(
              onTap: _triggerEasterEgg,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF1E1B4B).withOpacity(0.35) : const Color(0xFFECFDF5),
                  border: Border.all(
                    color: const Color(0xFF10B981).withOpacity(0.25),
                    width: 1.2,
                  ),
                ),
                child: StockyMascot(
                  size: 68,
                  state: _mascotState,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Contenido inteligente del Copiloto
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Badge con estado
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'STOCKY COPILOTO',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: Color(0xFF8B5CF6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          insightTitle,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: textMain,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),

                // Mensaje dinámico
                Text(
                  insightText,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: textMuted,
                  ),
                ),

                if (actionButtons.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: actionButtons,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
