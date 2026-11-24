import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design/status_pill.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/coupons.dart';
import '../core/utils/currency_formatter.dart';
import '../core/widgets/app_toast.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_widgets.dart';
import '../core/design/filter_tabs.dart';

/// Cupones de descuento para pagar Pro con Wompi (0.16.0, fase 7): se crean aquí, el
/// cliente los escribe en la pantalla Pro y el servidor fija el precio.
class AdminCouponsSection extends StatefulWidget {
  const AdminCouponsSection({super.key});

  @override
  State<AdminCouponsSection> createState() => _AdminCouponsSectionState();
}

/// Plazos para usarlo; null = sin vencimiento
const _validities = <int?>[null, 7, 30, 90];

class _AdminCouponsSectionState extends State<AdminCouponsSection> {
  final _admin = ProAdminService.instance;
  final _code = TextEditingController();
  final _value = TextEditingController();
  final _maxUses = TextEditingController();
  final _note = TextEditingController();

  bool _percent = true;
  final Set<String> _kinds = {'business', 'services'};
  bool _firstOnly = false;
  int? _validDays = 30;
  bool _saving = false;

  List<Coupon> _coupons = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _maxUses.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _admin.listCoupons();
      if (mounted) setState(() => _coupons = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(num v) => CurrencyFormatter.formatCOP(v.toDouble());

  Future<void> _create() async {
    final value = double.tryParse(_value.text.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (CouponText.normalize(_code.text).length < 4) {
      AppToast.showError(context, 'El código lleva de 4 a 32 letras, números o guiones.');
      return;
    }
    if (value == null || value <= 0 || (_percent && value > 90)) {
      AppToast.showError(context, _percent ? 'El porcentaje va de 1 a 90.' : 'Escribe el valor del descuento.');
      return;
    }
    if (_kinds.isEmpty) {
      AppToast.showError(context, 'Elige al menos un plan.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final code = await _admin.saveCoupon(
        code: CouponText.normalize(_code.text),
        percent: _percent ? value : null,
        amount: _percent ? null : value,
        kinds: _kinds.toList(),
        maxUses: int.tryParse(_maxUses.text.trim()),
        firstPurchaseOnly: _firstOnly,
        validDays: _validDays,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      _code.clear();
      _value.clear();
      _maxUses.clear();
      _note.clear();
      AppToast.showSuccess(context, 'Cupón $code creado.');
      await _load();
    } catch (e) {
      if (mounted) AppToast.showError(context, adminCouponError('$e'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AdminLoadState(
      loading: _loading,
      error: _error,
      empty: _coupons.isEmpty,
      emptyText: 'Todavía no hay cupones',
      emptyDetail: 'Un cupón da un descuento al pagar Pro en la app.',
      emptyIcon: Icons.local_offer_outlined,
      onRetry: _load,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminCard(child: _form(c)),
        const SizedBox(height: AppSpace.lg),
        Text('Cupones', style: TextStyle(fontSize: AppText.sizeTitle, fontWeight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: AppSpace.sm),
        if (state.blocking) state else for (final k in _coupons) _row(c, k),
      ],
    );
  }

  Widget _label(StockealoColors c, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Text(text, style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
      );

  Widget _form(StockealoColors c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Crear cupón de descuento', style: TextStyle(fontSize: AppText.sizeTitle, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: AppSpace.xs),
          Text('Sirve al pagar Pro con Wompi. Para regalar Pro completo, usa los códigos canjeables.',
              style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')), LengthLimitingTextInputFormatter(32)],
            decoration: const InputDecoration(labelText: 'Código', hintText: 'PRIMERMES30'),
          ),
          const SizedBox(height: AppSpace.md),
          _label(c, 'Descuento'),
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
              labelText: _percent ? 'Porcentaje (1 a 90)' : 'Valor en pesos',
              suffixText: _percent ? '%' : null,
              prefixText: _percent ? null : r'$ ',
            ),
          ),
          const SizedBox(height: AppSpace.md),
          _label(c, 'Planes'),
          Wrap(
            spacing: AppSpace.sm,
            children: [
              for (final k in const {'business': 'Pro', 'services': 'Pro Servicios'}.entries)
                FilterChip(
                  label: Text(k.value),
                  selected: _kinds.contains(k.key),
                  onSelected: (on) => setState(() => on ? _kinds.add(k.key) : _kinds.remove(k.key)),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          _label(c, 'Plazo para usarlo'),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final v in _validities)
                ChoiceChip(
                  label: Text(v == null ? 'Sin vencimiento' : '$v días'),
                  selected: _validDays == v,
                  onSelected: (_) => setState(() => _validDays = v),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _maxUses,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Cuántas veces en total (vacío = sin límite)'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Solo la primera compra'),
            subtitle: const Text('Para quien nunca ha pagado Pro'),
            value: _firstOnly,
            onChanged: (v) => setState(() => _firstOnly = v),
          ),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
          const SizedBox(height: AppSpace.md),
          FilledButton(onPressed: _saving ? null : _create, child: Text(_saving ? 'Creando…' : 'Crear cupón')),
        ],
      );

  Widget _row(StockealoColors c, Coupon k) {
    final tone = k.usable ? AppTone.success : AppTone.neutral;
    final plans = k.kinds.map((e) => e == 'services' ? 'Pro Servicios' : 'Pro').join(' y ');
    return AdminCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(k.code, style: AppText.mono(context, weight: FontWeight.w700))),
                    const SizedBox(width: AppSpace.sm),
                    StatusPill(k.stateLabel, tone: tone),
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '${k.discountLabel(_money)} en $plans · ${k.usesLabel}'
                  '${k.firstPurchaseOnly ? ' · solo primera compra' : ''}'
                  '${k.expiresAt != null ? ' · hasta ${k.expiresAt!.day}/${k.expiresAt!.month}/${k.expiresAt!.year}' : ''}',
                  style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted),
                ),
                if (k.note != null) Text(k.note!, style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint)),
              ],
            ),
          ),
          Switch(
            value: k.active,
            onChanged: (v) async {
              try {
                await _admin.setCouponActive(k.code, v);
                await _load();
              } catch (e) {
                if (mounted) AppToast.showError(context, adminCouponError('$e'));
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Mensaje para cada error al crear un cupón en el panel
String adminCouponError(String e) {
  if (e.contains('code_taken')) return 'Ya existe un código o cupón con ese nombre.';
  if (e.contains('invalid_code')) return 'El código lleva de 4 a 32 letras, números o guiones.';
  if (e.contains('admin_role_forbidden')) return 'Solo el dueño del panel puede crear cupones.';
  return 'No se pudo guardar el cupón. Inténtalo de nuevo.';
}
