import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/filter_tabs.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/coupons.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../pro/data/pro_service.dart';
import '../../data/online_store_service.dart';

/// Cupones de la tienda (0.16.0, fase 7): el negocio crea los suyos («BIENVENIDA10»),
/// el comprador los escribe en el carrito y la nube revisa y descuenta. Una vez por
/// teléfono. Gratis: 1 activo; con Pro, varios.
class StoreCouponsScreen extends StatefulWidget {
  final Business business;
  final String storeUrl;

  /// Para las pruebas: de dónde salen los cupones (por defecto, la nube)
  final Future<List<Coupon>> Function()? loader;

  const StoreCouponsScreen({super.key, required this.business, required this.storeUrl, this.loader});

  static Future<void> open(BuildContext context, Business business, String storeUrl) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => StoreCouponsScreen(business: business, storeUrl: storeUrl)));

  @override
  State<StoreCouponsScreen> createState() => _StoreCouponsScreenState();
}

class _StoreCouponsScreenState extends State<StoreCouponsScreen> {
  List<Coupon>? _coupons;
  String? _error;

  OnlineStoreService get _service => OnlineStoreService.instance;
  String _money(num v) => CurrencyFormatter.formatIn(v, widget.business.currency);
  bool get _pro => ProService.instance.status.value.active;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await (widget.loader ?? () => _service.myCoupons(widget.business.id))();
      if (mounted) setState(() => _coupons = list);
    } catch (e) {
      if (mounted) setState(() => _error = e is CouponException ? e.message : 'No se pudieron cargar los cupones. Revisa tu conexión.');
    }
  }

  Future<void> _save(Coupon coupon) async {
    try {
      await _service.saveCoupon(widget.business.id, coupon);
      await _load();
    } on CouponException catch (e) {
      if (mounted) AppToast.showError(context, e.message);
    } catch (_) {
      if (mounted) AppToast.showError(context, 'No se pudo guardar el cupón. Revisa tu conexión.');
    }
  }

  Future<void> _edit([Coupon? current]) async {
    final saved = await AppSheet.show<Coupon>(
      context: context,
      title: current == null ? 'Nuevo cupón' : 'Editar cupón',
      subtitle: 'Tus clientes lo escriben en el carrito de la tienda.',
      builder: (ctx) => CouponForm(initial: current, currency: widget.business.currency),
    );
    if (saved != null) await _save(saved);
  }

  Future<void> _delete(Coupon coupon) async {
    final ok = await AppDialog.confirm(
      context: context,
      title: '¿Borrar el cupón ${coupon.code}?',
      message: 'Nadie más podrá usarlo. Los pedidos que ya lo usaron no cambian.',
      confirmText: 'Borrar',
      destructive: true,
    );
    if (!ok || coupon.id == null) return;
    try {
      await _service.deleteCoupon(widget.business.id, coupon.id!);
      await _load();
    } catch (_) {
      if (mounted) AppToast.showError(context, 'No se pudo borrar el cupón. Revisa tu conexión.');
    }
  }

  void _share(Coupon coupon) => Share.share(
        coupon.shareText(storeName: widget.business.name, storeUrl: widget.storeUrl, money: _money),
        subject: widget.business.name,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final coupons = _coupons;
    return Scaffold(
      appBar: AppBar(title: const Text('Cupones')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo cupón'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 96),
          children: [
            Text(
              _pro
                  ? 'Con Pro puedes tener varios cupones activos. Cada cliente usa un cupón una vez (por su celular).'
                  : 'Sin Pro puedes tener 1 cupón activo; con Pro, varios. Cada cliente usa un cupón una vez (por su celular).',
              style: AppText.small(context, color: c.inkMuted),
            ),
            const SizedBox(height: AppSpace.md),
            if (_error != null)
              AppCard(
                child: Column(
                  children: [
                    Text(_error!, style: AppText.body(context), textAlign: TextAlign.center),
                    TextButton(onPressed: _load, child: const Text('Reintentar')),
                  ],
                ),
              )
            else if (coupons == null)
              const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Center(child: CircularProgressIndicator()))
            else if (coupons.isEmpty)
              AppCard(
                child: Column(
                  children: [
                    Icon(Icons.local_offer_outlined, size: 36, color: c.accent),
                    const SizedBox(height: AppSpace.sm),
                    Text('Todavía no tienes cupones', style: AppText.title(context)),
                    const SizedBox(height: AppSpace.xs),
                    Text('Crea uno como «BIENVENIDA10» y compártelo por WhatsApp o Instagram.',
                        textAlign: TextAlign.center, style: AppText.small(context, color: c.inkMuted)),
                  ],
                ),
              )
            else
              for (final k in coupons) _tile(c, k),
          ],
        ),
      ),
    );
  }

  Widget _tile(StockealoColors c, Coupon k) {
    final details = [
      '${k.discountLabel(_money)} de descuento',
      if (k.minTotal > 0) 'desde ${_money(k.minTotal)}',
      k.usesLabel,
      if (k.expiresAt != null) 'hasta ${k.expiresAt!.day}/${k.expiresAt!.month}/${k.expiresAt!.year}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        onTap: () => _edit(k),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(child: Text(k.code, style: AppText.mono(context, weight: FontWeight.w700))),
                const SizedBox(width: AppSpace.sm),
                StatusPill(k.stateLabel, tone: k.usable ? AppTone.success : AppTone.neutral),
                const Spacer(),
                Switch(
                  value: k.active,
                  onChanged: (v) => _save(Coupon(
                    id: k.id,
                    code: k.code,
                    percent: k.percent,
                    amount: k.amount,
                    minTotal: k.minTotal,
                    maxUses: k.maxUses,
                    expiresAt: k.expiresAt,
                    active: v,
                  )),
                ),
              ],
            ),
            Text(details, style: AppText.small(context, color: c.inkMuted)),
            const SizedBox(height: AppSpace.xs),
            Wrap(
              spacing: AppSpace.sm,
              children: [
                TextButton.icon(
                  onPressed: () => _share(k),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Compartir cupón'),
                ),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: k.code));
                    AppToast.showSuccess(context, 'Código copiado.');
                  },
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copiar'),
                ),
                TextButton.icon(
                  onPressed: () => _delete(k),
                  icon: Icon(Icons.delete_outline, size: 18, color: c.danger),
                  label: Text('Borrar', style: TextStyle(color: c.danger)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// El formulario de un cupón de la tienda: código, % o valor, mínimo, usos y vencimiento
class CouponForm extends StatefulWidget {
  final Coupon? initial;
  final String currency;
  const CouponForm({super.key, this.initial, required this.currency});

  @override
  State<CouponForm> createState() => _CouponFormState();
}

class _CouponFormState extends State<CouponForm> {
  late final _code = TextEditingController(text: widget.initial?.code ?? '');
  late final _value = TextEditingController(text: _num(widget.initial?.percent ?? widget.initial?.amount));
  late final _min = TextEditingController(text: _num(widget.initial?.minTotal == 0 ? null : widget.initial?.minTotal));
  late final _uses = TextEditingController(text: widget.initial?.maxUses?.toString() ?? '');
  late bool _percent = widget.initial?.amount == null;
  late DateTime? _expires = widget.initial?.expiresAt;
  String? _codeError;
  String? _valueError;

  static String _num(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : '$v');

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _min.dispose();
    _uses.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expires ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _expires = DateTime(picked.year, picked.month, picked.day, 23, 59));
  }

  void _submit() {
    final code = CouponText.normalize(_code.text);
    final value = double.tryParse(_value.text.replaceAll(RegExp(r'[^0-9.]'), ''));
    setState(() {
      _codeError = CouponText.validStoreCode(code) ? null : CouponText.error('invalid_code');
      _valueError = value == null || value <= 0 || (_percent && value > 100)
          ? (_percent ? 'Escribe un porcentaje de 1 a 100.' : 'Escribe el valor del descuento.')
          : null;
    });
    if (_codeError != null || _valueError != null) return;
    Navigator.pop(
      context,
      Coupon(
        id: widget.initial?.id,
        code: code,
        percent: _percent ? value : null,
        amount: _percent ? null : value,
        minTotal: double.tryParse(_min.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0,
        maxUses: int.tryParse(_uses.text.trim()),
        expiresAt: _expires,
        active: widget.initial?.active ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = _expires;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _code,
          autofocus: widget.initial == null,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')), LengthLimitingTextInputFormatter(24)],
          decoration: InputDecoration(labelText: 'Código', hintText: 'BIENVENIDA10', errorText: _codeError),
        ),
        const SizedBox(height: AppSpace.md),
        FilterTabs<bool>(
          options: const {true: 'Porcentaje', false: 'Valor fijo'},
          value: _percent,
          onChanged: (v) => setState(() => _percent = v),
        ),
        const SizedBox(height: AppSpace.sm),
        TextField(
          controller: _value,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: _percent ? 'Descuento' : 'Valor del descuento',
            suffixText: _percent ? '%' : null,
            prefixText: _percent ? null : r'$ ',
            errorText: _valueError,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: _min,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Compra mínima (opcional)', prefixText: r'$ '),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: _uses,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Cuántas veces en total (opcional)', hintText: 'Vacío = sin límite'),
        ),
        const SizedBox(height: AppSpace.sm),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(e == null ? 'Sin vencimiento' : 'Vence el ${e.day}/${e.month}/${e.year}'),
          trailing: e == null
              ? TextButton(onPressed: _pickDate, child: const Text('Poner fecha'))
              : IconButton(tooltip: 'Quitar la fecha', onPressed: () => setState(() => _expires = null), icon: const Icon(Icons.close)),
          onTap: _pickDate,
        ),
        Text('Cada cliente lo usa una vez: la tienda le pide su celular.', style: AppText.small(context, color: c.inkMuted)),
        const SizedBox(height: AppSpace.lg),
        FilledButton(onPressed: _submit, child: const Text('Guardar cupón')),
      ],
    );
  }
}
