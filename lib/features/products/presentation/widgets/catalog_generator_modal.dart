import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/design/primary_action_button.dart';
import '../../../../core/design/pro_crown.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/models/business.dart';
import '../../../pro/data/pro_service.dart';
import '../../../pro/presentation/widgets/pro_upsell_sheet.dart';
import '../../../reports/data/catalog_pdf_service.dart';
import '../../../reports/models/catalog_style.dart';
import '../../models/product.dart';
import '../../../business/presentation/business_identity.dart';
import 'story_catalog_modal.dart';

/// Arma el catálogo del negocio: qué productos, cómo se ve y qué datos de
/// contacto lleva. El estilo se recuerda por negocio y sirve para el PDF y las
/// historias.
class CatalogGeneratorModal extends StatefulWidget {
  final Business business;

  const CatalogGeneratorModal({super.key, required this.business});

  static Future<void> show({
    required BuildContext context,
    required Business business,
  }) {
    return showModalBottomSheet(
      showDragHandle: false,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CatalogGeneratorModal(business: business),
    );
  }

  @override
  State<CatalogGeneratorModal> createState() => _CatalogGeneratorModalState();
}

class _CatalogGeneratorModalState extends State<CatalogGeneratorModal> {
  final _pdfService = CatalogPdfService.instance;

  final _titleController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _addressController = TextEditingController();
  final _hoursController = TextEditingController();
  final _socialController = TextEditingController();

  CatalogStyle _style = const CatalogStyle();
  List<Product> _allInStockProducts = [];
  List<String> _categories = ['Todas'];
  String _selectedCategory = 'Todas';

  bool _isLoading = true;
  bool _isGenerating = false;
  double _progress = 0.0;
  String _statusMessage = '';

  File? _generatedFile;
  String? _savedPathLabel;
  bool _isPublicDownload = false;
  bool _isSavingToDownloads = false;

  /// Stockealo Pro activo en este negocio: abre plantillas, colores, fondo y pie
  bool _pro = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    ProService.instance.status.addListener(_onProChanged);
    ProService.instance.refresh(widget.business.id);
    // refresh limpia al instante el estado si era de otro negocio
    _pro = ProService.instance.status.value.active;
  }

  void _onProChanged() {
    if (mounted) setState(() => _pro = ProService.instance.status.value.active);
  }

  /// Las opciones Pro se pueden probar en la vista previa; Pro se pide al
  /// descargar o compartir. true si se puede seguir con la exportación.
  Future<bool> _confirmExport() async {
    if (_pro || !_chosenStyle.usesProFeatures) return true;
    FocusScope.of(context).unfocus();
    final result = await ProUpsellSheet.show(
      context,
      business: widget.business,
      title: '¿Te gusta cómo quedó?',
      message: 'Tu catálogo usa ${_joinNames(_chosenStyle.proFeatureNames)}. '
          'Descárgalo así con Stockealo Pro.',
      highlight: ProBenefit.catalogs,
      alternativeLabel: 'Descargar la versión gratis',
    );
    if (!mounted) return false;
    switch (result) {
      case ProUpsellResult.pro:
        return true;
      case ProUpsellResult.alternative:
        _update(_chosenStyle.effective(pro: false));
        return true;
      case ProUpsellResult.dismissed:
        return false;
    }
  }

  static String _joinNames(List<String> names) => names.length <= 1
      ? names.join()
      : '${names.take(names.length - 1).join(', ')} y ${names.last}';

  @override
  void dispose() {
    ProService.instance.status.removeListener(_onProChanged);
    _titleController.dispose();
    _whatsappController.dispose();
    _addressController.dispose();
    _hoursController.dispose();
    _socialController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final db = AppDatabase.instance;
      var style = CatalogStyle.decode(await db.getSetting(CatalogStyle.settingsKey(widget.business.id)));

      // La primera vez, el WhatsApp sale del teléfono de la cuenta
      final phone = AuthRepository.instance.currentUser?.phone?.trim() ?? '';
      if (style.whatsapp.isEmpty && phone.isNotEmpty) style = style.copyWith(whatsapp: phone);

      final maps = await (await db.database).query(
        'products',
        where: 'business_id = ? AND is_active = 1 AND stock > 0',
        whereArgs: [widget.business.id],
        orderBy: 'category ASC, name ASC',
      );
      final products = maps.map((m) => Product.fromMap(m)).toList();
      final catSet = <String>{'Todas'};
      for (final p in products) {
        if (p.category.trim().isNotEmpty) catSet.add(p.category.trim());
      }

      // Los elegidos a mano que ya no existen o no tienen stock se descartan
      final ids = products.map((p) => p.id).toSet();
      style = style.copyWith(selectedProductIds: style.selectedProductIds.where(ids.contains).toSet());

      _titleController.text = style.title;
      _whatsappController.text = style.whatsapp;
      _addressController.text = style.address;
      _hoursController.text = style.hours;
      _socialController.text = style.social;

      if (mounted) {
        setState(() {
          _style = style;
          _allInStockProducts = products;
          _categories = catSet.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(context, message: 'No se pudo cargar el inventario: $e', type: ToastType.error);
      }
    }
  }

  /// Estilo elegido con lo que hay escrito en los campos de texto (se guarda así)
  CatalogStyle get _chosenStyle => _style.copyWith(
        title: _titleController.text.trim(),
        whatsapp: _whatsappController.text.trim(),
        address: _addressController.text.trim(),
        hours: _hoursController.text.trim(),
        social: _socialController.text.trim(),
      );

  /// Lo que de verdad se exporta: sin Pro, las opciones Pro vuelven a lo gratis.
  /// La vista previa y las opciones muestran [_chosenStyle] (se puede probar).
  CatalogStyle get _currentStyle => _chosenStyle.effective(pro: _pro);

  List<Product> get _targetProducts =>
      CatalogPdfService.selectProducts(_allInStockProducts, _currentStyle, categoryFilter: _selectedCategory);

  void _update(CatalogStyle style) => setState(() => _style = style);

  Future<void> _saveStyle() async {
    try {
      await AppDatabase.instance.setSetting(CatalogStyle.settingsKey(widget.business.id), _chosenStyle.encode());
    } catch (e) {
      debugPrint('No se pudo guardar el estilo del catálogo: $e');
    }
  }

  Future<void> _generatePdf() async {
    if (_targetProducts.isEmpty) {
      AppToast.show(context, message: 'No hay productos para este catálogo.', type: ToastType.warning);
      return;
    }
    FocusScope.of(context).unfocus();
    if (!await _confirmExport() || !mounted) return;
    await _saveStyle();

    setState(() {
      _isGenerating = true;
      _progress = 0.05;
      _statusMessage = 'Preparando el catálogo…';
    });

    try {
      final file = await _pdfService.generateCatalogPdf(
        business: widget.business,
        products: _allInStockProducts,
        style: _currentStyle,
        categoryFilter: _selectedCategory,
        onProgress: (p, msg) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusMessage = msg;
            });
          }
        },
      );

      final savedResult = await _pdfService.saveToDownloads(pdfFile: file, businessName: widget.business.name);

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generatedFile = savedResult.file;
          _savedPathLabel = savedResult.pathLabel;
          _isPublicDownload = savedResult.isPublicDownload;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        AppToast.show(context, message: 'No se pudo crear el PDF: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _openStories() async {
    if (_targetProducts.isEmpty) {
      AppToast.show(context, message: 'No hay productos para este catálogo.', type: ToastType.warning);
      return;
    }
    FocusScope.of(context).unfocus();
    if (!await _confirmExport() || !mounted) return;
    await _saveStyle();
    if (!mounted) return;
    StoryCatalogModal.show(
      context: context,
      business: widget.business,
      products: _targetProducts,
      style: _currentStyle,
    );
  }

  Future<void> _manualSaveToDownloads() async {
    if (_generatedFile == null) return;
    setState(() => _isSavingToDownloads = true);
    try {
      final savedResult = await _pdfService.saveToDownloads(pdfFile: _generatedFile!, businessName: widget.business.name);
      if (mounted) {
        setState(() {
          _isSavingToDownloads = false;
          _generatedFile = savedResult.file;
          _savedPathLabel = savedResult.pathLabel;
          _isPublicDownload = savedResult.isPublicDownload;
        });
        AppToast.show(context, message: 'Guardado en ${savedResult.pathLabel}', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingToDownloads = false);
        AppToast.show(context, message: 'No se pudo guardar el archivo: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _shareFile() async {
    if (_generatedFile == null) return;
    await Share.shareXFiles(
      [XFile(_generatedFile!.path, mimeType: 'application/pdf', name: p.basename(_generatedFile!.path))],
      subject: 'Catálogo de ${widget.business.name}',
    );
  }

  Future<void> _openFile() async {
    if (_generatedFile == null) return;
    final res = await OpenFilex.open(_generatedFile!.path);
    if (res.type != ResultType.done && mounted) {
      AppToast.show(context, message: 'No se pudo abrir el visor: ${res.message}', type: ToastType.warning);
    }
  }

  String _getFileSize(File file) {
    try {
      final bytes = file.lengthSync();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {
      return '';
    }
  }

  Color get _accent =>
      AppPalette.fromHex(_chosenStyle.colorHex) ?? AppPalette.fromHex(widget.business.color) ?? AppPalette.brand;

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpace.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: c.lineStrong, borderRadius: BorderRadius.circular(AppRadius.pill)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.sm, AppSpace.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Catálogo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
                        Text(
                          'Para compartir por WhatsApp o redes',
                          style: TextStyle(fontSize: 13, color: c.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: c.inkMuted),
                  ),
                ],
              ),
            ),
            Flexible(child: _body(c)),
          ],
        ),
      ),
    );
  }

  Widget _body(StockealoColors c) {
    if (_isLoading) {
      return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    }
    if (_allInStockProducts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Text(
          'No tienes productos con stock. Agrega productos al inventario para armar tu catálogo.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.inkMuted),
        ),
      );
    }
    if (_isGenerating) return _generatingView(c);
    if (_generatedFile != null) return _successView(c);
    return _configView(c);
  }

  Widget _generatingView(StockealoColors c) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              color: c.accent,
              backgroundColor: c.surfaceMuted,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(_statusMessage, style: TextStyle(color: c.inkMuted), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _successView(StockealoColors c) {
    final file = _generatedFile!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(
            c,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: c.successSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
                  child: Icon(Icons.picture_as_pdf_rounded, color: c.success),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Catálogo listo', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                      Text(
                        '${p.basename(file.path)} · ${_getFileSize(file)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.inkMuted),
                      ),
                      if (_savedPathLabel != null)
                        Text(
                          _isPublicDownload ? 'Guardado en $_savedPathLabel' : 'Copia en $_savedPathLabel',
                          style: TextStyle(fontSize: 12, color: c.inkMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          FilledButton.icon(
            onPressed: _shareFile,
            icon: const Icon(Icons.share_rounded),
            label: const Text('Compartir'),
          ),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openFile,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Ver'),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSavingToDownloads ? null : _manualSaveToDownloads,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Descargas'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          TextButton(
            onPressed: () => setState(() => _generatedFile = null),
            child: const Text('Cambiar el diseño'),
          ),
        ],
      ),
    );
  }

  Widget _configView(StockealoColors c) {
    final count = _targetProducts.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
            children: [
              _CatalogPreview(
                business: widget.business,
                style: _chosenStyle,
                accent: _accent,
                products: _targetProducts
                    .take(_style.template == 'lista' ? 5 : (_style.itemsPerPage >= 4 ? 4 : _style.itemsPerPage))
                    .toList(),
              ),
              if (!_pro && _chosenStyle.usesProFeatures) _trialBanner(c),
              const SizedBox(height: AppSpace.lg),
              _productsSection(c),
              const SizedBox(height: AppSpace.md),
              _designSection(c),
              const SizedBox(height: AppSpace.md),
              _contactSection(c),
              const SizedBox(height: AppSpace.md),
              _showSection(c),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.md),
          decoration: BoxDecoration(color: c.paper, border: Border(top: BorderSide(color: c.line))),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: count == 0 ? null : _openStories,
                  icon: const Icon(Icons.amp_stories_outlined),
                  label: const Text('Historias'),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: PrimaryActionButton(
                  label: count == 0 ? 'Sin productos' : 'PDF · $count',
                  icon: Icons.picture_as_pdf_rounded,
                  onPressed: count == 0 ? null : _generatePdf,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Aviso bajo la vista previa mientras se prueban opciones Pro sin tenerlo
  Widget _trialBanner(StockealoColors c) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpace.md),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.xs, AppSpace.xs),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          const ProCrown(size: 18),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text('Probando opciones Pro', style: TextStyle(fontSize: 13, color: c.ink)),
          ),
          TextButton(
            onPressed: () => _update(_chosenStyle.effective(pro: false)),
            child: const Text('Volver a lo gratis'),
          ),
        ],
      ),
    );
  }

  Widget _section(StockealoColors c, {String? title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: AppSpace.md),
          ],
          child,
        ],
      ),
    );
  }

  Widget _productsSection(StockealoColors c) {
    final manual = _style.selectedProductIds.isNotEmpty;
    return _section(
      c,
      title: 'Productos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!manual) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final cat in _categories)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpace.sm),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: _selectedCategory == cat,
                        onSelected: (_) => setState(() => _selectedCategory = cat),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.checklist_rounded, color: c.inkMuted),
            title: Text(
              manual ? '${_style.selectedProductIds.length} elegidos a mano' : 'Elegir productos a mano',
              style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
            ),
            subtitle: manual ? null : Text('Ahora: todos los de la categoría', style: TextStyle(color: c.inkMuted)),
            trailing: manual
                ? TextButton(
                    onPressed: () => _update(_style.copyWith(selectedProductIds: {})),
                    child: const Text('Quitar'),
                  )
                : Icon(Icons.chevron_right_rounded, color: c.inkFaint),
            onTap: _pickProducts,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Solo productos con foto', style: TextStyle(color: c.ink)),
            value: _style.onlyWithPhoto,
            onChanged: (v) => _update(_style.copyWith(onlyWithPhoto: v)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickProducts() async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductPickerSheet(products: _allInStockProducts, initial: _style.selectedProductIds),
    );
    if (picked != null) _update(_style.copyWith(selectedProductIds: picked));
  }

  Widget _designSection(StockealoColors c) {
    // Color del negocio (o el verde de Stockealo si no tiene); no se repite en la lista
    final businessHex = AppPalette.toHex(AppPalette.fromHex(widget.business.color) ?? AppPalette.brand);
    final freeHexes = CatalogStyle.paletteHexes(pro: false);
    final colors = <String?>[
      null,
      for (final hex in CatalogStyle.paletteHexes(pro: true))
        if (hex != businessHex) hex,
    ];
    final current = _chosenStyle;
    final stockealo = AppPalette.toHex(AppPalette.brand);
    return _section(
      c,
      title: 'Diseño',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Plantilla', style: TextStyle(fontSize: 13, color: c.inkMuted)),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final t in CatalogStyle.templates.entries)
                _ProChip(
                  label: t.value,
                  selected: current.template == t.key,
                  locked: !_pro && t.key != 'clasica',
                  onTap: () => _update(_style.copyWith(template: t.key)),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text('Color', style: TextStyle(fontSize: 13, color: c.inkMuted)),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final hex in colors)
                _ColorDot(
                  color: AppPalette.fromHex(hex ?? businessHex) ?? AppPalette.brand,
                  selected: current.colorHex == hex,
                  tooltip: hex == null
                      ? 'Color del negocio'
                      : (hex == stockealo ? 'Verde Stockealo' : 'Color ${_colorName(hex)}'),
                  isBusiness: hex == null,
                  locked: !_pro && hex != null && !freeHexes.contains(hex),
                  onTap: () => _update(hex == null
                      ? CatalogStyle.fromJson({..._style.toJson(), 'colorHex': null})
                      : _style.copyWith(colorHex: hex)),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text('Fondo', style: TextStyle(fontSize: 13, color: c.inkMuted)),
          const SizedBox(height: AppSpace.sm),
          SegmentedButton<bool>(
            segments: [
              const ButtonSegment(value: false, label: Text('Claro'), icon: Icon(Icons.light_mode_outlined)),
              ButtonSegment(
                value: true,
                label: const Text('Oscuro'),
                icon: _pro ? const Icon(Icons.dark_mode_outlined) : const ProCrown(size: 18),
                tooltip: _pro ? null : 'Con Stockealo Pro',
              ),
            ],
            selected: {current.darkBackground},
            onSelectionChanged: (v) => _update(_style.copyWith(darkBackground: v.first)),
          ),
          if (_style.template != 'lista') ...[
          const SizedBox(height: AppSpace.lg),
          Text('Productos por página', style: TextStyle(fontSize: 13, color: c.inkMuted)),
          const SizedBox(height: AppSpace.sm),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 4, label: Text('4')),
              ButtonSegment(value: 6, label: Text('6')),
            ],
            selected: {_style.itemsPerPage},
            onSelectionChanged: (v) => _update(_style.copyWith(itemsPerPage: v.first)),
          ),
          ],
          const SizedBox(height: AppSpace.lg),
          _field(c, _titleController, 'Título de la portada', 'Ej.: Colección de temporada', Icons.title_rounded),
        ],
      ),
    );
  }

  String _colorName(String hex) => AppPalette.businessColors.entries
      .firstWhere((e) => AppPalette.toHex(e.value) == hex, orElse: () => const MapEntry('', Colors.black))
      .key;

  Widget _contactSection(StockealoColors c) {
    return _section(
      c,
      title: 'Contacto',
      child: Column(
        children: [
          _field(c, _whatsappController, 'WhatsApp', 'Para que te escriban', Icons.chat_outlined,
              keyboard: TextInputType.phone),
          const SizedBox(height: AppSpace.md),
          _field(c, _addressController, 'Dirección', 'Opcional', Icons.place_outlined),
          const SizedBox(height: AppSpace.md),
          _field(c, _hoursController, 'Horario', 'Ej.: Lun a Sáb, 8 a. m. – 6 p. m.', Icons.schedule_rounded),
          const SizedBox(height: AppSpace.md),
          _field(c, _socialController, 'Redes', 'Ej.: @mitienda', Icons.alternate_email_rounded),
        ],
      ),
    );
  }

  Widget _field(StockealoColors c, TextEditingController controller, String label, String hint, IconData icon,
      {TextInputType? keyboard}) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      textCapitalization: keyboard == null ? TextCapitalization.sentences : TextCapitalization.none,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon)),
    );
  }

  Widget _showSection(StockealoColors c) {
    Widget toggle(String label, bool value, CatalogStyle Function(bool) apply) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(label, style: TextStyle(color: c.ink, fontSize: 15)),
          value: value,
          onChanged: (v) => _update(apply(v)),
        );
    return _section(
      c,
      title: 'Qué mostrar',
      child: Column(
        children: [
          toggle('Precio', _style.showPrice, (v) => _style.copyWith(showPrice: v)),
          toggle('Unidades disponibles', _style.showExactStock, (v) => _style.copyWith(showExactStock: v)),
          toggle('Descripción', _style.showDescription, (v) => _style.copyWith(showDescription: v)),
          toggle('Categoría', _style.showCategory, (v) => _style.copyWith(showCategory: v)),
          toggle('Código o referencia', _style.showCode, (v) => _style.copyWith(showCode: v)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Row(
              children: [
                Flexible(child: Text('Pie "Hecho con Stockealo"', style: TextStyle(color: c.ink, fontSize: 15))),
                if (!_pro) ...[
                  const SizedBox(width: AppSpace.xs),
                  const ProCrown(),
                ],
              ],
            ),
            subtitle: _pro ? null : Text('Quitarlo es de Stockealo Pro', style: TextStyle(color: c.inkMuted)),
            value: _chosenStyle.showBranding,
            onChanged: (v) => _update(_style.copyWith(showBranding: v)),
          ),
        ],
      ),
    );
  }
}

/// Círculo de color para elegir el color del catálogo
class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final bool isBusiness;
  final bool locked;
  final String tooltip;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.isBusiness,
    required this.tooltip,
    required this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: locked ? '$tooltip · Stockealo Pro' : tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: locked ? '$tooltip, con Stockealo Pro' : tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? c.ink : Colors.transparent, width: 2),
            ),
            child: Container(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                  : locked
                      ? const Center(child: ProCrown(size: 16))
                      : (isBusiness ? const Icon(Icons.storefront_rounded, size: 16, color: Colors.white) : null),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opción que puede ser de Stockealo Pro: sin Pro lleva candado
class _ProChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  const _ProChip({required this.label, required this.selected, required this.locked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: locked ? '$label, con Stockealo Pro' : null,
      child: ChoiceChip(
        label: Text(label),
        avatar: locked ? const ProCrown(size: 18) : null,
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

/// Vista previa de la primera página: se actualiza con cada cambio
class _CatalogPreview extends StatelessWidget {
  final Business business;
  final CatalogStyle style;
  final Color accent;
  final List<Product> products;

  const _CatalogPreview({required this.business, required this.style, required this.accent, required this.products});

  @override
  Widget build(BuildContext context) {
    final dark = style.darkBackground;
    final page = dark ? AppPalette.paperDark : AppPalette.paper;
    final card = dark ? AppPalette.surfaceDark : AppPalette.surface;
    final ink = dark ? AppPalette.inkDark : AppPalette.ink;
    final muted = dark ? AppPalette.inkMutedDark : AppPalette.inkMuted;
    final line = dark ? AppPalette.lineDark : AppPalette.line;
    final imageBg = dark ? AppPalette.surfaceMutedDark : AppPalette.surfaceMuted;
    final price = dark ? Color.lerp(accent, Colors.white, 0.25)! : accent;
    final columns = style.itemsPerPage >= 4 ? 2 : 1;
    final title = style.title.isNotEmpty ? style.title : 'Catálogo de productos';

    return Semantics(
      label: 'Vista previa del catálogo',
      child: Center(
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: page,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: context.colors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    CatalogLogo(business: business, color: accent, size: 24),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(business.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          if (style.template == 'promo')
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                  color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.pill)),
                              child: Text(title.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: accent, fontSize: 7, fontWeight: FontWeight.w700)),
                            )
                          else
                            Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 8)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (style.template == 'lista')
                _priceList(card, ink, muted, line, imageBg, price)
              else
              GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 5,
                crossAxisSpacing: 5,
                childAspectRatio: columns == 2 ? 0.95 : (style.itemsPerPage == 1 ? 1.1 : 2.2),
                children: [
                  for (final prod in products)
                    if (style.template == 'vitrina')
                      _showcaseItem(prod, ink, muted, imageBg)
                    else
                    Container(
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: line, width: 0.6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: imageBg,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _thumb(prod, muted),
                                  if (style.template == 'promo')
                                    Positioned(top: 3, left: 3, child: _badge('OFERTA')),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(prod.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: ink, fontSize: 8, fontWeight: FontWeight.w700)),
                                if (style.showPrice)
                                  Text(CurrencyFormatter.format(prod.salePrice),
                                      style: TextStyle(color: price, fontSize: 8, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (style.whatsapp.isNotEmpty) 'WhatsApp ${style.whatsapp}',
                  if (style.showBranding) 'Hecho con Stockealo',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted, fontSize: 7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 5, fontWeight: FontWeight.w700)),
      );

  /// Plantilla "Vitrina": foto grande y precio en una píldora
  Widget _showcaseItem(Product prod, Color ink, Color muted, Color imageBg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: imageBg, borderRadius: BorderRadius.circular(8)),
            child: ClipRRect(borderRadius: BorderRadius.circular(8), child: _thumb(prod, muted)),
          ),
        ),
        const SizedBox(height: 2),
        Text(prod.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: ink, fontSize: 8, fontWeight: FontWeight.w700)),
        if (style.showPrice)
          Center(child: _badge(CurrencyFormatter.format(prod.salePrice))),
      ],
    );
  }

  /// Plantilla "Lista de precios": renglones con foto pequeña
  Widget _priceList(Color card, Color ink, Color muted, Color line, Color imageBg, Color price) {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: line, width: 0.6),
      ),
      child: Column(
        children: [
          for (var i = 0; i < products.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: line, width: 0.6))),
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(color: imageBg, borderRadius: BorderRadius.circular(4)),
                    child: ClipRRect(borderRadius: BorderRadius.circular(4), child: _thumb(products[i], muted)),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(products[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ink, fontSize: 8, fontWeight: FontWeight.w700)),
                  ),
                  if (style.showPrice)
                    Text(CurrencyFormatter.format(products[i].salePrice),
                        style: TextStyle(color: price, fontSize: 8, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _thumb(Product prod, Color muted) {
    final path = prod.photoPath;
    if (path != null && path.startsWith('http')) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        child: Image.network(path, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
      );
    }
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        child: Image.file(File(path), fit: BoxFit.cover, cacheWidth: 200),
      );
    }
    return Center(child: Icon(Icons.inventory_2_outlined, size: 14, color: muted));
  }
}

/// Lista para elegir a mano qué productos entran al catálogo
class _ProductPickerSheet extends StatefulWidget {
  final List<Product> products;
  final Set<String> initial;

  const _ProductPickerSheet({required this.products, required this.initial});

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  late final Set<String> _selected = {...widget.initial};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _query.toLowerCase();
    final visible = widget.products
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.category.toLowerCase().contains(q))
        .toList();
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.sm, AppSpace.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Elegir productos',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      if (_selected.length == widget.products.length) {
                        _selected.clear();
                      } else {
                        _selected.addAll(widget.products.map((p) => p.id));
                      }
                    }),
                    child: Text(_selected.length == widget.products.length ? 'Ninguno' : 'Todos'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: const InputDecoration(hintText: 'Buscar', prefixIcon: Icon(Icons.search_rounded)),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (_, i) {
                  final prod = visible[i];
                  return CheckboxListTile(
                    value: _selected.contains(prod.id),
                    onChanged: (v) => setState(() => v == true ? _selected.add(prod.id) : _selected.remove(prod.id)),
                    title: Text(prod.name, style: TextStyle(color: c.ink)),
                    subtitle: Text(
                      [if (prod.category.isNotEmpty) prod.category, CurrencyFormatter.format(prod.salePrice)].join(' · '),
                      style: TextStyle(color: c.inkMuted),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: SizedBox(
                width: double.infinity,
                child: PrimaryActionButton(
                  label: _selected.isEmpty ? 'Usar todos' : 'Listo · ${_selected.length}',
                  icon: Icons.check_rounded,
                  onPressed: () => Navigator.pop(context, _selected),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
