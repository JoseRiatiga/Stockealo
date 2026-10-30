import 'package:flutter/material.dart';

/// Hoja para elegir el orden y el filtro de stock del catálogo.
class ProductSortFilterSheet {
  /// Devuelve la selección aplicada, o null si el usuario cerró sin aplicar.
  static Future<({String sort, String stockFilter})?> show(
    BuildContext context, {
    required String sort,
    required String stockFilter,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String tempSort = sort;
    String tempStockFilter = stockFilter;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final cardBg = isDark ? const Color(0xFF131126) : Colors.white;
            final textMain = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
            final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
            final borderColor = isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0);

            Widget buildSortItem(String value, String label, IconData icon) {
              final isSelected = tempSort == value;
              return InkWell(
                onTap: () => setModalState(() => tempSort = value),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (const Color(0xFF8B5CF6).withOpacity(0.12))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF8B5CF6) : borderColor,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: isSelected ? const Color(0xFF8B5CF6) : textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? const Color(0xFF8B5CF6) : textMain,
                          ),
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF8B5CF6)),
                    ],
                  ),
                ),
              );
            }

            Widget buildStockFilterChip(String value, String label, Color color) {
              final isSelected = tempStockFilter == value;
              return Expanded(
                child: InkWell(
                  onTap: () => setModalState(() => tempStockFilter = value),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? color : borderColor,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? color : textMuted,
                      ),
                    ),
                  ),
                ),
              );
            }

            return Container(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(ctx).padding.bottom + 20,
              ),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF475569) : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filtros y Ordenamiento',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: textMain,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              tempSort = 'name_asc';
                              tempStockFilter = 'all';
                            });
                          },
                          child: const Text('Restablecer', style: TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ESTADO DEL STOCK',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textMuted),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        buildStockFilterChip('all', 'Todos', const Color(0xFF8B5CF6)),
                        const SizedBox(width: 8),
                        buildStockFilterChip('low_stock', 'Bajo Stock', const Color(0xFFD97706)),
                        const SizedBox(width: 8),
                        buildStockFilterChip('out_of_stock', 'Agotados', const Color(0xFFDC2626)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'ORDENAR POR',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textMuted),
                    ),
                    const SizedBox(height: 8),
                    buildSortItem('name_asc', 'Alfabético (A - Z) • Predeterminado', Icons.sort_by_alpha_rounded),
                    buildSortItem('name_desc', 'Alfabético (Z - A)', Icons.sort_by_alpha_rounded),
                    buildSortItem('stock_desc', 'Mayor stock disponible', Icons.inventory_2_rounded),
                    buildSortItem('stock_asc', 'Menor stock (Por agotarse)', Icons.production_quantity_limits_rounded),
                    buildSortItem('price_desc', 'Mayor precio de venta', Icons.arrow_upward_rounded),
                    buildSortItem('price_asc', 'Menor precio de venta', Icons.arrow_downward_rounded),
                    buildSortItem('margin_desc', 'Mayor margen de ganancia', Icons.trending_up_rounded),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Aplicar Filtros', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return applied == true ? (sort: tempSort, stockFilter: tempStockFilter) : null;
  }
}
