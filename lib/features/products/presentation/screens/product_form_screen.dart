import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/utils/code_generator.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/image_helper.dart';
import '../../data/product_repository.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import 'barcode_scanner_screen.dart';
import '../widgets/manage_categories_modal.dart';
import '../widgets/product_image_view.dart';
import '../../../../core/widgets/image_source_picker_modal.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../team/data/team_repository.dart';

class _VariantDraft {
  String id;
  String attributeValue;
  int stock;
  String? skuOrBarcode;
  TextEditingController valueController;
  TextEditingController stockController;
  TextEditingController barcodeController;

  _VariantDraft({
    String? id,
    required this.attributeValue,
    this.stock = 0,
    this.skuOrBarcode,
  })  : id = id ?? const Uuid().v4(),
        valueController = TextEditingController(text: attributeValue),
        stockController = TextEditingController(text: stock > 0 ? stock.toString() : '0'),
        barcodeController = TextEditingController(text: skuOrBarcode ?? '');

  void dispose() {
    valueController.dispose();
    stockController.dispose();
    barcodeController.dispose();
  }
}

class ProductFormScreen extends StatefulWidget {
  final Product? productToEdit;
  final String businessId;
  final String? userRole;

  const ProductFormScreen({
    super.key,
    this.productToEdit,
    required this.businessId,
    this.userRole,
  });

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repository = ProductRepository();

  late TextEditingController _codeController;
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _purchasePriceController;
  late TextEditingController _salePriceController;
  late TextEditingController _stockController;
  late TextEditingController _minStockController;

  String? _photoPath;
  String? _selectedCategory;
  List<Category> _categories = [];
  bool _isLoading = false;

  // Variantes (Tallas / Colores / Presentaciones)
  bool _hasVariants = false;
  String _variantAttributeName = 'Talla';
  final List<_VariantDraft> _variantDrafts = [];

  bool get isEditing => widget.productToEdit != null;

  @override
  void initState() {
    super.initState();
    final p = widget.productToEdit;

    _codeController = TextEditingController(text: p?.code ?? CodeGenerator.generateUniqueCode());
    _nameController = TextEditingController(text: p?.name ?? '');
    _descriptionController = TextEditingController(text: p?.description ?? '');
    _purchasePriceController = TextEditingController(
      text: p != null && p.purchasePrice > 0 ? p.purchasePrice.toStringAsFixed(0) : '',
    );
    _salePriceController = TextEditingController(
      text: p != null && p.salePrice > 0 ? p.salePrice.toStringAsFixed(0) : '',
    );
    _stockController = TextEditingController(text: p?.stock.toString() ?? '0');
    _minStockController = TextEditingController(text: p?.minStock.toString() ?? '5');
    _photoPath = p?.photoPath;
    if (p != null) {
      _selectedCategory = p.category;
      _hasVariants = p.hasVariants;
      if (p.hasVariants) {
        if (p.variants.isNotEmpty) {
          _variantAttributeName = p.variants.first.attributeName;
          for (final v in p.variants) {
            final draft = _VariantDraft(
              id: v.id,
              attributeValue: v.attributeValue,
              stock: v.stock,
              skuOrBarcode: v.skuOrBarcode,
            );
            draft.stockController.addListener(_updateTotalStockFromVariants);
            _variantDrafts.add(draft);
          }
        } else {
          _loadExistingVariants(p.id);
        }
      }
    }

    _checkRoleSecurity();
    _loadCategories();
  }

  Future<void> _loadExistingVariants(String productId) async {
    final list = await _repository.getVariantsForProduct(productId);
    if (list.isNotEmpty && mounted) {
      setState(() {
        _hasVariants = true;
        _variantAttributeName = list.first.attributeName;
        _variantDrafts.clear();
        for (final v in list) {
          final draft = _VariantDraft(
            id: v.id,
            attributeValue: v.attributeValue,
            stock: v.stock,
            skuOrBarcode: v.skuOrBarcode,
          );
          draft.stockController.addListener(_updateTotalStockFromVariants);
          _variantDrafts.add(draft);
        }
        _updateTotalStockFromVariants();
      });
    }
  }

  void _updateTotalStockFromVariants() {
    final total = _variantDrafts.fold(0, (sum, d) {
      final s = int.tryParse(d.stockController.text.trim()) ?? 0;
      return sum + s;
    });
    _stockController.text = total.toString();
  }

  void _addVariantDraft([String initialValue = '']) {
    setState(() {
      final draft = _VariantDraft(attributeValue: initialValue, stock: 0);
      draft.stockController.addListener(_updateTotalStockFromVariants);
      _variantDrafts.add(draft);
      _updateTotalStockFromVariants();
    });
  }

  void _removeVariantDraft(int index) {
    setState(() {
      _variantDrafts[index].dispose();
      _variantDrafts.removeAt(index);
      _updateTotalStockFromVariants();
    });
  }

  void _applyClothingPreset() {
    setState(() {
      _variantAttributeName = 'Talla';
      for (final d in _variantDrafts) {
        d.dispose();
      }
      _variantDrafts.clear();
      for (final s in ['S', 'M', 'L', 'XL']) {
        final d = _VariantDraft(attributeValue: s, stock: 0);
        d.stockController.addListener(_updateTotalStockFromVariants);
        _variantDrafts.add(d);
      }
      _updateTotalStockFromVariants();
    });
  }

  void _applyShoePreset() {
    setState(() {
      _variantAttributeName = 'Talla';
      for (final d in _variantDrafts) {
        d.dispose();
      }
      _variantDrafts.clear();
      for (final s in ['36', '37', '38', '39', '40']) {
        final d = _VariantDraft(attributeValue: s, stock: 0);
        d.stockController.addListener(_updateTotalStockFromVariants);
        _variantDrafts.add(d);
      }
      _updateTotalStockFromVariants();
    });
  }

  Future<void> _checkRoleSecurity() async {
    final user = AuthRepository.instance.currentUser;
    if (user != null) {
      final role = widget.userRole ??
          await TeamRepository.instance.getUserRoleInBusiness(
            businessId: widget.businessId,
            userId: user.id,
            userEmail: user.email,
          );
      if (role == 'CASHIER' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Acceso restringido: Solo administradores pueden gestionar productos'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _purchasePriceController.dispose();
    _salePriceController.dispose();
    _stockController.dispose();
    _minStockController.dispose();
    for (final d in _variantDrafts) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final cats = await _repository.getCategories(widget.businessId);
    setState(() {
      _categories = cats;
      if (_categories.isNotEmpty) {
        if (_selectedCategory == null || !_categories.any((c) => c.name == _selectedCategory)) {
          _selectedCategory = _categories.first.name;
        }
      } else {
        _selectedCategory = null;
      }
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final path = source == ImageSource.camera
        ? await ImageHelper.pickFromCamera()
        : await ImageHelper.pickFromGallery();

    if (path != null && mounted) {
      setState(() {
        _photoPath = path;
      });
    }
  }

  void _showImagePickerModal() {
    ImageSourcePickerModal.show(
      context,
      title: 'Foto del Producto',
      subtitle: 'Elige cómo capturar o subir la imagen del producto',
      hasExistingImage: _photoPath != null && _photoPath!.trim().isNotEmpty,
      onSelected: (source) => _pickImage(source),
      onRemove: () {
        setState(() {
          _photoPath = null;
        });
      },
    );
  }

  Future<void> _scanBarcode() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (scannedCode != null && scannedCode.isNotEmpty) {
      setState(() {
        _codeController.text = scannedCode;
      });
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final catController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva Categoría'),
        content: TextField(
          controller: catController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ej. Accesorios, Ferretería...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (catController.text.trim().isNotEmpty) {
                Navigator.pop(ctx, catController.text.trim());
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _repository.addCategory(result, widget.businessId);
      await _loadCategories();
      setState(() {
        _selectedCategory = result;
      });
    }
  }

  Future<void> _openManageCategoriesModal() async {
    final changed = await ManageCategoriesModal.show(context, widget.businessId);
    if (changed == true || mounted) {
      await _loadCategories();
      setState(() {
        if (!_categories.any((c) => c.name == _selectedCategory)) {
          _selectedCategory = _categories.isNotEmpty ? _categories.first.name : null;
        }
      });
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategory == null || _selectedCategory!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor crea o selecciona una categoría pulsando el botón +'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final purchasePrice = double.tryParse(_purchasePriceController.text.trim()) ?? 0.0;
    final salePrice = double.tryParse(_salePriceController.text.trim()) ?? 0.0;
    final minStock = int.tryParse(_minStockController.text.trim()) ?? 5;
    final productId = widget.productToEdit?.id ?? const Uuid().v4();
    final now = DateTime.now();

    List<ProductVariant> variants = [];
    if (_hasVariants) {
      if (_variantDrafts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor agrega al menos una talla o desactiva la opción de variantes.'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      for (final d in _variantDrafts) {
        final val = d.valueController.text.trim();
        if (val.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Todas las variantes deben tener un valor o talla (ej: S, M, L).'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() => _isLoading = false);
          return;
        }
        final s = int.tryParse(d.stockController.text.trim()) ?? 0;
        final barcode = d.barcodeController.text.trim();
        variants.add(ProductVariant(
          id: d.id,
          businessId: widget.productToEdit?.businessId ?? widget.businessId,
          productId: productId,
          attributeName: _variantAttributeName,
          attributeValue: val,
          skuOrBarcode: barcode.isNotEmpty ? barcode : null,
          stock: s,
          createdAt: now,
          updatedAt: now,
        ));
      }
    }

    final totalStock = _hasVariants
        ? variants.fold(0, (sum, v) => sum + v.stock)
        : (int.tryParse(_stockController.text.trim()) ?? 0);

    final product = Product(
      id: productId,
      businessId: widget.productToEdit?.businessId ?? widget.businessId,
      code: _codeController.text.trim(),
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      category: _selectedCategory!,
      purchasePrice: purchasePrice,
      salePrice: salePrice,
      stock: totalStock,
      minStock: minStock,
      photoPath: _photoPath,
      createdAt: widget.productToEdit?.createdAt ?? now,
      updatedAt: now,
      hasVariants: _hasVariants,
      variants: variants,
    );

    try {
      if (isEditing) {
        await _repository.updateProduct(product);
      } else {
        await _repository.insertProduct(product);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing ? 'Producto actualizado con éxito' : '¡Producto guardado exitosamente!',
            ),
            backgroundColor: const Color(0xFF059669),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final purchasePrice = double.tryParse(_purchasePriceController.text) ?? 0.0;
    final salePrice = double.tryParse(_salePriceController.text) ?? 0.0;
    final profit = salePrice - purchasePrice;
    final margin = salePrice > 0 ? (profit / salePrice) * 100 : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Producto' : 'Nuevo Producto'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                children: [
                  // 1. Selector de Foto
                  Center(
                    child: GestureDetector(
                      onTap: _showImagePickerModal,
                      child: Stack(
                        children: [
                          Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E293B) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: (_photoPath != null && _photoPath!.trim().isNotEmpty)
                                ? ProductImageView(
                                    imagePath: _photoPath,
                                    width: 130,
                                    height: 130,
                                    borderRadius: BorderRadius.circular(19),
                                    iconSize: 40,
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.add_a_photo_outlined, size: 40, color: Color(0xFF059669)),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Agregar Foto',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFF059669),
                              child: Icon(
                                (_photoPath != null && _photoPath!.trim().isNotEmpty) ? Icons.edit : Icons.camera_alt,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 2. Nombre del Producto (campo principal)
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del Producto *',
                      hintText: 'Ej. Café Colombiano 500g, Llavero Acrílico...',
                      prefixIcon: Icon(Icons.shopping_bag_outlined, color: Color(0xFF64748B)),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa el nombre del producto' : null,
                  ),
                  const SizedBox(height: 16),

                  // 4. Categoría con botón "+" al vuelo
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Categoría *',
                                prefixIcon: Icon(Icons.category_outlined, color: Color(0xFF64748B)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _categories.any((c) => c.name == _selectedCategory)
                                      ? _selectedCategory
                                      : null,
                                  hint: Text(
                                    _categories.isEmpty
                                        ? 'Sin categorías (Toca + para crear)'
                                        : 'Selecciona una categoría',
                                    style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                                  ),
                                  isDense: true,
                                  isExpanded: true,
                                  items: _categories.map((c) {
                                    return DropdownMenuItem<String>(
                                      value: c.name,
                                      child: Text(c.name),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedCategory = val;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: _showAddCategoryDialog,
                            icon: const Icon(Icons.add),
                            tooltip: 'Crear Categoría',
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFF064E3B)
                                  : const Color(0xFFECFDF5),
                              foregroundColor: Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF059669),
                              padding: const EdgeInsets.all(14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: _openManageCategoriesModal,
                            icon: const Icon(Icons.tune, size: 20),
                            tooltip: 'Gestionar categorías',
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF1F5F9),
                              foregroundColor: Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFFCBD5E1)
                                  : const Color(0xFF475569),
                              padding: const EdgeInsets.all(14),
                            ),
                          ),
                        ],
                      ),
                      if (_categories.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 6, left: 4),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 14, color: Color(0xFF059669)),
                              SizedBox(width: 4),
                              Text(
                                'Aún no tienes categorías. Toca + para crear una.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF059669),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 5. Precios de Compra y Venta
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _purchasePriceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Precio de Compra',
                            prefixText: r'$ ',
                            hintText: '0',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _salePriceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Precio de Venta *',
                            prefixText: r'$ ',
                            hintText: '0',
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Requerido';
                            final val = double.tryParse(v.trim());
                            if (val == null || val <= 0) return 'Mayor a 0';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Tarjeta dinámica de Ganancia y Margen %
                  if (salePrice > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: margin >= 0
                            ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5))
                            : (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF7F1D1D).withOpacity(0.4) : const Color(0xFFFEE2E2)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: margin >= 0
                              ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF059669) : const Color(0xFFA7F3D0))
                              : (Theme.of(context).brightness == Brightness.dark ? const Color(0xFFEF4444) : const Color(0xFFFECACA)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                margin >= 0 ? Icons.trending_up : Icons.trending_down,
                                size: 18,
                                color: margin >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Ganancia unitaria: ${CurrencyFormatter.format(profit)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: margin >= 0
                                      ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46))
                                      : (Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B)),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Margen: ${margin.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: margin >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // 5. Stock y Variantes (Tallas / Colores / Presentaciones)
                  Container(
                    decoration: BoxDecoration(
                      color: _hasVariants
                          ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1B4B).withOpacity(0.4) : const Color(0xFFF5F3FF))
                          : (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF131127) : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _hasVariants ? const Color(0xFF8B5CF6) : (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0)),
                        width: _hasVariants ? 1.5 : 1,
                      ),
                    ),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      title: Row(
                        children: [
                          Icon(
                            Icons.style_outlined,
                            size: 20,
                            color: _hasVariants ? const Color(0xFF8B5CF6) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '¿Tiene variantes? (Tallas, colores...)',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      subtitle: const Text(
                        'Actívalo si vendes este producto en varias tallas o modelos con stock independiente.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                      value: _hasVariants,
                      activeColor: const Color(0xFF8B5CF6),
                      onChanged: (val) {
                        setState(() {
                          _hasVariants = val;
                          if (_hasVariants && _variantDrafts.isEmpty) {
                            _applyClothingPreset();
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Si NO tiene variantes: Stock simple tradicional
                  if (!_hasVariants)
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _stockController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: isEditing ? 'Stock Actual *' : 'Stock Inicial *',
                              hintText: '0',
                              prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20, color: Color(0xFF64748B)),
                              prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Requerido';
                              final val = int.tryParse(v.trim());
                              if (val == null || val < 0) return 'Mínimo 0';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _minStockController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Stock Mínimo',
                              hintText: '5',
                              prefixIcon: Icon(Icons.notifications_active_outlined, size: 20, color: Color(0xFF64748B)),
                              prefixIconConstraints: BoxConstraints(minWidth: 38, minHeight: 38),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Requerido';
                              final val = int.tryParse(v.trim());
                              if (val == null || val < 0) return 'Mínimo 0';
                              return null;
                            },
                          ),
                        ),
                      ],
                    )
                  else ...[
                    // Si SÍ tiene variantes: Gestor de Tallas / Colores
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF131127) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF26214A) : const Color(0xFFDDD6FE),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.tune, size: 16, color: Color(0xFF8B5CF6)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Variantes por: $_variantAttributeName',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF8B5CF6)),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    label: const Text('Ropa', style: TextStyle(fontSize: 11)),
                                    onPressed: _applyClothingPreset,
                                  ),
                                  const SizedBox(width: 4),
                                  ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    label: const Text('Calzado', style: TextStyle(fontSize: 11)),
                                    onPressed: _applyShoePreset,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          ..._variantDrafts.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final draft = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF1A1633)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? const Color(0xFF26214A)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: draft.valueController,
                                      decoration: InputDecoration(
                                        labelText: _variantAttributeName,
                                        hintText: 'Ej. S, M, 38...',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: draft.stockController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Stock',
                                        hintText: '0',
                                        isDense: true,
                                      ),
                                      onChanged: (_) => _updateTotalStockFromVariants(),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.qr_code_scanner, size: 18, color: Color(0xFF059669)),
                                    tooltip: 'Escanear código de barras para esta talla',
                                    onPressed: () async {
                                      final code = await Navigator.push<String>(
                                        context,
                                        MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
                                      );
                                      if (code != null && code.isNotEmpty) {
                                        setState(() {
                                          draft.barcodeController.text = code;
                                        });
                                      }
                                    },
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                                    onPressed: () => _removeVariantDraft(idx),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _addVariantDraft(''),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Agregar Talla', style: TextStyle(fontSize: 12)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Total: ${_stockController.text} unids',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF059669)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _minStockController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Alerta de Stock Mínimo Global',
                        hintText: '5',
                        prefixIcon: Icon(Icons.notifications_active_outlined, size: 20, color: Color(0xFF64748B)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // 6. Código de Barras / SKU (Asignación automática y escáner claro)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _codeController,
                        decoration: InputDecoration(
                          labelText: 'Código de Barras / SKU',
                          hintText: 'Ej. STK-12345',
                          prefixIcon: const Icon(Icons.qr_code_2, color: Color(0xFF64748B)),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF059669)),
                                tooltip: 'Escanear código de barras con la cámara',
                                onPressed: _scanBarcode,
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8), size: 20),
                                tooltip: 'Generar otro código automático',
                                onPressed: () {
                                  setState(() {
                                    _codeController.text = CodeGenerator.generateUniqueCode();
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 4),
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text(
                          '💡 Código único automático. Toca el escáner si tu producto ya tiene código de barras impreso.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 7. Descripción opcional
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Descripción / Notas (Opcional)',
                      hintText: 'Detalles adicionales, proveedor, ubicación...',
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Botón Guardar
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _saveProduct,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        isEditing ? 'Guardar Cambios' : 'Crear Producto',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
                ],
              ),
            ),
            ),
            ),
    );
  }
}
