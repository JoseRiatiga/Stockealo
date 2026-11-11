import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/design/country_flag.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/countries.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/currency_options.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../../core/widgets/image_source_picker_modal.dart';
import '../../../products/data/product_image_service.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/business_repository.dart';
import '../../models/business.dart';
import '../business_identity.dart';

/// Datos elegidos en la hoja "Nuevo negocio"
class NewBusinessData {
  final String name;
  final String country;
  final String currency;
  final String icon;
  final String color;

  // Solo al editar
  final String? description;

  /// Logo elegido (los bytes de la imagen) para subir al guardar
  final Uint8List? newLogoBytes;
  final String? newLogoMime;
  final bool removeLogo;
  final bool cashRegisterEnabled;


  const NewBusinessData({
    required this.name,
    required this.country,
    required this.currency,
    required this.icon,
    required this.color,
    this.description,
    this.newLogoBytes,
    this.newLogoMime,
    this.removeLogo = false,
    this.cashRegisterEnabled = false,
  });
}

/// Hoja inferior para crear un negocio: nombre, país (que sugiere la moneda),
/// vista previa del precio, tipo de negocio y color. Con [initial] edita un negocio
/// existente y suma descripción, logo y arqueo de caja.
class CreateBusinessSheet extends StatefulWidget {
  final Business? initial;

  const CreateBusinessSheet({super.key, this.initial});

  static Future<NewBusinessData?> show(BuildContext context, {Business? initial}) {
    return showModalBottomSheet<NewBusinessData>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CreateBusinessSheet(initial: initial),
    );
  }

  /// Edita un negocio: abre la hoja, sube el logo si cambió y guarda.
  /// Devuelve el negocio guardado, o null si el usuario canceló.
  static Future<Business?> edit(BuildContext context, Business business) async {
    final data = await show(context, initial: business);
    if (data == null || !context.mounted) return null;

    String? logoUrl;
    final bytes = data.newLogoBytes;
    if (bytes != null) {
      try {
        logoUrl = await ProductImageService.instance.uploadBytes(
          businessId: business.id,
          productId: 'logo',
          bytes: bytes,
          mimeType: data.newLogoMime,
        );
      } on ProductImageException catch (e) {
        if (context.mounted) AppToast.showWarning(context, 'No se pudo subir el logo: ${e.message}');
      }
    } else if (data.removeLogo) {
      logoUrl = '';
    }

    final saved = await BusinessRepository.instance.updateBusiness(
      id: business.id,
      name: data.name,
      currency: data.currency,
      description: data.description,
      country: data.country,
      icon: data.icon,
      color: data.color,
      logoUrl: logoUrl,
    );
    if (context.mounted) {
      AppToast.showSuccess(
        context,
        'Datos del negocio guardados',
      );
    }
    return saved;
  }

  @override
  State<CreateBusinessSheet> createState() => _CreateBusinessSheetState();
}

class _CreateBusinessSheetState extends State<CreateBusinessSheet> {
  late final _nameController = TextEditingController(text: widget.initial?.name);
  late final _descriptionController = TextEditingController(text: widget.initial?.description);
  late Country _country = widget.initial != null ? countryByCode(widget.initial!.country) : deviceCountry();
  late String _currency = widget.initial?.currency ?? _country.currency;
  late String _icon = widget.initial?.icon ?? kBusinessKinds.first.key;
  late String _colorKey = _colorKeyFor(widget.initial?.color);
  // La caja se enciende en Ajustes › Módulos (0.12.0); aquí se conserva lo que había
  late final bool _cashRegister = widget.initial?.cashRegisterEnabled ?? false;
  Uint8List? _newLogoBytes;
  String? _newLogoMime;
  bool _removeLogo = false;
  bool _triedSubmit = false;

  bool get _isEditing => widget.initial != null;

  static String _colorKeyFor(String? hex) {
    final color = AppPalette.fromHex(hex);
    for (final entry in AppPalette.businessColors.entries) {
      if (entry.value == color) return entry.key;
    }
    return AppPalette.businessColors.keys.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final hasLogo = !_removeLogo && (_newLogoBytes != null || (widget.initial?.logoUrl?.isNotEmpty ?? false));
    await ImageSourcePickerModal.show(
      context,
      title: 'Logo del negocio',
      hasExistingImage: hasLogo,
      subtitle: 'Se sube al guardar los cambios',
      onSelected: (source) async {
        final picked = await ImageHelper.pickBytes(source);
        if (picked != null && mounted) {
          setState(() {
            _newLogoBytes = picked.bytes;
            _newLogoMime = picked.mimeType;
            _removeLogo = false;
          });
        }
      },
      onRemove: () => setState(() {
        _newLogoBytes = null;
        _removeLogo = true;
      }),
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _triedSubmit = true);
      return;
    }
    Navigator.pop(
      context,
      NewBusinessData(
        name: name,
        country: _country.code,
        currency: _currency,
        icon: _icon,
        color: AppPalette.toHex(AppPalette.businessColors[_colorKey]!),
        description: _isEditing ? _descriptionController.text.trim() : null,
        newLogoBytes: _newLogoBytes,
        newLogoMime: _newLogoMime,
        removeLogo: _removeLogo,
        cashRegisterEnabled: _cashRegister,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = AppPalette.businessColors[_colorKey]!;
    final nameMissing = _triedSubmit && _nameController.text.trim().isEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(13)),
                    child:
                        Icon(businessKindFor(_icon).icon, color: Colors.white),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_isEditing ? 'Editar negocio' : 'Nuevo negocio',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(_isEditing ? 'Los cambios se ven en todo el equipo' : 'Podrás cambiar todo esto después',
                            style: TextStyle(color: c.inkMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xl),
              TextField(
                controller: _nameController,
                autofocus: !_isEditing,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Nombre del negocio',
                  hintText: 'Miscelánea Central',
                  errorText:
                      nameMissing ? 'Escribe el nombre de tu negocio' : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              DropdownButtonFormField<String>(
                key: ValueKey(_country.code),
initialValue: _country.code,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'País'),
                items: [
                  for (final country in kCountries)
                    DropdownMenuItem(
                        value: country.code,
                        child: CountryLabel(country: country, text: country.name)),
                ],
                onChanged: (code) => setState(() {
                  _country = countryByCode(code);
                  _currency = _country.currency;
                }),
              ),
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_currency),
initialValue: _currency,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Moneda'),
                      items: [
                        for (final option in kAvailableCurrencies
                            .where((o) => o.code != 'OTRA'))
                          DropdownMenuItem(
                              value: option.code, child: Text(option.code)),
                      ],
                      onChanged: (code) =>
                          setState(() => _currency = code ?? _currency),
                    ),
                  ),
                  const SizedBox(width: AppSpace.lg),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Así se verán tus precios: ',
                        style: TextStyle(color: c.inkMuted, fontSize: 13),
                        children: [
                          TextSpan(
                            text: CurrencyFormatter.formatIn(12500, _currency),
                            style: AppText.amount(context, size: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xl),
              BusinessIconField(
                selected: _icon,
                color: color,
                onSelected: (key) => setState(() => _icon = key),
              ),
              const SizedBox(height: AppSpace.xl),
              Text('Color',
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.md,
                runSpacing: AppSpace.md,
                children: [
                  for (final entry in AppPalette.businessColors.entries)
                    Semantics(
                      button: true,
                      selected: _colorKey == entry.key,
                      label: 'Color ${entry.key}',
                      child: GestureDetector(
                        onTap: () => setState(() => _colorKey = entry.key),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: entry.value,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _colorKey == entry.key
                                    ? c.ink
                                    : Colors.transparent,
                                width: 2.5),
                          ),
                          child: _colorKey == entry.key
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 18)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              if (_isEditing) ...[
                const SizedBox(height: AppSpace.xl),
                Text('Logo', style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    _logoPreview(color),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Text(
                        'Sale en el catálogo, los comprobantes y el selector de negocios',
                        style: TextStyle(fontSize: 13, color: c.inkMuted),
                      ),
                    ),
                    TextButton(onPressed: _pickLogo, child: const Text('Cambiar')),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                TextField(
                  controller: _descriptionController,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                    hintText: 'Abarrotes, papelería y regalos',
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.xxl),
              FilledButton(
                  onPressed: _submit, child: Text(_isEditing ? 'Guardar cambios' : 'Crear negocio')),
              const SizedBox(height: AppSpace.sm),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logoPreview(Color color) {
    const size = 52.0;
    final radius = BorderRadius.circular(14);
    final bytes = _newLogoBytes;
    if (bytes != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover),
      );
    }
    final path = _removeLogo ? null : widget.initial?.logoUrl;
    if (path != null && path.isNotEmpty) {
      return ProductImageView(imagePath: path, width: size, height: size, borderRadius: radius);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, borderRadius: radius),
      child: Icon(businessKindFor(_icon).icon, color: Colors.white),
    );
  }
}
