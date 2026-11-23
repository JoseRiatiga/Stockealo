import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/pro_crown.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/money_input.dart';
import '../../models/price_tier.dart';

/// «Precio por cantidad» en Editar producto (0.17.0, bloque B, Pro): hasta 3
/// escalones como «desde 12 unidades: $1.800». Vender los aplica solo.
class PriceTiersEditor extends StatefulWidget {
  final List<PriceTier> initial;
  final double salePrice;
  final bool enabled;

  /// Sin Pro (0.17.1) se puede armar y guardar, pero se aplica solo con Pro
  final bool pro;
  final ValueChanged<List<PriceTier>> onChanged;

  const PriceTiersEditor({
    super.key,
    required this.initial,
    required this.salePrice,
    required this.enabled,
    this.pro = true,
    required this.onChanged,
  });

  @override
  State<PriceTiersEditor> createState() => _PriceTiersEditorState();
}

class _Row {
  final qty = TextEditingController();
  final price = TextEditingController();

  void dispose() {
    qty.dispose();
    price.dispose();
  }
}

class _PriceTiersEditorState extends State<PriceTiersEditor> {
  final _rows = <_Row>[];

  bool get _noCents => CurrencyFormatter.noCents;

  @override
  void initState() {
    super.initState();
    for (final t in widget.initial) {
      _rows.add(_Row()
        ..qty.text = '${t.minQty}'
        ..price.text = _noCents ? MoneyInput.text(t.price) : t.price.toStringAsFixed(t.price % 1 == 0 ? 0 : 2));
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  double _parse(String text) => _noCents ? MoneyInput.parse(text) : (double.tryParse(text.trim().replaceAll(',', '.')) ?? 0);

  List<PriceTier> get _tiers => [
        for (final r in _rows) PriceTier(int.tryParse(r.qty.text.trim()) ?? 0, _parse(r.price.text)),
      ];

  void _changed() {
    widget.onChanged(PriceTier.clean(_tiers, basePrice: widget.salePrice));
    setState(() {});
  }

  /// Qué le pasa a un escalón que no sirve
  String? _problem(int i) {
    final t = _tiers[i];
    if (_rows[i].qty.text.trim().isEmpty && _rows[i].price.text.trim().isEmpty) return null;
    if (t.minQty < 2) return 'Desde 2 unidades o más';
    if (t.price <= 0) return 'Escribe el precio';
    if (widget.salePrice > 0 && t.price >= widget.salePrice) return 'Debe ser menor al precio normal';
    for (var j = 0; j < i; j++) {
      final o = _tiers[j];
      if (o.minQty == t.minQty) return 'Esa cantidad ya está';
      if (o.minQty < t.minQty && o.price <= t.price) return 'Con más unidades, el precio debe bajar';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(child: Text('Precio por cantidad (opcional)', style: AppText.body(context, weight: FontWeight.w700))),
            if (!widget.pro) ...[const SizedBox(width: AppSpace.xs), const ProCrown(size: 16)],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          widget.pro
              ? 'Por ejemplo, desde 12 unidades a un precio más bajo. Vender lo aplica solo y la tienda lo muestra.'
              : 'Arma tus precios ya. Se aplican en Vender y en tu tienda cuando tengas Stockealo Pro.',
          style: AppText.small(context, color: c.inkMuted),
        ),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _rows[i].qty,
                    enabled: widget.enabled,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Desde', suffixText: 'und.'),
                    onChanged: (_) => _changed(),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: TextField(
                    controller: _rows[i].price,
                    enabled: widget.enabled,
                    keyboardType: _noCents ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: _noCents ? MoneyInput.formatters : null,
                    decoration: InputDecoration(labelText: 'Precio c/u', prefixText: r'$ ', errorText: _problem(i)),
                    onChanged: (_) => _changed(),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar',
                  onPressed: widget.enabled
                      ? () {
                          _rows.removeAt(i).dispose();
                          _changed();
                        }
                      : null,
                  icon: const Icon(Icons.close_outlined),
                ),
              ],
            ),
          ),
        if (widget.enabled && _rows.length < PriceTier.max)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _rows.add(_Row())),
              icon: const Icon(Icons.add_outlined, size: 18),
              label: Text(_rows.isEmpty ? 'Agregar precio por cantidad' : 'Agregar otro'),
            ),
          ),
      ],
    );
  }
}
