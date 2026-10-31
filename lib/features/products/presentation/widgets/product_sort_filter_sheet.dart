import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

/// Hoja para elegir el orden y el filtro de stock del catálogo.
class ProductSortFilterSheet {
  static const _sorts = {
    'name_asc': 'Nombre, de la A a la Z',
    'name_desc': 'Nombre, de la Z a la A',
    'stock_asc': 'Menos stock primero',
    'stock_desc': 'Más stock primero',
    'price_desc': 'Precio más alto primero',
    'price_asc': 'Precio más bajo primero',
    'margin_desc': 'Mayor ganancia primero',
  };

  static const _stockFilters = {
    'all': 'Todos',
    'low_stock': 'Stock bajo',
    'out_of_stock': 'Agotados',
  };

  /// Devuelve la selección aplicada, o null si el usuario cerró sin aplicar.
  static Future<({String sort, String stockFilter})?> show(
    BuildContext context, {
    required String sort,
    required String stockFilter,
  }) async {
    String tempSort = sort;
    String tempStockFilter = stockFilter;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final c = modalCtx.colors;
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Orden y filtros', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
                        ),
                        TextButton(
                          onPressed: () => setModalState(() {
                            tempSort = 'name_asc';
                            tempStockFilter = 'all';
                          }),
                          child: const Text('Restablecer'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    Text('Mostrar', style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                    const SizedBox(height: AppSpace.sm),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: c.accent,
                        selectedForegroundColor: c.onAccent,
                        side: BorderSide(color: c.line),
                      ),
                      segments: [
                        for (final e in _stockFilters.entries) ButtonSegment(value: e.key, label: Text(e.value)),
                      ],
                      selected: {tempStockFilter},
                      onSelectionChanged: (s) => setModalState(() => tempStockFilter = s.first),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    Text('Ordenar por', style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                    const SizedBox(height: AppSpace.xs),
                    for (final e in _sorts.entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.value),
                        trailing: tempSort == e.key ? Icon(Icons.check_rounded, color: c.accent) : null,
                        onTap: () => setModalState(() => tempSort = e.key),
                      ),
                    const SizedBox(height: AppSpace.lg),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Aplicar'),
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
