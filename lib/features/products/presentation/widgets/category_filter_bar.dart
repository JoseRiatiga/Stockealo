import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../models/category.dart';

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
          return ChoiceChip(
            label: Text(cat),
            selected: isSelected,
            showCheckmark: false,
            onSelected: (_) => onCategorySelected(cat),
            labelStyle: TextStyle(
              color: isSelected ? c.onAccent : c.ink,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 13.5,
            ),
            side: BorderSide(color: isSelected ? c.accent : c.line),
          );
        },
      ),
    );
  }
}
