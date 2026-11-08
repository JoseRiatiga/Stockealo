import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/code_generator.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/image_helper.dart';
import '../../data/product_image_service.dart';
import '../../data/product_repository.dart';
import '../../../../core/utils/paste_image.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import 'barcode_scanner_screen.dart';
import '../widgets/manage_categories_modal.dart';
import '../widgets/product_image_view.dart';
import '../widgets/variant_editor.dart';
import '../../../../core/widgets/image_source_picker_modal.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../team/data/team_repository.dart';

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
  bool _isUploadingPhoto = false;

  /// Id fijo desde que se abre el formulario: la foto se guarda en la nube con él
  /// antes de guardar el producto
  late final String _productId = widget.productToEdit?.id ?? const Uuid().v4();
  void Function()? _stopPasteListener;
  String? _selectedCategory;
  List<Category> _categories = [];
  bool _isLoading = false;

  // Variantes (tallas y colores)
  bool _hasVariants = false;
  final _variants = VariantEditorController();

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
          _variants.load(p.variants);
        } else {
          _loadExistingVariants(p.id);
        }
      }
    }
    _variants.addListener(_updateTotalStockFromVariants);
    _updateTotalStockFromVariants();

    _checkRoleSecurity();
    _loadCategories();
    // En la web: pegar una imagen copiada (Ctrl+V) la pone como foto del producto
    _stopPasteListener = listenForPastedImages((image) {
      if (mounted && !_isUploadingPhoto) _uploadPhotoBytes(image.bytes, image.mimeType);
    });
  }

  Future<void> _loadExistingVariants(String productId) async {
    final list = await _repository.getVariantsForProduct(productId);
    if (list.isNotEmpty && mounted) {
      setState(() => _hasVariants = true);
      _variants.load(list);
    }
  }

  void _updateTotalStockFromVariants() {
    if (!_hasVariants) return;
    final total = '${_variants.totalStock}';
    if (_stockController.text != total) _stockController.text = total;
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
    _variants.dispose();
    _stopPasteListener?.call();
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
    // En la web no hay archivos locales: la foto elegida se sube de una vez a la nube
    // (antes quedaba un enlace temporal del navegador que se perdía al recargar)
    if (kIsWeb) {
      final picked = await ImageHelper.pickBytes(source);
      if (picked != null && mounted) await _uploadPhotoBytes(picked.bytes, picked.mimeType);
      return;
    }
    final path = source == ImageSource.camera
        ? await ImageHelper.pickFromCamera()
        : await ImageHelper.pickFromGallery();

    if (path != null && mounted) {
      setState(() {
        _photoPath = path;
      });
    }
  }

  String get _photoBusinessId => widget.productToEdit?.businessId ?? widget.businessId;

  Future<void> _uploadPhotoBytes(Uint8List bytes, String? mimeType) async {
    setState(() => _isUploadingPhoto = true);
    try {
      final url = await ProductImageService.instance.uploadBytes(
        businessId: _photoBusinessId,
        productId: _productId,
        bytes: bytes,
        mimeType: mimeType,
      );
      if (mounted) setState(() => _photoPath = url);
    } on ProductImageException catch (e) {
      if (mounted) AppToast.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _photoFromLink() async {
    final link = await showDialog<String>(context: context, builder: (_) => const _PhotoLinkDialog());
    if (link == null || !mounted) return;
    setState(() => _isUploadingPhoto = true);
    try {
      final url = await ProductImageService.instance.importFromUrl(
        businessId: _photoBusinessId,
        productId: _productId,
        url: link,
      );
      if (mounted) {
        setState(() => _photoPath = url);
        AppToast.showSuccess(context, 'Listo, trajimos la foto.');
      }
    } on ProductImageException catch (e) {
      if (mounted) AppToast.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _showImagePickerModal() {
    ImageSourcePickerModal.show(
      context,
      title: 'Foto del Producto',
      subtitle: 'Elige cómo capturar o subir la imagen del producto',
      hasExistingImage: _photoPath != null && _photoPath!.trim().isNotEmpty,
      onSelected: (source) => _pickImage(source),
      onLink: _photoFromLink,
      footerHint: canPasteImages
          ? 'También puedes copiar una imagen y pegarla aquí con Ctrl+V mientras editas el producto.'
          : null,
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
    final productId = _productId;
    final now = DateTime.now();

    List<ProductVariant> variants = [];
    if (_hasVariants) {
      final problem = _variants.validate();
      if (problem != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$problem O desactiva la opción de variantes.')),
        );
        setState(() => _isLoading = false);
        return;
      }
      variants = _variants.build(
        businessId: widget.productToEdit?.businessId ?? widget.businessId,
        productId: productId,
        now: now,
      );
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
                      onTap: _isUploadingPhoto ? null : _showImagePickerModal,
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
                          if (_isUploadingPhoto)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                ),
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

                  // 5. Stock y Variantes (tallas y colores)
                  Container(
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: _hasVariants ? context.colors.accent : context.colors.line,
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
                            color: _hasVariants ? context.colors.accent : context.colors.inkMuted,
                          ),
                          const SizedBox(width: 8),
                          const Flexible(
                            child: Text(
                              '¿Tiene variantes? (tallas, colores…)',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        'Actívalo si vendes este producto en varias tallas o colores, cada uno con sus existencias.',
                        style: TextStyle(fontSize: 11, color: context.colors.inkMuted),
                      ),
                      value: _hasVariants,
                      onChanged: (val) {
                        setState(() => _hasVariants = val);
                        if (val && _variants.combos.isEmpty) _variants.setSizes(['S', 'M', 'L', 'XL']);
                        _updateTotalStockFromVariants();
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
                    // Si SÍ tiene variantes: tallas, colores y existencias por combinación
                    VariantEditor(controller: _variants),
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
                          'Código único automático. Toca el escáner si tu producto ya tiene código de barras impreso.',
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

/// Pegar el enlace del producto o de la imagen
class _PhotoLinkDialog extends StatefulWidget {
  const _PhotoLinkDialog();

  @override
  State<_PhotoLinkDialog> createState() => _PhotoLinkDialogState();
}

class _PhotoLinkDialogState extends State<_PhotoLinkDialog> {
  final _link = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) setState(() => _link.text = text);
  }

  void _submit() {
    if (_link.text.trim().isEmpty) return;
    Navigator.pop(context, _link.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: const Text('Foto desde un enlace'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pega el enlace de la página del producto (Shein, Temu, Mercado Libre, Amazon…) '
              'o el de la imagen. Traemos la foto principal y la guardamos con tu producto.',
              style: TextStyle(fontSize: 13, height: 1.4, color: c.inkMuted),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _link,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Enlace',
                hintText: 'https://…',
                suffixIcon: IconButton(
                  tooltip: 'Pegar',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: _pasteFromClipboard,
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Usa fotos que tengas permiso de usar.',
              style: TextStyle(fontSize: 12, color: c.inkFaint),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _link.text.trim().isEmpty ? null : _submit,
          child: const Text('Traer foto'),
        ),
      ],
    );
  }
}
