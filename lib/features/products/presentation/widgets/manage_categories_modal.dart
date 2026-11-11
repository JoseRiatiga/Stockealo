import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import 'category_name_dialog.dart';
import '../../data/product_repository.dart';
import '../../models/category.dart';
import '../../../../core/design/app_dialog.dart';

class ManageCategoriesModal extends StatefulWidget {
  final String businessId;

  const ManageCategoriesModal({
    super.key,
    required this.businessId,
  });

  static Future<bool?> show(BuildContext context, String businessId) {
    return showModalBottomSheet<bool>(
      showDragHandle: false,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManageCategoriesModal(businessId: businessId),
    );
  }

  @override
  State<ManageCategoriesModal> createState() => _ManageCategoriesModalState();
}

class _ManageCategoriesModalState extends State<ManageCategoriesModal> {
  final _repository = ProductRepository();
  List<Category> _categories = [];
  Map<String, int> _productCounts = {};
  bool _isLoading = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    final cats = await _repository.getCategories(widget.businessId);
    final counts = <String, int>{};
    for (final c in cats) {
      counts[c.name] = await _repository.countProductsInCategory(c.name, widget.businessId);
    }

    if (!mounted) return;
    setState(() {
      _categories = cats;
      _productCounts = counts;
      _isLoading = false;
    });
  }

  List<String> get _names => [for (final c in _categories) c.name];

  Future<void> _showAddCategoryDialog() async {
    final result = await CategoryNameDialog.show(context, existing: _names);
    if (result == null || result.isEmpty) return;
    // Si ya existía con otra escritura, no se crea otra igual
    if (_names.any((n) => n.trim().toLowerCase() == result.toLowerCase())) return;
    await _repository.addCategory(result, widget.businessId);
    _hasChanges = true;
    await _loadCategories();
  }

  Future<void> _showEditCategoryDialog(Category category) async {
    final result = await CategoryNameDialog.show(context, existing: _names, initial: category.name);
    if (result == null || result.isEmpty || result == category.name) return;
    await _repository.updateCategory(
      id: category.id,
      businessId: widget.businessId,
      oldName: category.name,
      newName: result,
    );
    _hasChanges = true;
    await _loadCategories();
  }

  Future<void> _confirmDeleteCategory(Category category) async {
    final count = _productCounts[category.name] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
title: '¿Eliminar "${category.name}"?',
content: Text(
          count > 0
              ? 'Tiene $count ${count == 1 ? "producto" : "productos"}. Al eliminarla, '
                  '${count == 1 ? "pasa" : "pasan"} a la categoría "General".'
              : 'No tiene productos.',
        ),
actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ctx.colors.danger, foregroundColor: Colors.white),
            child: const Text('Eliminar'),
          ),
        ],
),
    );

    if (confirmed == true) {
      await _repository.deleteCategory(
        id: category.id,
        businessId: widget.businessId,
        categoryName: category.name,
      );
      _hasChanges = true;
      await _loadCategories();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Barra de arrastre
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.lineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Cabecera
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.category_outlined, color: context.colors.accent, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Gestionar Categorías',
                      style: TextStyle(
                        fontSize: AppText.sizeHeading,
                        fontWeight: FontWeight.bold,
                        color: context.colors.ink,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_outlined),
                  onPressed: () => Navigator.pop(context, _hasChanges),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: context.colors.line),

          // Contenido de la lista
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: context.colors.accent))
                : _categories.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.category_outlined, size: 48, color: context.colors.inkFaint),
                            const SizedBox(height: 12),
                            Text(
                              'No tienes categorías creadas aún',
                              style: TextStyle(fontSize: AppText.sizeBody, color: context.colors.inkMuted),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _categories.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final cat = _categories[index];
                          final count = _productCounts[cat.name] ?? 0;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: context.colors.paper,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.colors.line),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: context.colors.successSoft,
                                  child: Text(
                                    cat.name.isNotEmpty ? cat.name[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      color: context.colors.accent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: AppText.sizeBody,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cat.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: AppText.sizeBody,
                                          color: context.colors.ink,
                                        ),
                                      ),
                                      Text(
                                        '$count ${count == 1 ? "producto" : "productos"}',
                                        style: TextStyle(
                                          fontSize: AppText.sizeCaption,
                                          color: context.colors.inkMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.edit_outlined, size: 20, color: context.colors.info),
                                  tooltip: 'Editar nombre',
                                  onPressed: () => _showEditCategoryDialog(cat),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline_outlined, size: 20, color: context.colors.danger),
                                  tooltip: 'Eliminar categoría',
                                  onPressed: () => _confirmDeleteCategory(cat),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // Botón inferior para agregar categoría
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _showAddCategoryDialog,
                icon: const Icon(Icons.add_outlined, size: 20),
                label: const Text('Nueva categoría'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
