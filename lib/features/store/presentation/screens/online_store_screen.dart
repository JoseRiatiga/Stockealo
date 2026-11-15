import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/design/content_width.dart';
import '../../../../core/design/phone_field.dart';
import '../../../../core/design/primary_action_button.dart';
import '../../../../core/design/pro_crown.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/countries.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/models/business.dart';
import '../../../pro/data/pro_service.dart';
import '../../../pro/presentation/widgets/pro_upsell_sheet.dart';
import '../../data/online_store_service.dart';
import '../../../../core/design/status_pill.dart';
import '../../../products/data/product_image_service.dart';
import '../../../../core/design/filter_tabs.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/design/app_card.dart';
import '../../../../store_web/store_page.dart';
import '../../../products/data/product_repository.dart';
import '../../../../core/services/maintenance_service.dart';
import '../../../../core/design/app_time_picker.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../products/data/product_templates.dart';
import '../widgets/store_qr_sheet.dart';

/// Tienda en línea (lugar del menú): publica el catálogo en stockealo.online/tienda/<slug> con
/// carrito; los pedidos llegan por WhatsApp (Stockealo Pro).
class OnlineStoreScreen extends StatefulWidget {
  final Business business;

  /// Dentro del marco de la app (lugar del menú): sin barra propia, el encabezado único pone el título
  final bool embedded;

  const OnlineStoreScreen({super.key, required this.business, this.embedded = false});

  static Future<void> open(BuildContext context, Business business) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => OnlineStoreScreen(business: business)));

  @override
  State<OnlineStoreScreen> createState() => _OnlineStoreScreenState();
}

class _OnlineStoreScreenState extends State<OnlineStoreScreen> {
  final _service = OnlineStoreService.instance;
  final _slugController = TextEditingController();
  /// WhatsApp de pedidos con prefijo (+573001234567); null si está vacío o mal escrito
  String? _whatsapp;
  String? _initialWhatsapp;
  final _welcomeController = TextEditingController();
  final _heroController = TextEditingController();
  final _paymentController = TextEditingController();

  /// Hashtags propios para Instagram (0.16.0, fase 3)
  final _hashtagsController = TextEditingController();
  String _template = StoreTemplate.classic;

  /// Personalizar tienda (0.16.0): color, modo oscuro, destacados y horario
  StoreLook _look = StoreLook.none;

  OnlineStoreConfig? _saved;
  bool _enabled = true;
  bool _showStock = false;
  bool _heroPhotos = true;

  /// Portada (0.15.0): fotos de productos (solo Moda), foto propia o sin foto
  String _cover = _coverProducts;
  String? _coverUrl;
  bool _uploadingCover = false;
  static const _coverProducts = 'PRODUCTOS';
  static const _coverOwn = 'PROPIA';
  static const _coverNone = 'NINGUNA';
  bool _pro = false;
  bool _cloudSync = true;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    ProService.instance.status.addListener(_onProChanged);
    ProService.instance.refresh(widget.business.id);
    _pro = ProService.instance.status.value.active;
    _load();
  }

  void _onProChanged() {
    if (mounted) setState(() => _pro = ProService.instance.status.value.active);
  }

  @override
  void dispose() {
    ProService.instance.status.removeListener(_onProChanged);
    _slugController.dispose();
    _welcomeController.dispose();
    _heroController.dispose();
    _paymentController.dispose();
    _hashtagsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final cloud = await SupabaseService.instance.isCloudSyncEnabled();
      final saved = await _service.getMine(widget.business.id);
      if (!mounted) return;
      setState(() {
        _cloudSync = cloud;
        _saved = saved;
        _slugController.text = saved?.slug ?? OnlineStoreService.suggestSlug(widget.business.name);
        _initialWhatsapp = saved != null ? '+${saved.whatsapp}' : AuthRepository.instance.currentUser?.phone?.trim();
        _whatsapp = PhoneNumbers.toE164(_initialWhatsapp ?? '', country: countryByCode(widget.business.country));
        _welcomeController.text = saved?.welcome ?? '';
        _enabled = saved?.enabled ?? true;
        _showStock = saved?.showStock ?? false;
        _heroPhotos = saved?.heroPhotos ?? true;
        // Sin tienda todavía: la plantilla y el aviso +18 que le quedan a su tipo de negocio
        final suggested = ProductTemplate.suggestedFor(widget.business.icon);
        _template = saved?.template ?? suggested?.storeTemplate ?? StoreTemplate.classic;
        _coverUrl = saved?.heroImageUrl;
        _cover = _coverUrl != null
            ? _coverOwn
            : (_template == StoreTemplate.fashion && _heroPhotos ? _coverProducts : _coverNone);
        _heroController.text = saved?.heroTitle ?? '';
        _look = saved?.look ?? StoreLook(adult: suggested?.adult ?? false);
        _paymentController.text = _look.payment ?? '';
        _hashtagsController.text = _look.hashtags.join(' ');
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _turnOnCloud() async {
    await SupabaseService.instance.setCloudSyncEnabled(true);
    if (mounted) setState(() => _cloudSync = true);
    final result = await SupabaseService.instance.syncToCloud();
    if (mounted) {
      AppToast.show(
        context,
        message: result.success ? 'Listo: tus productos se están subiendo a la nube.' : 'No se pudieron subir ahora; se reintentará solo.',
        type: result.success ? ToastType.success : ToastType.warning,
      );
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final slug = _slugController.text.trim().toLowerCase();
    if (!OnlineStoreService.isValidSlug(slug)) {
      AppToast.show(context,
          message: 'La dirección debe tener de 3 a 40 letras sin tildes, números o guiones.', type: ToastType.warning);
      return;
    }
    final phone = _whatsapp?.replaceAll('+', '');
    if (phone == null || phone.isEmpty) {
      AppToast.show(context, message: 'Revisa el número de WhatsApp que recibe los pedidos.', type: ToastType.warning);
      return;
    }
    if (_enabled && !_pro) {
      final result = await ProUpsellSheet.show(
        context,
        business: widget.business,
        title: 'Tu tienda en línea',
        message: 'Publica tu catálogo con carrito en stockealo.online y recibe los pedidos por WhatsApp.',
        highlight: ProBenefit.onlineStore,
      );
      if (result != ProUpsellResult.pro || !mounted) return;
    }
    if (_cover == _coverOwn && _coverUrl == null) {
      AppToast.show(context, message: 'Sube tu foto de portada o elige otra opción.', type: ToastType.warning);
      return;
    }
    setState(() => _saving = true);
    try {
      final hadCover = _saved?.heroImageUrl != null;
      final saved = await _service.save(
        businessId: widget.business.id,
        slug: slug,
        enabled: _enabled,
        whatsapp: phone,
        welcome: _welcomeController.text,
        showStock: _showStock,
        heroPhotos: _template == StoreTemplate.fashion ? _cover == _coverProducts : _heroPhotos,
        heroImageUrl: _cover == _coverOwn ? _coverUrl : null,
        template: _template,
        heroTitle: _heroController.text.trim().isEmpty ? null : _heroController.text.trim(),
      );
      // Se quitó la foto propia: el archivo ya no se usa y se borra (regla de archivos sin uso)
      if (hadCover && saved.heroImageUrl == null) {
        await SupabaseService.instance.removeStorageFiles('product-images', widget.business.id, prefix: _coverFile);
        _coverUrl = null;
      }
      // Personalizar tienda (0.16.0): si la nube aún no lo tiene, lo demás queda guardado
      var lookSaved = true;
      try {
        _look = await _service.saveLook(businessId: widget.business.id, look: _lookToSave);
      } catch (e) {
        lookSaved = false;
        if (mounted) AppToast.show(context, message: '$e', type: ToastType.warning);
      }
      if (!mounted) return;
      setState(() => _saved = saved);
      if (lookSaved) {
        AppToast.show(context,
            message: saved.enabled ? 'Tu tienda está publicada.' : 'Guardado. La tienda está apagada.', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Nombre del archivo de la portada en la nube (uno por negocio: al cambiarla se reemplaza)
  static const _coverFile = 'store-cover';

  Future<void> _pickCover() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 85);
    if (file == null || !mounted) return;
    setState(() => _uploadingCover = true);
    try {
      final url = await ProductImageService.instance.uploadBytes(
        businessId: widget.business.id,
        productId: _coverFile,
        bytes: await file.readAsBytes(),
        mimeType: file.mimeType,
      );
      if (mounted) {
        setState(() {
          _coverUrl = url;
          _cover = _coverOwn;
        });
        AppToast.show(context, message: 'Foto lista. Toca Guardar para publicarla.', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  /// Portada: fotos de productos (Moda), foto propia o sin foto
  Widget _coverPicker(StockealoColors c) {
    final fashion = _template == StoreTemplate.fashion;
    final options = {
      if (fashion) _coverProducts: 'Fotos de productos',
      _coverOwn: 'Mi propia foto',
      _coverNone: fashion ? 'Sin fotos' : 'Solo el color',
    };
    final value = options.containsKey(_cover) ? _cover : _coverNone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('PORTADA', padding: EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.sm)),
        FilterTabs<String>(
          wrap: true,
          options: options,
          value: value,
          onChanged: (v) => setState(() => _cover = v),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          switch (value) {
            _coverProducts => 'Fotos pequeñas de tus productos junto al título.',
            _coverOwn => 'Tu logo en grande, un banner o una foto del local. Se ve ancha y baja, para que los productos queden a la vista.',
            _ => fashion ? 'Solo el título y el mensaje de bienvenida.' : 'La franja con el color de tu negocio y tu logo.',
          },
          style: AppText.caption(context),
        ),
        if (value == _coverOwn) ...[
          const SizedBox(height: AppSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: AspectRatio(
              aspectRatio: 3,
              child: _coverUrl == null
                  ? ColoredBox(
                      color: c.surfaceMuted,
                      child: Center(child: Icon(Icons.image_outlined, color: c.inkFaint, size: 32)),
                    )
                  : Image.network(_coverUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(color: c.surfaceMuted)),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            onPressed: _uploadingCover ? null : _pickCover,
            icon: _uploadingCover
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_outlined, size: 18),
            label: Text(_coverUrl == null ? 'Subir foto' : 'Cambiar foto'),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Personalizar tienda (0.16.0)
  // ---------------------------------------------------------------------------

  static IconData _templateIcon(String t) => switch (t) {
        StoreTemplate.fashion => Icons.checkroom_outlined,
        StoreTemplate.market => Icons.local_grocery_store_outlined,
        StoreTemplate.menu => Icons.restaurant_menu_outlined,
        StoreTemplate.boutique => Icons.diamond_outlined,
        _ => Icons.storefront_outlined,
      };

  /// Las 5 plantillas, de a dos por fila
  Widget _templatePicker(StockealoColors c) => LayoutBuilder(
        builder: (context, box) {
          final w = (box.maxWidth - AppSpace.sm) / 2;
          return Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final t in StoreTemplate.all)
                SizedBox(
                  width: box.maxWidth < 360 ? box.maxWidth : w,
                  child: Semantics(
                    button: true,
                    selected: _template == t,
                    child: Material(
                      color: c.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control + 2),
                        side: BorderSide(color: _template == t ? c.accent : c.line, width: _template == t ? 2 : 1),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.control + 2),
                        onTap: () => setState(() => _template = t),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpace.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(_templateIcon(t), size: 18, color: _template == t ? c.accent : c.inkMuted),
                                  const SizedBox(width: AppSpace.sm),
                                  Expanded(child: Text(StoreTemplate.label(t), style: AppText.body(context, weight: FontWeight.w700))),
                                  if (ProductTemplate.suggestedFor(widget.business.icon)?.storeTemplate == t)
                                    const StatusPill('Sugerida', tone: AppTone.accent, compact: true),
                                ],
                              ),
                              const SizedBox(height: AppSpace.xs),
                              Text(StoreTemplate.description(t), style: AppText.caption(context)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );

  Widget _personalize(StockealoColors c) {
    final fashion = _template == StoreTemplate.fashion;
    final schedule = _look.schedule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.lg),
        const SectionLabel('PERSONALIZAR', padding: EdgeInsets.only(bottom: AppSpace.sm)),
        Text('Color de la tienda', style: AppText.body(context, weight: FontWeight.w600)),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('El del negocio'),
              selected: _look.accent == null,
              onSelected: (_) => setState(() => _look = _look.copyWith(clearAccent: true)),
            ),
            for (final e in AppPalette.businessColors.entries)
              Tooltip(
                message: e.key,
                child: InkResponse(
                  onTap: () => setState(() => _look = _look.copyWith(accent: AppPalette.toHex(e.value))),
                  radius: 22,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: e.value,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _look.accent == AppPalette.toHex(e.value) ? c.ink : c.line,
                        width: _look.accent == AppPalette.toHex(e.value) ? 3 : 1,
                      ),
                    ),
                    child: _look.accent == AppPalette.toHex(e.value) ? Icon(Icons.check, size: 18, color: c.onAccent) : null,
                  ),
                ),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Aviso +18', style: AppText.body(context)),
          subtitle: Text('Al entrar pregunta «¿Tienes 18 años o más?». Para licores y vapers.', style: AppText.small(context)),
          value: _look.adult,
          onChanged: (v) => setState(() => _look = _look.copyWith(adult: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Modo oscuro', style: AppText.body(context)),
          subtitle: Text(fashion ? 'Moda siempre es oscura.' : 'Fondo oscuro con tu color.', style: AppText.small(context)),
          value: fashion || _look.dark,
          onChanged: fashion ? null : (v) => setState(() => _look = _look.copyWith(dark: v)),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.star_outline),
          title: Text('Destacados', style: AppText.body(context)),
          subtitle: Text(
            _look.featured.isEmpty
                ? 'Hasta ${StoreLook.maxFeatured} productos que salen primero'
                : '${_look.featured.length} ${_look.featured.length == 1 ? 'elegido' : 'elegidos'}: salen primero',
            style: AppText.small(context),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickFeatured,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: Text('Horario', style: AppText.body(context)),
          subtitle: Text(
            schedule == null ? 'Muestra «Abierto» o «Cerrado». Fuera del horario los pedidos llegan con aviso.' : schedule.text,
            style: AppText.small(context),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editSchedule,
        ),
        const SizedBox(height: AppSpace.sm),
        TextField(
          controller: _paymentController,
          maxLength: 300,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Datos de pago (opcional)',
            hintText: 'Ej.: Nequi 300 123 4567 a nombre de Rosa',
            helperText: 'Salen al final del pedido, para que el cliente sepa cómo pagarte.',
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        TextField(
          controller: _hashtagsController,
          maxLines: 2,
          minLines: 1,
          decoration: InputDecoration(
            labelText: 'Tus hashtags (opcional)',
            hintText: '${StoreLook.nameHashtag(widget.business.name) ?? '#MiNegocio'} #Domicilios',
            helperText: 'Salen en el texto de Instagram, junto a los sugeridos para tu tipo de negocio.',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton.icon(
          onPressed: _preview,
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: const Text('Vista previa'),
        ),
      ],
    );
  }

  StoreLook get _lookToSave {
    final pay = _paymentController.text.trim();
    final look = _look.copyWith(hashtags: StoreLook.parseHashtags(_hashtagsController.text));
    return pay.isEmpty ? look.copyWith(clearPayment: true) : look.copyWith(payment: pay);
  }

  Future<void> _pickFeatured() async {
    final products = (await ProductRepository.instance.getAllProducts(widget.business.id)).where((p) => p.stock > 0).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    final picked = [..._look.featured];
    var query = '';
    final ok = await AppSheet.show<bool>(
      context: context,
      title: 'Destacados',
      subtitle: 'Elige hasta ${StoreLook.maxFeatured}. Salen primero, en el orden en que los eliges.',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final shown = products.where((p) => query.isEmpty || p.name.toLowerCase().contains(query)).take(60).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                decoration: const InputDecoration(hintText: 'Buscar producto', prefixIcon: Icon(Icons.search_outlined)),
                onChanged: (v) => setLocal(() => query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: AppSpace.sm),
              if (products.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Text('No tienes productos con stock.', textAlign: TextAlign.center, style: AppText.body(ctx)),
                ),
              for (final p in shown)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: picked.contains(p.id),
                  title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: picked.contains(p.id) ? Text('N.º ${picked.indexOf(p.id) + 1}') : null,
                  onChanged: (v) => setLocal(() {
                    if (v == true) {
                      if (picked.length >= StoreLook.maxFeatured) {
                        AppToast.show(ctx, message: 'Máximo ${StoreLook.maxFeatured} destacados.', type: ToastType.warning);
                        return;
                      }
                      picked.add(p.id);
                    } else {
                      picked.remove(p.id);
                    }
                  }),
                ),
              const SizedBox(height: AppSpace.md),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Listo · ${picked.length} de ${StoreLook.maxFeatured}')),
            ],
          );
        },
      ),
    );
    if (ok == true && mounted) setState(() => _look = _look.copyWith(featured: picked));
  }

  Future<void> _editSchedule() async {
    final current = _look.schedule;
    final days = {...?current?.days};
    if (days.isEmpty) days.addAll([1, 2, 3, 4, 5, 6]);
    var open = current?.open ?? '07:00';
    var close = current?.close ?? '20:00';
    TimeOfDay time(String hhmm) => TimeOfDay(hour: int.parse(hhmm.split(':')[0]), minute: int.parse(hhmm.split(':')[1]));
    String hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final result = await AppSheet.show<String>(
      context: context,
      title: 'Horario de la tienda',
      subtitle: 'Fuera del horario la tienda dice «Cerrado», pero los pedidos llegan igual con aviso.',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Días', style: AppText.body(ctx, weight: FontWeight.w600)),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.xs + 2,
              runSpacing: AppSpace.xs + 2,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(StoreSchedule.dayShort[d - 1]),
                    tooltip: const ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'][d - 1],
                    selected: days.contains(d),
                    showCheckmark: false,
                    onSelected: (v) => setLocal(() => v ? days.add(d) : days.remove(d)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                    label: Text('Abre ${StoreSchedule.hourText(open)}'),
                    onPressed: () async {
                      final t = await showAppTimePicker(ctx, initialTime: time(open), helpText: 'Hora de abrir');
                      if (t != null) setLocal(() => open = hhmm(t));
                    },
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.nightlight_outlined, size: 18),
                    label: Text('Cierra ${StoreSchedule.hourText(close)}'),
                    onPressed: () async {
                      final t = await showAppTimePicker(ctx, initialTime: time(close), helpText: 'Hora de cerrar');
                      if (t != null) setLocal(() => close = hhmm(t));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(onPressed: days.isEmpty ? null : () => Navigator.pop(ctx, 'ok'), child: const Text('Listo')),
            if (current != null)
              TextButton(onPressed: () => Navigator.pop(ctx, 'clear'), child: const Text('Quitar el horario')),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _look = result == 'clear'
        ? _look.copyWith(clearSchedule: true)
        : _look.copyWith(schedule: StoreSchedule(days: days, open: open, close: close)));
  }

  /// Cómo queda, con lo que está en pantalla y sin guardar: la tienda publicada con el
  /// diseño nuevo, o (si aún no está publicada) con los productos de este celular
  Future<void> _preview() async {
    final slug = _slugController.text.trim().toLowerCase();
    PublicStore? base;
    try {
      if (_saved?.enabled == true) base = await _service.getPublic(_saved!.slug);
    } catch (_) {}
    base ??= await _localStore(slug);
    if (!mounted) return;
    final store = base.copyWith(
      template: _template,
      heroTitle: _heroController.text.trim().isEmpty ? null : _heroController.text.trim(),
      heroPhotos: _template == StoreTemplate.fashion ? _cover == _coverProducts : _heroPhotos,
      heroImageUrl: _cover == _coverOwn ? _coverUrl : null,
      welcome: _welcomeController.text.trim(),
      look: _lookToSave,
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Vista previa'), actions: const [
            Padding(padding: EdgeInsets.only(right: AppSpace.md), child: StatusPill('Sin guardar', tone: AppTone.warning)),
          ]),
          body: StorePage(slug: store.slug, loader: (_) async => store, maintenanceLoader: () async => MaintenanceState.none),
        ),
      ),
    );
  }

  Future<PublicStore> _localStore(String slug) async {
    final products = await ProductRepository.instance.getAllProducts(widget.business.id);
    return PublicStore(
      slug: slug.isEmpty ? 'mi-tienda' : slug,
      whatsapp: _whatsapp?.replaceAll('+', '') ?? '',
      businessName: widget.business.name,
      currency: widget.business.currency,
      color: widget.business.color,
      logoUrl: (widget.business.logoUrl ?? '').startsWith('https://') ? widget.business.logoUrl : null,
      products: [
        for (final p in products)
          if (p.stock > 0 && p.salePrice > 0)
            StoreProduct(
              id: p.id,
              name: p.name,
              category: p.category.trim(),
              price: p.salePrice,
              description: (p.description ?? '').trim().isEmpty ? null : p.description!.trim(),
              imageUrl: (p.photoPath ?? '').startsWith('https://') ? p.photoPath : null,
              oldPrice: (p.comparePrice ?? 0) > p.salePrice ? p.comparePrice : null,
              few: p.stock <= 3,
            ),
      ],
    );
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) AppToast.show(context, message: 'Enlace copiado', type: ToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: widget.embedded ? null : AppBar(title: const Text('Tienda en línea')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _errorView(c)
              : ContentWidth(
                  child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xxl),
                  children: [
                    if (_saved != null && _saved!.enabled && _pro) ...[
                      _liveCard(c, _saved!),
                      const SizedBox(height: AppSpace.md),
                    ] else ...[
                      _introCard(c),
                      const SizedBox(height: AppSpace.md),
                    ],
                    if (!_cloudSync) ...[
                      _cloudCard(c),
                      const SizedBox(height: AppSpace.md),
                    ],
                    _formCard(c),
                  ],
                ),
                ),
    );
  }

  Widget _errorView(StockealoColors c) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center, style: AppText.body(context, color: c.inkMuted)),
              const SizedBox(height: AppSpace.md),
              OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );

  Widget _card(StockealoColors c, {required Widget child, Color? color}) => AppCard(color: color, child: child);

  Widget _introCard(StockealoColors c) => _card(
        c,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.storefront_outlined, color: c.accent, size: 28),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text('Tu catálogo con carrito', style: AppText.title(context)),
                      ),
                      if (!_pro) ...[const SizedBox(width: AppSpace.sm), const ProCrown()],
                    ],
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    'Tus clientes ven los productos con stock, eligen y te mandan el pedido por WhatsApp. '
                    'No muestra costos ni datos de tus clientes.',
                    style: AppText.small(context, color: c.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  /// La tienda publicada (diseño nuevo, 0.15.0): el enlace, su estado y qué hacer
  Widget _liveCard(StockealoColors c, OnlineStoreConfig store) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: c.successSoft, borderRadius: BorderRadius.circular(AppRadius.tile)),
                  child: Icon(Icons.storefront_outlined, color: c.success),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tu tienda', style: AppText.title(context)),
                      const SizedBox(height: 2),
                      SelectableText(store.url, maxLines: 1, style: AppText.small(context, weight: FontWeight.w600, color: c.accent)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                const StatusPill('Publicada', tone: AppTone.success, dot: true),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse(store.url), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_outlined, size: 18),
                  label: const Text('Ver mi tienda'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Share.share('Mira mi tienda y haz tu pedido aquí: ${store.url}',
                      subject: widget.business.name),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Compartir'),
                ),
                IconButton.outlined(
                  tooltip: 'Copiar el enlace',
                  onPressed: () => _copyLink(store.url),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                ),
                // QR para el mostrador (0.16.0, fase 3)
                OutlinedButton.icon(
                  onPressed: () => StoreQrSheet.show(context, business: widget.business, store: store),
                  icon: const Icon(Icons.qr_code_2_outlined, size: 18),
                  label: const Text('QR'),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _cloudCard(StockealoColors c) => _card(
        c,
        color: c.warningSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Activa la nube para tu tienda', style: AppText.body(context, weight: FontWeight.w700)),
            const SizedBox(height: AppSpace.xs),
            Text(
              'La tienda muestra los productos guardados en la nube. Hoy tu inventario está solo en este celular.',
              style: AppText.small(context),
            ),
            const SizedBox(height: AppSpace.sm),
            TextButton(onPressed: _turnOnCloud, child: const Text('Activar la nube y subir mis productos')),
          ],
        ),
      );

  Widget _formCard(StockealoColors c) => _card(
        c,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Tienda encendida', style: AppText.body(context, weight: FontWeight.w600)),
              subtitle: Text('Apágala cuando no quieras recibir pedidos', style: AppText.small(context, color: c.inkMuted)),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _slugController,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Dirección de tu tienda',
                prefixText: 'tienda/',
                helperText: '$storeBaseUrl/${_slugController.text.trim().toLowerCase()}',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            PhoneField(
              initialValue: _initialWhatsapp,
              defaultCountry: countryByCode(widget.business.country),
              label: 'WhatsApp de pedidos',
              required: true,
              onChanged: (v) => _whatsapp = v.isValid ? v.e164 : null,
            ),
            const SizedBox(height: AppSpace.lg),
            // Cómo se ve la tienda: Clásica, Moda, Mercado, Menú o Boutique (0.16.0)
            const SectionLabel('PLANTILLA', padding: EdgeInsets.only(bottom: AppSpace.sm)),
            _templatePicker(c),
            if (_template == StoreTemplate.fashion) ...[
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _heroController,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Título de la portada (opcional)',
                  hintText: 'Ej.: Chaquetas y abrigos para el frío',
                ),
              ),
            ],
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _welcomeController,
              maxLength: 280,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Mensaje de bienvenida (opcional)',
                hintText: 'Ej.: Domicilios gratis en el barrio',
              ),
            ),
            _coverPicker(c),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Mostrar unidades disponibles', style: AppText.body(context)),
              subtitle: Text(
                'Si lo apagas, la tienda solo avisa «Quedan pocas, pide pronto» cuando quedan 3 o menos.',
                style: AppText.small(context),
              ),
              value: _showStock,
              onChanged: (v) => setState(() => _showStock = v),
            ),
            _personalize(c),
            const SizedBox(height: AppSpace.md),
            PrimaryActionButton(
              label: _saving ? 'Guardando…' : (_saved == null ? 'Publicar mi tienda' : 'Guardar cambios'),
              icon: Icons.storefront_outlined,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      );
}
