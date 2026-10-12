import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/utils/code_generator.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/image_helper.dart';
import '../../data/product_repository.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import 'barcode_scanner_screen.dart';
import '../widgets/manage_categories_modal.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? productToEdit;
  final String businessId;

  const ProductFormScreen({
    super.key,
    this.productToEdit,
    required this.businessId,
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
    }

    _loadCategories();
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
    Navigator.pop(context); // Cerrar selector modal
    final path = source == ImageSource.camera
        ? await ImageHelper.pickFromCamera()
        : await ImageHelper.pickFromGallery();

    if (path != null) {
      setState(() {
        _photoPath = path;
      });
    }
  }

  void _showImagePickerModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Foto del Producto',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFECFDF5),
                  child: Icon(Icons.camera_alt, color: Color(0xFF059669)),
                ),
                title: const Text('Tomar foto con la cámara'),
                onTap: () => _pickImage(ImageSource.camera),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEFF6FF),
                  child: Icon(Icons.photo_library, color: Color(0xFF2563EB)),
                ),
                title: const Text('Elegir de la galería'),
                onTap: () => _pickImage(ImageSource.gallery),
              ),
              if (_photoPath != null)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFEE2E2),
                    child: Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                  ),
                  title: const Text('Eliminar foto actual'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _photoPath = null;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
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
    final stock = int.tryParse(_stockController.text.trim()) ?? 0;
    final minStock = int.tryParse(_minStockController.text.trim()) ?? 5;

    final now = DateTime.now();

    final product = Product(
      id: widget.productToEdit?.id ?? const Uuid().v4(),
      businessId: widget.productToEdit?.businessId ?? widget.businessId,
      code: _codeController.text.trim(),
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      category: _selectedCategory!,
      purchasePrice: purchasePrice,
      salePrice: salePrice,
      stock: stock,
      minStock: minStock,
      photoPath: _photoPath,
      createdAt: widget.productToEdit?.createdAt ?? now,
      updatedAt: now,
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
          : Form(
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
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: _photoPath != null && File(_photoPath!).existsSync()
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(19),
                                    child: Image.file(
                                      File(_photoPath!),
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_a_photo_outlined, size: 40, color: Color(0xFF059669)),
                                      SizedBox(height: 6),
                                      Text(
                                        'Agregar Foto',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF64748B),
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
                                _photoPath != null ? Icons.edit : Icons.camera_alt,
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
                              backgroundColor: const Color(0xFFECFDF5),
                              foregroundColor: const Color(0xFF059669),
                              padding: const EdgeInsets.all(14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: _openManageCategoriesModal,
                            icon: const Icon(Icons.tune, size: 20),
                            tooltip: 'Gestionar categorías',
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFF1F5F9),
                              foregroundColor: const Color(0xFF475569),
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
                        color: margin >= 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: margin >= 0 ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
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
                                color: margin >= 0 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Ganancia unitaria: ${CurrencyFormatter.format(profit)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: margin >= 0 ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Margen: ${margin.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: margin >= 0 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // 5. Stock y Stock Mínimo (etiquetas legibles sin truncar)
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
                  ),
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
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
