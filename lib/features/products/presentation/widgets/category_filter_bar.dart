import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../models/category.dart';
import '../category_icons.dart';

/// Pastillas de categorías para filtrar el inventario
class CategoryFilterBar extends StatelessWidget {
  final List<Category> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  const CategoryFilterBar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final allCategories = ['Todos', ...categories.map((c) => c.name)];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: allCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (context, index) {
          final cat = allCategories[index];
          final isSelected = cat == selectedCategory;
          // Como los chips de Vender (0.16.7, hallazgo 15): el elegido en tinta con la
          // letra clara del tema. Antes, en modo oscuro, era letra blanca sobre fondo
          // blanco y «Todas» no se leía. Se muestra «Todas», como en el resto de la app
          // Con su ícono (0.16.8, #28); «Todas» lleva el suyo
          final icon = index == 0 ? CategoryIcon.all : CategoryIcon.of(categories[index - 1].icon);
          return ChoiceChip(
            avatar: icon == null ? null : Icon(icon, size: 18, color: isSelected ? c.surface : c.accent),
            label: Text(cat == 'Todos' ? 'Todas' : cat),
            selected: isSelected,
            showCheckmark: false,
            onSelected: (_) => onCategorySelected(cat),
            side: BorderSide(color: isSelected ? c.ink : c.line),
          );
        },
      ),
    );
  }
}
