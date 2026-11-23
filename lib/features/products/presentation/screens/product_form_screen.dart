import '../../../suppliers/presentation/widgets/supplier_picker.dart';
import '../../../../core/utils/money_input.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import '../../models/price_tier.dart';
import '../widgets/price_tiers_editor.dart';
import '../../../pro/data/pro_service.dart';
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
import '../widgets/category_name_dialog.dart';
import '../widgets/manage_categories_modal.dart';
import '../widgets/product_image_view.dart';
import '../widgets/variant_editor.dart';
import '../../../../core/widgets/image_source_picker_modal.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../team/data/team_repository.dart';
import '../../../../core/codes/code_reader.dart';
import '../../../../core/codes/barcode_check.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/permissions/permissions.dart';
import '../../data/pricing.dart';
import '../widgets/lots_widgets.dart';
import '../../data/product_templates.dart';
import '../../../store/presentation/widgets/store_qr_sheet.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? productToEdit;
  final String businessId;
  final String? userRole;

  /// Desde una entrada de mercancía: el producto se crea en 0 y las cantidades
  /// escritas se devuelven aquí para sumarlas con la entrada (no se cuentan dos veces)
  final ValueChanged<Product>? onCreatedForPurchase;

  /// Proveedor ya elegido (el de la entrada)
  final String? initialSupplierId;

  const ProductFormScreen({
    super.key,
    this.productToEdit,
    required this.businessId,
    this.userRole,
    this.onCreatedForPurchase,
    this.initialSupplierId,
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

  /// Marca (0.16.0)
  late TextEditingController _brandController;
  late TextEditingController _purchasePriceController;
  late TextEditingController _salePriceController;

  /// Precio de antes (oferta en la tienda en línea)
  late TextEditingController _comparePriceController;
  late TextEditingController _stockController;
  late TextEditingController _minStockController;

  String? _photoPath;
  bool _isUploadingPhoto = false;

  /// Id fijo desde que se abre el formulario: la foto se guarda en la nube con él
  /// antes de guardar el producto
  late final String _productId = widget.productToEdit?.id ?? const Uuid().v4();
  void Function()? _stopPasteListener;

  /// La ventana de opciones de foto está abierta
  bool _photoPickerOpen = false;
  String? _selectedCategory;
  List<Category> _categories = [];
  bool _isLoading = false;

  // Variantes (tallas y colores)
  bool _hasVariants = false;

  /// Controla vencimiento por lote (0.16.0, fase 2b)
  bool _tracksExpiry = false;

  /// Precio por cantidad (0.17.0, Pro)
  late List<PriceTier> _priceTiers = widget.productToEdit?.priceTiers ?? const [];

  /// Plantilla del negocio: decide si un producto nuevo viene con lote encendido
  ProductTemplate? _template;

  /// La persona movió el interruptor de lote: ya no se cambia solo con la categoría
  bool _expiryTouched = false;

  /// Producto nuevo: lote encendido según la plantilla y la categoría (0.16.3)
  void _applyExpiryDefault() {
    if (widget.productToEdit != null || _expiryTouched || _template == null) return;
    _tracksExpiry = _template!.expiryByDefault(_selectedCategory);
  }
  final _variants = VariantEditorController();

  // Proveedor principal (opcional)
  late String? _supplierId = widget.productToEdit?.supplierId ?? widget.initialSupplierId;

  bool get isEditing => widget.productToEdit != null;

  @override
  void initState() {
    super.initState();
    final p = widget.productToEdit;

    _codeController = TextEditingController(text: p?.code ?? CodeGenerator.generateUniqueCode());
    _nameController = TextEditingController(text: p?.name ?? '');
    _descriptionController = TextEditingController(text: p?.description ?? '');
    _brandController = TextEditingController(text: p?.brand ?? '');
    _purchasePriceController = TextEditingController(
      text: p != null && p.purchasePrice > 0 ? _priceText(p.purchasePrice) : '',
    );
    _salePriceController = TextEditingController(
      text: p != null && p.salePrice > 0 ? _priceText(p.salePrice) : '',
    );
    _comparePriceController = TextEditingController(
      text: p?.comparePrice != null && p!.comparePrice! > 0 ? _priceText(p.comparePrice!) : '',
    );
    _stockController = TextEditingController(text: p?.stock.toString() ?? '0');
    _minStockController = TextEditingController(text: p?.minStock.toString() ?? '5');
    _photoPath = p?.photoPath;
    _tracksExpiry = p?.tracksExpiry ?? false;
    // Producto nuevo en una droguería (siempre) o en lo perecedero de una tienda de barrio
    if (p == null) {
      ProductTemplate.applied(widget.businessId).then((t) {
        if (!mounted) return;
        setState(() {
          _template = t;
          _applyExpiryDefault();
        });
      });
    }
    if (p != null) {
      // Editar: las cantidades guardadas se cambian con «Ajustar stock físico» (0.16.7)
      _variants.lockExistingStock = true;
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
      if (!mounted || _isUploadingPhoto) return;
      // La ventana de opciones de foto tapa el resultado: se cierra al pegar
      if (_photoPickerOpen) {
        Navigator.of(context, rootNavigator: true).popUntil((route) => route is! PopupRoute);
        Navigator.of(context).popUntil((route) => route is! PopupRoute);
      }
      _uploadPhotoBytes(image.bytes, image.mimeType, pasted: true);
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
      if (!Permissions.can(role, Perm.productsEdit) && mounted) {
        AppToast.show(context, message: 'Acceso restringido: Solo administradores pueden gestionar productos', type: ToastType.error);
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _brandController.dispose();
    _purchasePriceController.dispose();
    _salePriceController.dispose();
    _comparePriceController.dispose();
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
      _applyExpiryDefault();
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

  Future<void> _uploadPhotoBytes(Uint8List bytes, String? mimeType, {bool pasted = false}) async {
    setState(() => _isUploadingPhoto = true);
    if (pasted) AppToast.showInfo(context, 'Pegando la foto...');
    try {
      final url = await ProductImageService.instance.uploadBytes(
        businessId: _photoBusinessId,
        productId: _productId,
        bytes: bytes,
        mimeType: mimeType,
      );
      if (mounted) {
        setState(() => _photoPath = url);
        AppToast.showSuccess(context, pasted ? 'Listo, pegamos la foto del producto.' : 'Listo, subimos la foto.');
      }
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

  Future<void> _showImagePickerModal() async {
    _photoPickerOpen = true;
    await ImageSourcePickerModal.show(
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
    _photoPickerOpen = false;
  }

  /// El lector de códigos con la revisión del último número y el aviso si otro
  /// producto ya tiene ese código
  Future<void> _scanBarcode() async {
    final scannedCode = await CodeReader.pick(
      context,
      caption: widget.productToEdit == null ? 'Nuevo producto' : 'Editar producto',
      initial: _codeController.text.trim().isEmpty ? null : _codeController.text.trim(),
      ownerOf: (code) async {
        final other = await _repository.getProductByCode(code, widget.businessId);
        return other == null || other.id == widget.productToEdit?.id ? null : other.name;
      },
      confirmLabel: 'Usar este código',
    );
    if (scannedCode != null && scannedCode.isNotEmpty) {
      setState(() {
        _codeController.text = scannedCode;
      });
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final result = await CategoryNameDialog.show(context, existing: [for (final c in _categories) c.name]);
    if (result == null || result.isEmpty) return;

    // Si ya existía con otra escritura ("ropa" / "Ropa"), se elige esa en vez de repetirla
    final same = _categories.where((c) => c.name.trim().toLowerCase() == result.toLowerCase());
    if (same.isEmpty) {
      await _repository.addCategory(result, widget.businessId);
      await _loadCategories();
    }
    if (!mounted) return;
    setState(() {
      _selectedCategory = same.isNotEmpty ? same.first.name : result;
      _applyExpiryDefault();
    });
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
      AppToast.show(context, message: 'Por favor crea o selecciona una categoría pulsando el botón +', type: ToastType.warning);
      return;
    }

    // El código: que cuadre el último número y que no lo tenga otro producto
    final code = _codeController.text.trim();
    final check = BarcodeCheck.of(code);
    if (!check.valid) {
      AppToast.showWarning(context, 'El código no cuadra: el último número debería ser ${check.expected}. Revísalo con el lector.');
      return;
    }
    final other = await _repository.getProductByCode(code, widget.businessId);
    if (!mounted) return;
    if (other != null && other.id != widget.productToEdit?.id) {
      AppToast.showError(context, 'Ese código ya lo tiene «${other.name}». Usa otro o genera uno nuevo.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final purchasePrice = _price(_purchasePriceController.text);
    final salePrice = _price(_salePriceController.text);
    final minStock = int.tryParse(_minStockController.text.trim()) ?? 5;
    final productId = _productId;
    final now = DateTime.now();

    List<ProductVariant> variants = [];
    if (_hasVariants) {
      final problem = _variants.validate();
      if (problem != null) {
        AppToast.show(context, message: '$problem O desactiva la opción de variantes.', type: ToastType.info);
        setState(() => _isLoading = false);
        return;
      }
      variants = _variants.build(
        businessId: widget.productToEdit?.businessId ?? widget.businessId,
        productId: productId,
        now: now,
      );
    }

    // Al editar, el stock sale de la base (no se escribe aquí y pudo cambiar con una
    // venta mientras el formulario estaba abierto)
    final saved = isEditing ? await _repository.getProductById(productId, widget.productToEdit!.businessId) : null;
    // Variantes ya guardadas: su cantidad de la base, no la del formulario
    if (saved != null && _hasVariants) {
      final current = {for (final v in saved.variants) v.id: v.stock};
      variants = [for (final v in variants) current.containsKey(v.id) ? v.copyWith(stock: current[v.id]) : v];
    }
    final totalStock = _hasVariants
        ? variants.fold(0, (sum, v) => sum + v.stock)
        : (saved?.stock ?? int.tryParse(_stockController.text.trim()) ?? 0);

    final product = Product(
      id: productId,
      businessId: widget.productToEdit?.businessId ?? widget.businessId,
      code: _codeController.text.trim(),
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      category: _selectedCategory!,
      brand: _brandController.text.trim().isEmpty ? null : _brandController.text.trim(),
      purchasePrice: purchasePrice,
      salePrice: salePrice,
      comparePrice: _price(_comparePriceController.text) > salePrice
          ? _price(_comparePriceController.text)
          : null,
      stock: totalStock,
      minStock: minStock,
      photoPath: _photoPath,
      createdAt: widget.productToEdit?.createdAt ?? now,
      updatedAt: now,
      hasVariants: _hasVariants,
      variants: variants,
      supplierId: _supplierId,
      tracksExpiry: _tracksExpiry && !_hasVariants,
      priceTiers: PriceTier.clean(_priceTiers, basePrice: salePrice),
    );

    try {
      final forPurchase = widget.onCreatedForPurchase;
      if (isEditing) {
        await _repository.updateProduct(product);
      } else if (forPurchase != null) {
        await _repository.insertProduct(product.copyWith(
          stock: 0,
          variants: [for (final v in variants) v.copyWith(stock: 0)],
        ));
        forPurchase(product);
      } else {
        await _repository.insertProduct(product);
      }

      if (mounted) {
        AppToast.show(context, message: isEditing ? 'Producto actualizado con éxito' : '¡Producto guardado exitosamente!', type: ToastType.success);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, message: 'Error al guardar: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Precios (0.16.9): con puntos de mil si la moneda no usa centavos (peso colombiano);
  // con decimales si los usa (dólar: «2.50» es dos dólares y medio, no 250)
  static bool get _noCents => CurrencyFormatter.noCents;
  static List<TextInputFormatter>? get _priceFormatters => _noCents ? MoneyInput.formatters : null;
  static TextInputType get _priceKeyboard =>
      _noCents ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true);

  static double _price(String text) =>
      _noCents ? MoneyInput.parse(text) : (double.tryParse(text.trim().replaceAll(',', '.')) ?? 0);

  static String _priceText(double v) =>
      _noCents ? MoneyInput.text(v) : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2));

  @override
  Widget build(BuildContext context) {
    final purchasePrice = _price(_purchasePriceController.text);
    final salePrice = _price(_salePriceController.text);
    final profit = salePrice - purchasePrice;
    final margin = salePrice > 0 ? (profit / salePrice) * 100 : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar producto' : 'Nuevo producto'),
        actions: [
          // Compartir el producto con el link de la tienda (0.16.0, fase 3)
          if (isEditing)
            IconButton(
              tooltip: 'Compartir',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => ProductShare.share(context, product: widget.productToEdit!),
            ),
        ],
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
                              color: context.colors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: context.colors.lineStrong,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
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
                                      Icon(Icons.add_a_photo_outlined, size: 40, color: context.colors.accent),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Agregar foto',
                                        style: TextStyle(
                                          fontSize: AppText.sizeCaption,
                                          fontWeight: FontWeight.bold,
                                          color: context.colors.inkMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          if (_isUploadingPhoto)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.35),
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
                              backgroundColor: context.colors.accent,
                              child: Icon(
                                (_photoPath != null && _photoPath!.trim().isNotEmpty) ? Icons.edit_outlined : Icons.camera_alt_outlined,
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
                    decoration: InputDecoration(
                      labelText: 'Nombre del producto *',
                      hintText: 'Ej. Café Colombiano 500g, Llavero Acrílico...',
                      prefixIcon: Icon(Icons.shopping_bag_outlined, color: context.colors.inkMuted),
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
                              decoration: InputDecoration(
                                labelText: 'Categoría *',
                                prefixIcon: Icon(Icons.category_outlined, color: context.colors.inkMuted),
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
                                    style: TextStyle(fontSize: AppText.sizeBody, color: context.colors.inkMuted),
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
                                        _applyExpiryDefault();
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
                            icon: const Icon(Icons.add_outlined),
                            tooltip: 'Nueva categoría',
                            style: IconButton.styleFrom(
                              backgroundColor: context.colors.accent.withValues(alpha: 0.12),
                              foregroundColor: context.colors.accent,
                              padding: const EdgeInsets.all(14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: _openManageCategoriesModal,
                            icon: const Icon(Icons.tune_outlined, size: 20),
                            tooltip: 'Gestionar categorías',
                            style: IconButton.styleFrom(
                              backgroundColor: context.colors.surfaceMuted,
                              foregroundColor: context.colors.inkMuted,
                              padding: const EdgeInsets.all(14),
                            ),
                          ),
                        ],
                      ),
                      if (_categories.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 14, color: context.colors.accent),
                              const SizedBox(width: 4),
                              Text(
                                'Aún no tienes categorías. Toca + para crear una.',
                                style: TextStyle(
                                  fontSize: AppText.sizeCaption,
                                  color: context.colors.accent,
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
                          keyboardType: _priceKeyboard,
                          inputFormatters: _priceFormatters,
                          decoration: const InputDecoration(
                            labelText: 'Precio de compra',
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
                          keyboardType: _priceKeyboard,
                          inputFormatters: _priceFormatters,
                          decoration: const InputDecoration(
                            labelText: 'Precio de venta *',
                            prefixText: r'$ ',
                            hintText: '0',
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Requerido';
                            if (_price(v) <= 0) return 'Mayor a 0';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  // Precio sugerido por margen (0.15.0): con el costo, un toque pone el precio.
                  // Siempre ocupa una fila del mismo alto, para que lo de abajo no salte (0.16.3)
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: purchasePrice > 0
                        ? ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              Center(
                                child: Text('Precio para ganar', style: AppText.caption(context, color: context.colors.inkMuted)),
                              ),
                              for (final m in Pricing.margins)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Center(
                                    child: ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text('$m % · ${CurrencyFormatter.format(Pricing.priceForMargin(purchasePrice, m))}',
                                          style: AppText.caption(context)),
                                      onPressed: () => setState(() =>
                                          _salePriceController.text = _priceText(Pricing.priceForMargin(purchasePrice, m).roundToDouble())),
                                    ),
                                  ),
                                ),
                            ],
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Escribe el costo para ver precios sugeridos',
                                style: AppText.caption(context, color: context.colors.inkFaint)),
                          ),
                  ),
                  const SizedBox(height: 12),
                  // Oferta en la tienda en línea: el precio de antes se ve tachado
                  TextFormField(
                    controller: _comparePriceController,
                    keyboardType: _priceKeyboard,
                    inputFormatters: _priceFormatters,
                    decoration: const InputDecoration(
                      labelText: 'Precio de antes (opcional)',
                      prefixText: r'$ ',
                      hintText: 'Para mostrar «Oferta» en la tienda en línea',
                    ),
                    validator: (v) {
                      final before = _price(v ?? '');
                      final now = _price(_salePriceController.text);
                      if (before > 0 && before <= now) return 'Debe ser mayor al precio de venta';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  // Precio por cantidad (0.17.0, bloque B)
                  ValueListenableBuilder(
                    valueListenable: ProService.instance.status,
                    builder: (context, status, _) => PriceTiersEditor(
                      initial: _priceTiers,
                      salePrice: _price(_salePriceController.text),
                      enabled: status.active,
                      onChanged: (t) => _priceTiers = t,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Ganancia y margen: sin precio de venta se ve en gris con «—» (mismo alto)
                  Builder(builder: (context) {
                    final c = context.colors;
                    final ready = salePrice > 0;
                    final good = margin >= 0;
                    final strong = !ready ? c.inkMuted : (good ? c.success : c.danger);
                    final style = AppText.small(context, weight: FontWeight.w700, color: strong);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 10),
                      decoration: BoxDecoration(
                        color: !ready ? c.surfaceMuted : (good ? c.successSoft : c.dangerSoft),
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Row(
                        children: [
                          Icon(good ? Icons.trending_up_outlined : Icons.trending_down_outlined, size: 18, color: strong),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: Text(
                              'Ganancia unitaria: ${ready ? CurrencyFormatter.format(profit) : '—'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style,
                            ),
                          ),
                          Text('Margen: ${ready ? '${margin.toStringAsFixed(1)}%' : '—'}', style: style),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),

                  // Lotes con vencimiento (0.16.0, fase 2b)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.event_outlined),
                    title: const Text('Controla vencimiento por lote'),
                    subtitle: Text(
                      _hasVariants
                          ? 'No disponible en productos con tallas o variantes.'
                          : 'Cada entrada pide su fecha y lo vencido no se vende. Avisamos 30 días antes.',
                      style: TextStyle(fontSize: AppText.sizeCaption, color: context.colors.inkMuted),
                    ),
                    value: _tracksExpiry && !_hasVariants,
                    onChanged: _hasVariants
                        ? null
                        : (v) => setState(() {
                              _tracksExpiry = v;
                              _expiryTouched = true;
                            }),
                  ),
                  if (widget.productToEdit != null && _tracksExpiry && !_hasVariants && widget.productToEdit!.tracksExpiry) ...[
                    const SizedBox(height: AppSpace.sm),
                    ProductLotsSection(product: widget.productToEdit!),
                  ],
                  const SizedBox(height: 16),

                  // 5. Stock y Variantes (tallas y colores)
                  Material(
                    color: context.colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      side: BorderSide(
                        color: _hasVariants ? context.colors.accent : context.colors.line,
                        width: _hasVariants ? 1.5 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
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
                              style: TextStyle(fontSize: AppText.sizeBody, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        'Actívalo si vendes este producto en varias tallas o colores, cada uno con sus existencias.',
                        style: TextStyle(fontSize: AppText.sizeCaption, color: context.colors.inkMuted),
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
                            // Al editar no se escribe aquí: «Ajustar stock físico» en el detalle
                            // deja el motivo en el historial (0.16.7, hallazgo 10)
                            readOnly: isEditing,
                            enabled: !isEditing,
                            decoration: InputDecoration(
                              helperText: isEditing ? 'Se cambia con «Ajustar stock físico» en el detalle' : null,
                              helperMaxLines: 2,
                              labelText: isEditing
                                  ? 'Stock actual'
                                  : (widget.onCreatedForPurchase != null ? 'Cantidad que llegó *' : 'Stock inicial *'),
                              hintText: '0',
                              prefixIcon: Icon(Icons.inventory_2_outlined, size: 20, color: context.colors.inkMuted),
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
                            decoration: InputDecoration(
                              labelText: 'Stock mínimo',
                              hintText: '5',
                              prefixIcon: Icon(Icons.notifications_active_outlined, size: 20, color: context.colors.inkMuted),
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
                      ],
                    )
                  else ...[
                    // Si SÍ tiene variantes: tallas, colores y existencias por combinación
                    VariantEditor(controller: _variants, photoPath: _photoPath, businessId: _photoBusinessId, productId: _productId),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _minStockController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Alerta de stock mínimo para todos',
                        hintText: '5',
                        prefixIcon: Icon(Icons.notifications_active_outlined, size: 20, color: context.colors.inkMuted),
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
                          labelText: 'Código de barras o SKU',
                          hintText: 'Ej. STK-12345',
                          prefixIcon: Icon(Icons.qr_code_2_outlined, color: context.colors.inkMuted),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.qr_code_scanner_outlined, color: context.colors.accent),
                                tooltip: 'Leer el código: cámara, foto o a mano',
                                onPressed: _scanBarcode,
                              ),
                              IconButton(
                                icon: Icon(Icons.refresh_outlined, color: context.colors.inkFaint, size: 20),
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
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          'Código único automático. Toca el escáner si tu producto ya tiene código de barras impreso.',
                          style: TextStyle(fontSize: AppText.sizeCaption, color: context.colors.inkMuted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Marca (0.16.0): la tienda en línea filtra por marca
                  TextFormField(
                    controller: _brandController,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      labelText: 'Marca (opcional)',
                      hintText: 'Ej.: Elf Bar, Tecnoquímicas',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 7. Descripción opcional
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Descripción o notas (opcional)',
                      hintText: 'Detalles adicionales, ubicación...',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 8. Proveedor opcional
                  SupplierToggleField(
                    businessId: widget.productToEdit?.businessId ?? widget.businessId,
                    supplierId: _supplierId,
                    onChanged: (id) => _supplierId = id,
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
                        isEditing ? 'Guardar cambios' : 'Crear producto',
                        style: const TextStyle(fontSize: AppText.sizeTitle, fontWeight: FontWeight.bold),
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
    return AppDialog(
title: 'Foto desde un enlace',
content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pega el enlace de la página del producto (Shein, Temu, Mercado Libre, Amazon…) '
              'o el de la imagen. Traemos la foto principal y la guardamos con tu producto.',
              style: TextStyle(fontSize: AppText.sizeSmall, height: 1.4, color: c.inkMuted),
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
                  icon: const Icon(Icons.content_paste_outlined),
                  onPressed: _pasteFromClipboard,
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Usa fotos que tengas permiso de usar.',
              style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint),
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
