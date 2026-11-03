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

/// Inventario › Tienda: publica el catálogo en stockealo.online/tienda/<slug> con
/// carrito; los pedidos llegan por WhatsApp (Stockealo Pro).
class OnlineStoreScreen extends StatefulWidget {
  final Business business;

  const OnlineStoreScreen({super.key, required this.business});

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

  OnlineStoreConfig? _saved;
  bool _enabled = true;
  bool _showStock = false;
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
    setState(() => _saving = true);
    try {
      final saved = await _service.save(
        businessId: widget.business.id,
        slug: slug,
        enabled: _enabled,
        whatsapp: phone,
        welcome: _welcomeController.text,
        showStock: _showStock,
      );
      if (!mounted) return;
      setState(() => _saved = saved);
      AppToast.show(context,
          message: saved.enabled ? 'Tu tienda está publicada.' : 'Guardado. La tienda está apagada.', type: ToastType.success);
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
      appBar: AppBar(title: const Text('Tienda en línea')),
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
              Text(_loadError!, textAlign: TextAlign.center, style: TextStyle(color: c.inkMuted)),
              const SizedBox(height: AppSpace.md),
              OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );

  Widget _card(StockealoColors c, {required Widget child, Color? color}) => Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: color ?? c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: color == null ? Border.all(color: c.line) : null,
        ),
        child: child,
      );

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
                        child: Text('Tu catálogo con carrito',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
                      ),
                      if (!_pro) ...[const SizedBox(width: AppSpace.sm), const ProCrown()],
                    ],
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    'Tus clientes ven los productos con stock, eligen y te mandan el pedido por WhatsApp. '
                    'No muestra costos ni datos de tus clientes.',
                    style: TextStyle(fontSize: 13, height: 1.4, color: c.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _liveCard(StockealoColors c, OnlineStoreConfig store) => _card(
        c,
        color: c.successSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: c.success),
                const SizedBox(width: AppSpace.sm),
                Text('Tu tienda está publicada', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            SelectableText(store.url, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.accent)),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Share.share('Mira mi tienda y haz tu pedido aquí: ${store.url}',
                      subject: widget.business.name),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Compartir'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copyLink(store.url),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copiar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(store.url), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Ver'),
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
            Text('Activa la nube para tu tienda', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: AppSpace.xs),
            Text(
              'La tienda muestra los productos guardados en la nube. Hoy tu inventario está solo en este celular.',
              style: TextStyle(fontSize: 13, color: c.ink),
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
              title: Text('Tienda encendida', style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
              subtitle: Text('Apágala cuando no quieras recibir pedidos', style: TextStyle(color: c.inkMuted)),
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Mostrar unidades disponibles', style: TextStyle(color: c.ink)),
              value: _showStock,
              onChanged: (v) => setState(() => _showStock = v),
            ),
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
