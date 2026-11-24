import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/codes/code_reader.dart';
import '../../../../core/design/app_card.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/services/data_events.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/business_clock.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../data/product_repository.dart';
import '../../data/stock_count.dart';
import '../../models/product.dart';

/// Contar inventario (0.17.0, bloque C): lista por categoría con lo que dice la app y
/// un campo «Contaste». Se guarda a medias en este celular y al terminar muestra lo que
/// sobró y faltó antes de ajustar.
class StockCountScreen extends StatefulWidget {
  final Business business;

  const StockCountScreen({super.key, required this.business});

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  List<Product> _products = const [];
  StockCount? _count;
  String? _category;
  bool _loading = true;
  bool _dirty = false;
  bool _applying = false;
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _load();
    // Ventas o entradas de mientras: «En la app» se pone al día para lo que falta contar
    DataEvents.instance.salesVersion.addListener(_reloadStock);
    DataEvents.instance.productsVersion.addListener(_reloadStock);
  }

  Future<void> _reloadStock() async {
    final products = await ProductRepository.instance.searchProducts('', businessId: widget.business.id);
    if (mounted) setState(() => _products = products);
  }

  @override
  void dispose() {
    DataEvents.instance.salesVersion.removeListener(_reloadStock);
    DataEvents.instance.productsVersion.removeListener(_reloadStock);
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final products = await ProductRepository.instance.searchProducts('', businessId: widget.business.id);
    final saved = await StockCount.load(widget.business.id);
    if (!mounted) return;
    setState(() {
      _products = products;
      _count = saved ?? StockCount(businessId: widget.business.id, startedAt: appNow());
      _loading = false;
    });
  }

  TextEditingController _field(Product p, [String? variantId]) {
    final key = variantId == null ? p.id : '${p.id}|$variantId';
    return _controllers.putIfAbsent(key, () {
      final counted = _count!.countedOf(p.id, variantId);
      return TextEditingController(text: counted?.toString() ?? '');
    });
  }

  void _onTyped(Product p, String text, [String? variantId]) {
    _count!.set(p, int.tryParse(text.trim()), variantId: variantId);
    setState(() => _dirty = true);
  }

  List<String> get _categories => {for (final p in _products) p.category}.toList()..sort();

  List<Product> get _shown => [
        for (final p in _products)
          if (_category == null || p.category == _category) p,
      ];

  Future<void> _saveDraft({bool quiet = false}) async {
    await _count!.save();
    _dirty = false;
    if (!quiet && mounted) AppToast.showSuccess(context, 'Conteo guardado en este celular. Puedes seguir después.');
  }

  /// Cada lectura suma 1; el lector se vuelve a abrir hasta que se cierre
  Future<void> _scan() async {
    while (mounted) {
      final code = await CodeReader.scan(context, title: 'Contar con el lector', caption: 'Cada lectura suma 1');
      if (code == null || !mounted) return;
      final product = _products.where((p) => p.code == code.trim()).firstOrNull;
      if (product == null) {
        AppToast.showWarning(context, 'No hay ningún producto con el código $code.');
        continue;
      }
      if (product.hasVariants && product.variants.isNotEmpty) {
        AppToast.showWarning(context, '${product.name} tiene tallas o colores: cuéntalo en la lista.');
        continue;
      }
      final n = _count!.addOne(product);
      _field(product).text = '$n';
      setState(() => _dirty = true);
      AppToast.showInfo(context, '${product.name}: $n');
    }
  }

  Future<void> _finish() async {
    final count = _count!;
    if (count.lines.isEmpty) {
      AppToast.showWarning(context, 'Todavía no has contado nada.');
      return;
    }
    final s = count.summary({for (final p in _products) p.id: p});
    final ok = await AppDialog.confirm(
      context: context,
      title: 'Resumen del conteo',
      message: [
        'Contaste ${s.counted} ${s.counted == 1 ? 'producto' : 'productos'}; ${s.withDifference} con diferencia.',
        if (s.surplusUnits > 0) 'Sobraron ${s.surplusUnits} (${CurrencyFormatter.format(s.surplusValue)} a costo).',
        if (s.missingUnits > 0) 'Faltaron ${s.missingUnits} (${CurrencyFormatter.format(s.missingValue)} a costo).',
        if (s.withDifference == 0) 'Todo cuadra con la app.',
        if (s.withDifference > 0) 'Se ajusta el stock y cada diferencia queda en el historial como «${count.reason}».',
      ].join('\n\n'),
      confirmText: s.withDifference == 0 ? 'Terminar' : 'Ajustar el stock',
    );
    if (!ok || !mounted) return;
    setState(() => _applying = true);
    try {
      final changed = await count.apply();
      if (!mounted) return;
      AppToast.showSuccess(context, changed == 0 ? 'Conteo terminado: todo cuadra.' : 'Listo: se ajustaron $changed ${changed == 1 ? 'producto' : 'productos'}.');
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      AppToast.showError(context, 'No se pudo ajustar: $e');
    }
  }

  Future<void> _discard() async {
    final ok = await AppDialog.confirm(
      context: context,
      title: 'Empezar de nuevo',
      message: 'Se borra lo contado en este celular. El stock no cambia.',
      confirmText: 'Borrar lo contado',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _count!.discard();
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    setState(() {
      _count = StockCount(businessId: widget.business.id, startedAt: appNow());
      _dirty = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        await _saveDraft(quiet: true);
        if (mounted) setState(() {});
        nav.pop();
      },
      child: Scaffold(
        backgroundColor: c.paper,
        appBar: AppBar(
          title: const Text('Contar inventario'),
          actions: [
            IconButton(
              tooltip: 'Contar con el lector',
              onPressed: _loading ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner_outlined),
            ),
            if (!_loading && (_count?.lines.isNotEmpty ?? false))
              IconButton(tooltip: 'Empezar de nuevo', onPressed: _discard, icon: const Icon(Icons.restart_alt_outlined)),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
                    child: Text(
                      'Escribe lo que hay en el estante. Lo que dejes vacío no se cambia. Lo contado se guarda en este celular hasta que termines.',
                      style: AppText.small(context, color: c.inkMuted),
                    ),
                  ),
                  SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpace.sm),
                          child: ChoiceChip(
                            label: const Text('Todas'),
                            selected: _category == null,
                            onSelected: (_) => setState(() => _category = null),
                          ),
                        ),
                        for (final cat in _categories)
                          Padding(
                            padding: const EdgeInsets.only(right: AppSpace.sm),
                            child: ChoiceChip(
                              label: Text(cat),
                              selected: _category == cat,
                              onSelected: (_) => setState(() => _category = cat),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _shown.isEmpty
                        ? Center(child: Text('No hay productos para contar.', style: AppText.body(context, color: c.inkMuted)))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.xl),
                            itemCount: _shown.length,
                            itemBuilder: (_, i) => _productCard(_shown[i]),
                          ),
                  ),
                  _bottomBar(),
                ],
              ),
      ),
    );
  }

  Widget _productCard(Product p) {
    final variants = p.hasVariants ? p.variants : const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (variants.isEmpty)
              _row(p, title: p.name, subtitle: p.category, expected: p.stock)
            else ...[
              Text(p.name, style: AppText.body(context, weight: FontWeight.w700)),
              for (final v in variants)
                _row(p, title: v.label.isEmpty ? 'Sin nombre' : v.label, expected: v.stock, variantId: v.id),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(Product p, {required String title, String? subtitle, required int expected, String? variantId}) {
    final c = context.colors;
    final line = _count!.lines[variantId == null ? p.id : '${p.id}|$variantId'];
    final diff = line?.diff ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.body(context, weight: variantId == null ? FontWeight.w700 : FontWeight.w500)),
                Text(
                  [
                    if (subtitle != null) subtitle,
                    'En la app: ${line?.expected ?? expected}',
                    if (line != null && diff != 0) diff > 0 ? 'sobran $diff' : 'faltan ${-diff}',
                  ].join(' · '),
                  style: AppText.small(context, color: line != null && diff != 0 ? (diff > 0 ? c.success : c.danger) : c.inkMuted),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: TextField(
              controller: _field(p, variantId),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              decoration: const InputDecoration(hintText: 'Cant.', isDense: true),
              onChanged: (t) => _onTyped(p, t, variantId),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final c = context.colors;
    final n = _count?.lines.length ?? 0;
    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
      padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.md + MediaQuery.paddingOf(context).bottom),
      child: Row(
        children: [
          Expanded(child: Text('$n ${n == 1 ? 'contado' : 'contados'}', style: AppText.body(context, color: c.inkMuted))),
          OutlinedButton(onPressed: _applying || n == 0 ? null : () => _saveDraft(), child: const Text('Seguir después')),
          const SizedBox(width: AppSpace.sm),
          FilledButton(onPressed: _applying ? null : _finish, child: const Text('Terminar')),
        ],
      ),
    );
  }
}
