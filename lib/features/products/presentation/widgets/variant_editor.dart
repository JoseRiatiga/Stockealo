import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/design/color_swatch_dot.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../models/product_variant.dart';
import '../screens/barcode_scanner_screen.dart';

/// Un color de la lista: nombre libre ("Blanco con rojo") y su muestra.
class VariantColor {
  String name;
  String? hex; // '#RRGGBB' o 'multi'
  String? hex2; // segundo tono
  VariantColor(this.name, {this.hex, this.hex2});

  String get key => name.trim().toLowerCase();
}

class VariantCell {
  final String id;
  final TextEditingController stock;
  String? barcode;
  VariantCell({String? id, int stock = 0, this.barcode})
      : id = id ?? const Uuid().v4(),
        stock = TextEditingController(text: '$stock');

  int get value => int.tryParse(stock.text.trim()) ?? 0;
}

/// Estado del editor de variantes: tallas × colores, con existencias por combinación.
/// Sin colores funciona como antes (una fila por talla); sin tallas, una por color.
class VariantEditorController extends ChangeNotifier {
  String attributeName;
  final List<String> sizes = [];
  final List<VariantColor> colors = [];
  final Map<String, VariantCell> _cells = {};

  /// Combinaciones que el dueño quitó porque no existen (ej. XL en Rojo)
  final Set<String> removed = {};

  /// Variantes antiguas escritas como "M (ROJO)" que se pueden separar
  bool canSplitLegacy = false;

  VariantEditorController({this.attributeName = 'Talla'});

  static String cellKey(String size, String? color) => '${size.trim().toLowerCase()}|${(color ?? '').trim().toLowerCase()}';

  /// Combinaciones visibles, en orden de talla y luego de color
  List<({String size, VariantColor? color, String key})> get combos {
    final sizeList = sizes.isEmpty ? [''] : sizes;
    final colorList = colors.isEmpty ? <VariantColor?>[null] : colors.cast<VariantColor?>();
    if (sizes.isEmpty && colors.isEmpty) return const [];
    return [
      for (final s in sizeList)
        for (final c in colorList)
          if (!removed.contains(cellKey(s, c?.name))) (size: s, color: c, key: cellKey(s, c?.name)),
    ];
  }

  VariantCell cellFor(String key) => _cells.putIfAbsent(key, () {
        final cell = VariantCell();
        cell.stock.addListener(notifyListeners);
        return cell;
      });

  int get totalStock => combos.fold(0, (sum, c) => sum + cellFor(c.key).value);

  int totalForSize(String size) =>
      combos.where((c) => c.size == size).fold(0, (sum, c) => sum + cellFor(c.key).value);

  int totalForColor(VariantColor color) =>
      combos.where((c) => c.color?.key == color.key).fold(0, (sum, c) => sum + cellFor(c.key).value);

  void load(List<ProductVariant> variants) {
    if (variants.isEmpty) return;
    attributeName = variants.first.attributeName;
    for (final v in variants) {
      final size = v.attributeValue.trim();
      final colorName = (v.attribute2Value ?? '').trim();
      if (size.isNotEmpty && !sizes.contains(size)) sizes.add(size);
      if (colorName.isNotEmpty && !colors.any((c) => c.key == colorName.toLowerCase())) {
        colors.add(VariantColor(colorName, hex: v.colorHex, hex2: v.colorHex2));
      }
      final cell = VariantCell(id: v.id, stock: v.stock, barcode: v.skuOrBarcode);
      cell.stock.addListener(notifyListeners);
      _cells[cellKey(size, colorName.isEmpty ? null : colorName)] = cell;
    }
    // Las combinaciones que no estaban guardadas se consideran quitadas
    for (final s in sizes.isEmpty ? [''] : sizes) {
      for (final c in colors.isEmpty ? <VariantColor?>[null] : colors.cast<VariantColor?>()) {
        final key = cellKey(s, c?.name);
        if (!_cells.containsKey(key)) removed.add(key);
      }
    }
    canSplitLegacy = colors.isEmpty && sizes.where((s) => ProductVariant.splitLegacy(s) != null).length >= 2;
    notifyListeners();
  }

  /// "M (ROJO)", "M (VERDE)" → Talla M con colores Rojo y Verde. Conserva cada
  /// variante (su id, existencias y código) para no romper el historial de ventas.
  void splitLegacy() {
    final oldSizes = List<String>.from(sizes);
    final oldCells = Map<String, VariantCell>.from(_cells);
    sizes.clear();
    _cells.clear();
    removed.clear();
    final kept = <String>{};
    for (final raw in oldSizes) {
      final parts = ProductVariant.splitLegacy(raw);
      final size = parts?.first ?? raw;
      final colorName = parts?.second;
      if (!sizes.contains(size)) sizes.add(size);
      if (colorName != null && !colors.any((c) => c.key == colorName.toLowerCase())) {
        colors.add(VariantColor(colorName, hex: suggestHex(colorName)));
      }
      final key = cellKey(size, colorName);
      final cell = oldCells[cellKey(raw, null)];
      if (cell != null) _cells[key] = cell;
      kept.add(key);
    }
    for (final s in sizes) {
      for (final c in colors.isEmpty ? <VariantColor?>[null] : colors.cast<VariantColor?>()) {
        final key = cellKey(s, c?.name);
        if (!kept.contains(key)) removed.add(key);
      }
    }
    canSplitLegacy = false;
    notifyListeners();
  }

  void addSize(String raw) {
    for (final part in raw.split(',')) {
      final s = part.trim();
      if (s.isEmpty || sizes.any((x) => x.toLowerCase() == s.toLowerCase())) continue;
      sizes.add(s);
    }
    notifyListeners();
  }

  void removeSize(String size) {
    sizes.remove(size);
    final prefix = '${size.trim().toLowerCase()}|';
    removed.removeWhere((k) => k.startsWith(prefix));
    notifyListeners();
  }

  void setSizes(List<String> list) {
    sizes
      ..clear()
      ..addAll(list);
    removed.clear();
    notifyListeners();
  }

  void upsertColor(VariantColor color, {VariantColor? replacing}) {
    if (replacing != null) {
      final i = colors.indexOf(replacing);
      if (i >= 0) {
        // Al renombrar, las existencias siguen con el color
        if (replacing.key != color.key) {
          for (final s in sizes.isEmpty ? [''] : sizes) {
            final cell = _cells.remove(cellKey(s, replacing.name));
            if (cell != null) _cells[cellKey(s, color.name)] = cell;
            if (removed.remove(cellKey(s, replacing.name))) removed.add(cellKey(s, color.name));
          }
        }
        colors[i] = color;
      }
    } else if (!colors.any((c) => c.key == color.key)) {
      // El primer color se queda con lo que ya tenía cada talla (existencias, código, id)
      if (colors.isEmpty) _moveCells(fromColor: null, toColor: color.name);
      colors.add(color);
    }
    notifyListeners();
  }

  /// Pasa las celdas de cada talla de un color a otro (null = sin color)
  void _moveCells({required String? fromColor, required String? toColor}) {
    for (final s in sizes.isEmpty ? [''] : sizes) {
      final cell = _cells.remove(cellKey(s, fromColor));
      if (cell != null) _cells[cellKey(s, toColor)] = cell;
      if (removed.remove(cellKey(s, fromColor))) removed.add(cellKey(s, toColor));
    }
  }

  void removeColor(VariantColor color) {
    colors.remove(color);
    final suffix = '|${color.key}';
    removed.removeWhere((k) => k.endsWith(suffix));
    // Sin colores, cada talla vuelve a tener sus existencias de ese último color
    if (colors.isEmpty) _moveCells(fromColor: color.name, toColor: null);
    notifyListeners();
  }

  /// La × de una fila. Sin colores, la fila es la talla: se quita la talla. Con
  /// tallas y colores se quita solo esa combinación (ej. no hay XL en rojo), y si
  /// una talla o un color se queda sin combinaciones, se quita también de arriba.
  void removeCombo(String key) {
    final matches = combos.where((c) => c.key == key);
    if (matches.isEmpty) return;
    final combo = matches.first;
    if (colors.isEmpty) return removeSize(combo.size);
    if (sizes.isEmpty) return removeColor(combo.color!);
    removed.add(key);
    if (!combos.any((c) => c.size == combo.size)) return removeSize(combo.size);
    if (!combos.any((c) => c.color?.key == combo.color!.key)) return removeColor(combo.color!);
    notifyListeners();
  }

  void restoreCombos() {
    removed.clear();
    notifyListeners();
  }

  void fillAll(int value) {
    for (final c in combos) {
      cellFor(c.key).stock.text = '$value';
    }
    notifyListeners();
  }

  void setBarcode(String key, String code) {
    cellFor(key).barcode = code;
    notifyListeners();
  }

  /// Mensaje si falta algo para guardar; null si está bien
  String? validate() {
    if (combos.isEmpty) return 'Agrega al menos una ${attributeName.toLowerCase()} o un color.';
    return null;
  }

  List<ProductVariant> build({required String businessId, required String productId, required DateTime now}) {
    final hasColors = colors.isNotEmpty;
    return [
      for (final c in combos)
        ProductVariant(
          id: cellFor(c.key).id,
          businessId: businessId,
          productId: productId,
          attributeName: attributeName.trim().isEmpty ? 'Talla' : attributeName.trim(),
          attributeValue: c.size,
          attribute2Name: hasColors ? 'Color' : null,
          attribute2Value: c.color?.name.trim(),
          colorHex: ProductVariant.validHex(c.color?.hex, allowMulti: true),
          colorHex2: ProductVariant.validHex(c.color?.hex2),
          skuOrBarcode: (cellFor(c.key).barcode ?? '').trim().isEmpty ? null : cellFor(c.key).barcode!.trim(),
          stock: cellFor(c.key).value.clamp(0, 1 << 30),
          createdAt: now,
          updatedAt: now,
        ),
    ];
  }

  @override
  void dispose() {
    for (final cell in _cells.values) {
      cell.stock.dispose();
    }
    super.dispose();
  }

  /// Colores frecuentes para elegir la muestra con un toque
  static const palette = <String, String>{
    'Blanco': '#FFFFFF',
    'Negro': '#1F1D18',
    'Gris': '#9E9E9E',
    'Beige': '#E8D9B5',
    'Café': '#6D4C41',
    'Rojo': '#C62828',
    'Vinotinto': '#7B1E3A',
    'Rosado': '#F48FB1',
    'Fucsia': '#D81B60',
    'Naranja': '#EF6C00',
    'Amarillo': '#FBC02D',
    'Verde': '#2E7D32',
    'Verde menta': '#98D8C8',
    'Azul': '#1565C0',
    'Azul cielo': '#81D4FA',
    'Azul oscuro': '#1A237E',
    'Morado': '#6A1B9A',
    'Lila': '#B39DDB',
  };

  /// Muestra sugerida según el nombre ("Rojo" → rojo); null si no se reconoce
  static String? suggestHex(String name) {
    final n = name.trim().toLowerCase();
    for (final e in palette.entries) {
      if (e.key.toLowerCase() == n) return e.value;
    }
    if (n == 'cafe' || n == 'marrón' || n == 'marron') return palette['Café'];
    if (n == 'rosa') return palette['Rosado'];
    if (n == 'multicolor' || n == 'estampado') return ProductVariant.multicolor;
    return null;
  }
}

/// Editor visual: tallas, colores con muestra y la tabla de combinaciones
class VariantEditor extends StatefulWidget {
  final VariantEditorController controller;
  const VariantEditor({super.key, required this.controller});

  @override
  State<VariantEditor> createState() => _VariantEditorState();
}

class _VariantEditorState extends State<VariantEditor> {
  final _sizeInput = TextEditingController();
  final _fillInput = TextEditingController();

  VariantEditorController get ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    ctrl.addListener(_changed);
  }

  @override
  void dispose() {
    ctrl.removeListener(_changed);
    _sizeInput.dispose();
    _fillInput.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _addSizeFromInput() {
    if (_sizeInput.text.trim().isEmpty) return;
    ctrl.addSize(_sizeInput.text);
    _sizeInput.clear();
  }

  Future<void> _editColor([VariantColor? existing]) async {
    final result = await showDialog<VariantColor>(
      context: context,
      builder: (_) => _ColorDialog(initial: existing),
    );
    if (result == null) return;
    if (existing == null && ctrl.colors.any((c) => c.key == result.key)) return;
    ctrl.upsertColor(result, replacing: existing);
  }

  Future<void> _scan(String key) async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code != null && code.trim().isNotEmpty) ctrl.setBarcode(key, code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = ctrl.attributeName;
    TextStyle section = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink);

    return Container(
      padding: const EdgeInsets.all(AppSpace.md + 2),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ctrl.canSplitLegacy) _legacyBanner(c),

          // 1. Tallas
          Row(
            children: [
              Expanded(child: Text('${label}s', style: section)),
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: const Text('Ropa', style: TextStyle(fontSize: 11)),
                onPressed: () => ctrl.setSizes(['S', 'M', 'L', 'XL']),
              ),
              const SizedBox(width: 4),
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: const Text('Calzado', style: TextStyle(fontSize: 11)),
                onPressed: () => ctrl.setSizes(['36', '37', '38', '39', '40']),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in ctrl.sizes)
                InputChip(
                  label: Text(s),
                  onDeleted: () => ctrl.removeSize(s),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _sizeInput,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Agregar ${label.toLowerCase()}',
              hintText: 'Ej. M  ·  varias separadas por coma: S, M, L',
              isDense: true,
              suffixIcon: IconButton(
                tooltip: 'Agregar',
                icon: const Icon(Icons.add_rounded),
                onPressed: _addSizeFromInput,
              ),
            ),
            onSubmitted: (_) => _addSizeFromInput(),
          ),

          const SizedBox(height: AppSpace.lg),

          // 2. Colores
          Text('Colores (opcional)', style: section),
          const SizedBox(height: 2),
          Text(
            'Si la prenda viene en varios colores, agrégalos y pon cuántas hay de cada combinación.',
            style: TextStyle(fontSize: 12, color: c.inkMuted),
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final col in ctrl.colors)
                InputChip(
                  avatar: ColorSwatchDot(hex: col.hex, hex2: col.hex2, size: 18),
                  label: Text(col.name),
                  onPressed: () => _editColor(col),
                  onDeleted: () => ctrl.removeColor(col),
                  visualDensity: VisualDensity.compact,
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Agregar color'),
                onPressed: () => _editColor(),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),

          const SizedBox(height: AppSpace.lg),

          // 3. Existencias por combinación
          if (ctrl.combos.isNotEmpty) ...[
            Row(
              children: [
                Expanded(child: Text('Existencias', style: section)),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _fillInput,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(hintText: '0', isDense: true),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final v = int.tryParse(_fillInput.text.trim());
                    if (v != null) ctrl.fillAll(v);
                  },
                  child: const Text('Llenar todas'),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            ..._comboRows(c),
            if (ctrl.removed.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: ctrl.restoreCombos,
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: Text('Mostrar las ${ctrl.removed.length} combinaciones quitadas'),
                ),
              ),
            const SizedBox(height: AppSpace.sm),
            _totals(c),
          ],
        ],
      ),
    );
  }

  Widget _legacyBanner(StockealoColors c) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.infoSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parece que escribiste el color dentro de la talla, como "M (Rojo)".',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
          ),
          const SizedBox(height: 2),
          Text(
            '¿Separarlos en talla y color? Las existencias de cada una se conservan.',
            style: TextStyle(fontSize: 12.5, color: c.inkMuted),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: ctrl.splitLegacy, child: const Text('Separar talla y color')),
          ),
        ],
      ),
    );
  }

  List<Widget> _comboRows(StockealoColors c) {
    final rows = <Widget>[];
    String? currentSize;
    final grouped = ctrl.sizes.isNotEmpty && ctrl.colors.isNotEmpty;
    for (final combo in ctrl.combos) {
      if (grouped && combo.size != currentSize) {
        currentSize = combo.size;
        rows.add(Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm, bottom: 4),
          child: Text(
            '${ctrl.attributeName} ${combo.size}',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.inkMuted),
          ),
        ));
      }
      final cell = ctrl.cellFor(combo.key);
      final name = combo.color == null ? combo.size : combo.color!.name;
      rows.add(Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
        decoration: BoxDecoration(
          color: c.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          children: [
            if (combo.color != null) ...[
              ColorSwatchDot(hex: combo.color!.hex, hex2: combo.color!.hex2, size: 18),
              const SizedBox(width: AppSpace.sm),
            ],
            Expanded(
              child: Text(
                name.isEmpty ? '—' : name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
              ),
            ),
            SizedBox(
              width: 72,
              child: TextField(
                controller: cell.stock,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(isDense: true, hintText: '0'),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: (cell.barcode ?? '').isEmpty ? 'Escanear código de esta combinación' : 'Código: ${cell.barcode}',
              icon: Icon(
                (cell.barcode ?? '').isEmpty ? Icons.qr_code_scanner_rounded : Icons.qr_code_2_rounded,
                size: 18,
                color: (cell.barcode ?? '').isEmpty ? c.inkMuted : c.accent,
              ),
              onPressed: () => _scan(combo.key),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: combo.color == null || combo.size.isEmpty ? 'Quitar' : 'Quitar esta combinación (no existe)',
              icon: Icon(Icons.close_rounded, size: 18, color: c.inkMuted),
              onPressed: () => ctrl.removeCombo(combo.key),
            ),
          ],
        ),
      ));
    }
    return rows;
  }

  Widget _totals(StockealoColors c) {
    Widget pill(String text, {bool strong = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: strong ? c.successSoft : c.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
              color: strong ? c.success : c.inkMuted,
            ),
          ),
        );
    final grouped = ctrl.sizes.isNotEmpty && ctrl.colors.isNotEmpty;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        pill('Total: ${ctrl.totalStock} unid.', strong: true),
        if (grouped) ...[
          for (final s in ctrl.sizes) pill('$s: ${ctrl.totalForSize(s)}'),
          for (final col in ctrl.colors) pill('${col.name}: ${ctrl.totalForColor(col)}'),
        ],
      ],
    );
  }
}

/// Elegir nombre y muestra de un color: paleta, código hexadecimal, dos tonos o multicolor
class _ColorDialog extends StatefulWidget {
  final VariantColor? initial;
  const _ColorDialog({this.initial});

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _hex = TextEditingController(text: _hexText(widget.initial?.hex));
  late final _hex2 = TextEditingController(text: _hexText(widget.initial?.hex2));
  late bool _multi = ColorSwatchDot.isMulti(widget.initial?.hex);
  late bool _twoTones = widget.initial?.hex2 != null;
  bool _nameTouched = false;

  static String _hexText(String? v) => (v == null || ColorSwatchDot.isMulti(v)) ? '' : v.replaceFirst('#', '');

  @override
  void initState() {
    super.initState();
    _nameTouched = widget.initial != null;
  }

  @override
  void dispose() {
    _name.dispose();
    _hex.dispose();
    _hex2.dispose();
    super.dispose();
  }

  void _pick(TextEditingController target, String name, String hex) {
    setState(() {
      _multi = false;
      target.text = hex.replaceFirst('#', '');
      // El nombre se propone solo si el dueño aún no escribió uno
      if (!_nameTouched && target == _hex) _name.text = name;
      if (!_nameTouched && target == _hex2 && _name.text.trim().isNotEmpty && !_name.text.contains(' con ')) {
        _name.text = '${_name.text.trim()} con ${name.toLowerCase()}';
      }
    });
  }

  String? get _hexValue => ProductVariant.validHex(_hex.text);
  String? get _hex2Value => ProductVariant.validHex(_hex2.text);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget paletteFor(TextEditingController target) => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in VariantEditorController.palette.entries)
              Tooltip(
                message: e.key,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _pick(target, e.key, e.value),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 2,
                        color: ProductVariant.validHex(target.text) == e.value ? c.accent : Colors.transparent,
                      ),
                    ),
                    child: ColorSwatchDot(hex: e.value, size: 26),
                  ),
                ),
              ),
          ],
        );

    Widget hexField(TextEditingController ctrl, String label) => TextField(
          controller: ctrl,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]'))],
          decoration: InputDecoration(
            labelText: label,
            prefixText: '#',
            counterText: '',
            isDense: true,
          ),
          onChanged: (_) => setState(() => _multi = false),
        );

    final canSave = _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.initial == null ? 'Agregar color' : 'Editar color'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ColorSwatchDot(
                    hex: _multi ? ProductVariant.multicolor : _hexValue,
                    hex2: _twoTones && !_multi ? _hex2Value : null,
                    size: 40,
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del color',
                        hintText: 'Ej. Rojo, Vinotinto, Blanco con rojo',
                      ),
                      onChanged: (_) => setState(() => _nameTouched = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              Text('Muestra', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: AppSpace.sm),
              paletteFor(_hex),
              const SizedBox(height: AppSpace.sm),
              hexField(_hex, 'Código del color (hexadecimal)'),
              const SizedBox(height: AppSpace.sm),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _twoTones,
                onChanged: _multi ? null : (v) => setState(() => _twoTones = v ?? false),
                title: const Text('Es de dos colores (ej. blanca con roja)'),
              ),
              if (_twoTones && !_multi) ...[
                paletteFor(_hex2),
                const SizedBox(height: AppSpace.sm),
                hexField(_hex2, 'Segundo color (hexadecimal)'),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _multi,
                onChanged: (v) => setState(() {
                  _multi = v ?? false;
                  if (_multi && !_nameTouched && _name.text.trim().isEmpty) _name.text = 'Multicolor';
                }),
                title: const Text('Multicolor o estampado'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: canSave
              ? () {
                  final name = _name.text.trim();
                  Navigator.pop(
                    context,
                    VariantColor(
                      name[0].toUpperCase() + name.substring(1),
                      hex: _multi ? ProductVariant.multicolor : (_hexValue ?? VariantEditorController.suggestHex(name)),
                      hex2: (_twoTones && !_multi) ? _hex2Value : null,
                    ),
                  );
                }
              : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
