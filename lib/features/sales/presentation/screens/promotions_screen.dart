import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/filter_tabs.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/models/product.dart';
import '../../data/promotions_repository.dart';
import '../../data/sell_cart.dart';
import '../../models/promotion.dart';

/// Productos › Promociones (0.13.4, para todos los planes): % de descuento o lleva X,
/// paga Y, con nombre libre y fechas. Vender las aplica solas; con Pro la tienda en
/// línea y los catálogos las muestran con su cinta.
class PromotionsScreen extends StatefulWidget {
  final Business business;

  /// Dueño o administrador: crea, cambia y borra
  final bool canEdit;

  const PromotionsScreen({super.key, required this.business, this.canEdit = true});

  static Future<void> open(BuildContext context, {required Business business, bool canEdit = true}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PromotionsScreen(business: business, canEdit: canEdit)));

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  final _repo = PromotionsRepository.instance;
  List<Promotion>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _repo.all(widget.business.id);
    // Vender usa las vigentes: se refrescan al cambiar algo
    SellCart.instance.setPromotions([for (final p in list) if (p.isLiveAt(DateTime.now())) p]);
    if (mounted) setState(() => _list = list);
  }

  Future<void> _edit([Promotion? p]) async {
    final saved = await PromotionEditor.show(context, business: widget.business, promotion: p);
    if (saved == true) await _load();
  }

  static final _day = DateFormat('d MMM', 'es_CO');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = _list;
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(title: const Text('Promociones')),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xxl),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Vender las aplica solas mientras están vigentes, y se apagan solas al terminar.',
                                style: AppText.small(context),
                              ),
                            ),
                            if (widget.canEdit) ...[
                              const SizedBox(width: AppSpace.md),
                              FilledButton.icon(
                                onPressed: () => _edit(),
                                icon: const Icon(Icons.add_outlined, size: 18),
                                label: const Text('Nueva promoción'),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSpace.md),
                        if (list.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
                            child: Text(
                              'Aún no tienes promociones. Crea una: «20 % en camisetas», «2×1 en gaseosas», «Fin de mes»…',
                              textAlign: TextAlign.center,
                              style: AppText.body(context, color: c.inkMuted),
                            ),
                          ),
                        for (final p in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpace.sm),
                            child: Material(
                              color: c.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadius.card),
                                side: BorderSide(color: c.line),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(AppRadius.card),
                                onTap: widget.canEdit ? () => _edit(p) : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpace.md),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 56,
                                        height: 56,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: c.accent.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(AppRadius.control),
                                        ),
                                        child: Text(p.badge,
                                            style: AppText.body(context, weight: FontWeight.w800, color: c.accent)),
                                      ),
                                      const SizedBox(width: AppSpace.md),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(p.name, style: AppText.bodyLarge(context, weight: FontWeight.w700)),
                                            Text(
                                              '${_scopeText(p)} · ${_day.format(p.startsAt)} – '
                                              '${_day.format(p.endsAt.subtract(const Duration(minutes: 1)))}',
                                              style: AppText.small(context),
                                            ),
                                          ],
                                        ),
                                      ),
                                      StatusPill(
                                        !p.isActive
                                            ? 'Apagada'
                                            : p.isLiveAt(now)
                                                ? 'Vigente'
                                                : (p.isOverAt(now) ? 'Terminó' : 'Próxima'),
                                        tone: !p.isActive || p.isOverAt(now)
                                            ? AppTone.neutral
                                            : (p.isLiveAt(now) ? AppTone.success : AppTone.info),
                                        compact: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  static String _scopeText(Promotion p) => switch (p.scope) {
        Promotion.scopeCategory => 'Categoría ${p.category ?? ''}',
        Promotion.scopeProducts => '${p.productIds.length} ${p.productIds.length == 1 ? 'producto' : 'productos'}',
        _ => 'Todo el inventario',
      };
}

/// LA hoja para crear o cambiar una promoción
class PromotionEditor extends StatefulWidget {
  final Business business;
  final Promotion? promotion;

  const PromotionEditor({super.key, required this.business, this.promotion});

  /// true si se guardó o se borró
  static Future<bool?> show(BuildContext context, {required Business business, Promotion? promotion}) =>
      AppSidePanel.show<bool>(
        context: context,
        title: promotion == null ? 'Nueva promoción' : 'Editar promoción',
        subtitle: 'Se aplica sola en Vender mientras esté vigente.',
        builder: (_) => PromotionEditor(business: business, promotion: promotion),
      );

  @override
  State<PromotionEditor> createState() => _PromotionEditorState();
}

class _PromotionEditorState extends State<PromotionEditor> {
  late final Promotion _base =
      widget.promotion ?? PromotionsRepository.instance.newPromotion(widget.business.id, name: '', kind: Promotion.percent);
  late final _name = TextEditingController(text: widget.promotion?.name ?? '');
  late final _percent = TextEditingController(text: _base.percentOff > 0 ? _base.percentOff.round().toString() : '10');
  late String _kind = _base.kind;
  late int _buy = _base.buyQty;
  late int _pay = _base.payQty;
  late String _scope = _base.scope;
  late String? _category = _base.category;
  late Set<String> _products = {..._base.productIds};
  late DateTimeRange _range = DateTimeRange(
    start: _base.startsAt,
    end: _base.endsAt.subtract(const Duration(days: 1)),
  );
  late bool _active = _base.isActive;
  List<String> _categories = const [];
  List<Product> _allProducts = const [];
  bool _saving = false;

  static final _day = DateFormat('d MMM yyyy', 'es_CO');

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final repo = ProductRepository.instance;
    final cats = await repo.getCategories(widget.business.id);
    final products = await repo.getAllProducts(widget.business.id);
    if (!mounted) return;
    setState(() {
      _categories = [for (final c in cats) c.name];
      _allProducts = products;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _percent.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _range,
      helpText: '¿De qué día a qué día?',
      saveText: 'Listo',
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _pickProducts() async {
    final chosen = {..._products};
    await AppSheet.show<void>(
      context: context,
      title: 'Productos de la promoción',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in _allProducts)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: chosen.contains(p.id),
                title: Text(p.name),
                subtitle: p.category.isEmpty ? null : Text(p.category),
                onChanged: (v) => set(() => v == true ? chosen.add(p.id) : chosen.remove(p.id)),
              ),
            const SizedBox(height: AppSpace.md),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text('Listo (${chosen.length})')),
          ],
        ),
      ),
    );
    setState(() => _products = chosen);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final pct = double.tryParse(_percent.text.trim().replaceAll(',', '.')) ?? 0;
    String? problem;
    if (name.isEmpty) problem = 'Ponle un nombre, por ejemplo «Fin de mes».';
    if (_kind == Promotion.percent && (pct < 1 || pct > 90)) problem = 'El descuento va de 1 % a 90 %.';
    if (_kind == Promotion.buyXPayY && _pay >= _buy) problem = 'En «lleva X, paga Y», Y debe ser menor que X.';
    if (_scope == Promotion.scopeCategory && (_category ?? '').isEmpty) problem = 'Elige la categoría.';
    if (_scope == Promotion.scopeProducts && _products.isEmpty) problem = 'Marca al menos un producto.';
    if (problem != null) {
      AppToast.showWarning(context, problem);
      return;
    }
    setState(() => _saving = true);
    final p = Promotion(
      id: _base.id,
      businessId: _base.businessId,
      name: name.length > 60 ? name.substring(0, 60) : name,
      kind: _kind,
      percentOff: _kind == Promotion.percent ? pct : 0,
      buyQty: _buy,
      payQty: _pay,
      scope: _scope,
      category: _scope == Promotion.scopeCategory ? _category : null,
      productIds: _scope == Promotion.scopeProducts ? _products.toList() : const [],
      startsAt: DateTime(_range.start.year, _range.start.month, _range.start.day),
      // Hasta el final del último día
      endsAt: DateTime(_range.end.year, _range.end.month, _range.end.day).add(const Duration(days: 1)),
      isActive: _active,
      createdAt: _base.createdAt,
      updatedAt: DateTime.now(),
    );
    await PromotionsRepository.instance.save(p);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await AppDialog.confirm(
      context: context,
      title: 'Borrar «${widget.promotion!.name}»',
      message: 'Las ventas que ya la usaron conservan su descuento.',
      confirmText: 'Borrar',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await PromotionsRepository.instance.delete(widget.promotion!);
    if (mounted) Navigator.pop(context, true);
  }

  Widget _counter(String label, int value, ValueChanged<int> onChanged, {int min = 0}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppText.body(context)),
          IconButton(
            tooltip: 'Menos',
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_outlined, size: 18),
          ),
          Text('$value', style: AppText.bodyLarge(context, weight: FontWeight.w700)),
          IconButton(
            tooltip: 'Más',
            onPressed: value < 20 ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_outlined, size: 18),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej.: Fin de mes, 2×1 en camisetas'),
        ),
        const SizedBox(height: AppSpace.sm),
        Text('Tipo', style: AppText.small(context, weight: FontWeight.w700)),
        const SizedBox(height: AppSpace.xs),
        FilterTabs<String>(
          options: const {Promotion.percent: '% de descuento', Promotion.buyXPayY: 'Lleva X, paga Y'},
          value: _kind,
          onChanged: (v) => setState(() => _kind = v),
        ),
        const SizedBox(height: AppSpace.md),
        if (_kind == Promotion.percent)
          TextField(
            controller: _percent,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Descuento', suffixText: '%'),
          )
        else
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpace.md,
            children: [
              _counter('Lleva', _buy, (v) => setState(() {
                    _buy = v;
                    if (_pay >= _buy) _pay = _buy - 1;
                  }), min: 2),
              _counter('Paga', _pay, (v) => setState(() => _pay = v < _buy ? v : _buy - 1), min: 1),
              StatusPill('$_buy×$_pay', tone: AppTone.accent, compact: true),
            ],
          ),
        const SizedBox(height: AppSpace.md),
        Text('¿A qué productos?', style: AppText.small(context, weight: FontWeight.w700)),
        const SizedBox(height: AppSpace.xs),
        FilterTabs<String>(
          options: const {
            Promotion.scopeAll: 'Todo',
            Promotion.scopeCategory: 'Una categoría',
            Promotion.scopeProducts: 'Productos marcados',
          },
          value: _scope,
          onChanged: (v) => setState(() => _scope = v),
        ),
        const SizedBox(height: AppSpace.sm),
        if (_scope == Promotion.scopeCategory)
          DropdownButtonFormField<String>(
            initialValue: _categories.contains(_category) ? _category : null,
            decoration: const InputDecoration(labelText: 'Categoría'),
            items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _category = v),
          ),
        if (_scope == Promotion.scopeProducts)
          OutlinedButton.icon(
            onPressed: _allProducts.isEmpty ? null : _pickProducts,
            icon: const Icon(Icons.checklist_outlined, size: 18),
            label: Text(_products.isEmpty ? 'Elegir productos' : '${_products.length} elegidos · Cambiar'),
          ),
        const SizedBox(height: AppSpace.md),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.date_range_outlined),
          title: const Text('Fechas'),
          subtitle: Text('Del ${_day.format(_range.start)} al ${_day.format(_range.end)}, todo el día'),
          trailing: TextButton(onPressed: _pickRange, child: const Text('Cambiar')),
        ),
        if (widget.promotion != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: const Text('Encendida'),
            subtitle: const Text('Apágala para pausarla sin borrarla'),
          ),
        const SizedBox(height: AppSpace.md),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando…' : 'Guardar promoción'),
        ),
        if (widget.promotion != null)
          TextButton(onPressed: _saving ? null : _delete, child: const Text('Borrar promoción')),
      ],
    );
  }
}
