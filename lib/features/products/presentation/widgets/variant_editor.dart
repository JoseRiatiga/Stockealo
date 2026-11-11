import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/design/color_sliders.dart';
import '../../../../core/design/color_swatch_dot.dart';
import '../../../../core/utils/eyedropper.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../models/product_variant.dart';
import 'photo_color_picker.dart';
import '../../../../core/codes/code_reader.dart';
import '../../../../core/design/app_dialog.dart';

/// Un color: nombre libre ("Blanco con rojo") y su muestra.
class VariantColor {
  String name;
  String? hex; // '#RRGGBB' o 'multi'
  String? hex2; // segundo tono
  VariantColor(this.name, {this.hex, this.hex2});

  String get key => name.trim().toLowerCase();

  VariantColor copy() => VariantColor(name, hex: hex, hex2: hex2);
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

/// Estado del editor de variantes. Cada talla tiene sus propios colores (la S puede
/// venir solo en rojo y la M en rojo y verde). Una talla sin colores es una sola fila.
/// Sin tallas, los colores cuelgan de una talla vacía ('').
class VariantEditorController extends ChangeNotifier {
  String attributeName;
  final List<String> sizes = [];

  /// Colores de cada talla, por la clave de la talla (en minúsculas)
  final Map<String, List<VariantColor>> _colorsBySize = {};
  final Map<String, VariantCell> _cells = {};

  /// Variantes antiguas escritas como "M (ROJO)" que se pueden separar
  bool canSplitLegacy = false;

  VariantEditorController({this.attributeName = 'Talla'});

  static String _sizeKey(String size) => size.trim().toLowerCase();

  static String cellKey(String size, String? color) => '${_sizeKey(size)}|${(color ?? '').trim().toLowerCase()}';

  /// Tallas que se muestran: si no hay ninguna pero sí colores, una talla vacía
  List<String> get _sizeList => sizes.isEmpty ? [''] : sizes;

  List<VariantColor> colorsOf(String size) => _colorsBySize[_sizeKey(size)] ?? const [];

  /// Todos los colores usados, sin repetir, en el orden en que aparecen
  List<VariantColor> get colors {
    final seen = <String>{};
    return [
      for (final s in _sizeList)
        for (final c in colorsOf(s))
          if (seen.add(c.key)) c,
    ];
  }

  /// Combinaciones en orden de talla y luego de color
  List<({String size, VariantColor? color, String key})> get combos {
    if (sizes.isEmpty && colorsOf('').isEmpty) return const [];
    return [
      for (final s in _sizeList)
        if (colorsOf(s).isEmpty)
          (size: s, color: null, key: cellKey(s, null))
        else
          for (final c in colorsOf(s)) (size: s, color: c, key: cellKey(s, c.name)),
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

  void _putCell(String key, VariantCell cell) {
    cell.stock.addListener(notifyListeners);
    _cells[key] = cell;
  }

  void load(List<ProductVariant> variants) {
    if (variants.isEmpty) return;
    attributeName = variants.first.attributeName;
    for (final v in variants) {
      final size = v.attributeValue.trim();
      final colorName = (v.attribute2Value ?? '').trim();
      if (size.isNotEmpty && !sizes.contains(size)) sizes.add(size);
      if (colorName.isNotEmpty) {
        final list = _colorsBySize.putIfAbsent(_sizeKey(size), () => []);
        if (!list.any((c) => c.key == colorName.toLowerCase())) {
          list.add(VariantColor(colorName, hex: v.colorHex, hex2: v.colorHex2));
        }
      }
      _putCell(cellKey(size, colorName.isEmpty ? null : colorName),
          VariantCell(id: v.id, stock: v.stock, barcode: v.skuOrBarcode));
    }
    canSplitLegacy = colors.isEmpty && sizes.where((s) => ProductVariant.splitLegacy(s) != null).length >= 2;
    notifyListeners();
  }

  /// "M (ROJO)", "M (VERDE)" → Talla M con sus colores Rojo y Verde. Conserva cada
  /// variante (su id, existencias y código) para no romper el historial de ventas.
  void splitLegacy() {
    final oldSizes = List<String>.from(sizes);
    final oldCells = Map<String, VariantCell>.from(_cells);
    sizes.clear();
    _cells.clear();
    _colorsBySize.clear();
    for (final raw in oldSizes) {
      final parts = ProductVariant.splitLegacy(raw);
      final size = parts?.first ?? raw;
      final colorName = parts?.second;
      if (!sizes.contains(size)) sizes.add(size);
      if (colorName != null) {
        final list = _colorsBySize.putIfAbsent(_sizeKey(size), () => []);
        if (!list.any((c) => c.key == colorName.toLowerCase())) {
          // Mismo color en varias tallas: misma muestra
          final known = colors.where((c) => c.key == colorName.toLowerCase());
          list.add(known.isNotEmpty ? known.first.copy() : VariantColor(colorName, hex: suggestHex(colorName)));
        }
      }
      final cell = oldCells[cellKey(raw, null)];
      if (cell != null) _cells[cellKey(size, colorName)] = cell;
    }
    canSplitLegacy = false;
    notifyListeners();
  }

  void addSize(String raw) {
    for (final part in raw.split(',')) {
      final s = part.trim();
      if (s.isEmpty || sizes.any((x) => x.toLowerCase() == s.toLowerCase())) continue;
      // Si había colores sin talla, pasan a la primera talla que se agrega
      if (sizes.isEmpty && colorsOf('').isNotEmpty) {
        _colorsBySize[_sizeKey(s)] = _colorsBySize.remove('')!;
        for (final c in colorsOf(s)) {
          final cell = _cells.remove(cellKey('', c.name));
          if (cell != null) _cells[cellKey(s, c.name)] = cell;
        }
      }
      sizes.add(s);
    }
    notifyListeners();
  }

  void removeSize(String size) {
    sizes.remove(size);
    _colorsBySize.remove(_sizeKey(size));
    notifyListeners();
  }

  void setSizes(List<String> list) {
    sizes
      ..clear()
      ..addAll(list);
    _colorsBySize.removeWhere((k, _) => !list.any((s) => _sizeKey(s) == k));
    notifyListeners();
  }

  /// Agrega un color solo a esa talla. El primer color de la talla se queda con lo
  /// que ella ya tenía (existencias, código, id).
  void addColorTo(String size, VariantColor color) {
    final list = _colorsBySize.putIfAbsent(_sizeKey(size), () => []);
    if (list.any((c) => c.key == color.key)) return;
    if (list.isEmpty) {
      final cell = _cells.remove(cellKey(size, null));
      if (cell != null) _cells[cellKey(size, color.name)] = cell;
    }
    list.add(color);
    notifyListeners();
  }

  /// Cambia nombre o muestra de un color en esa talla; la muestra nueva se aplica
  /// también al mismo color en las otras tallas, para que se vea igual en todas.
  void updateColorIn(String size, VariantColor old, VariantColor updated) {
    final list = _colorsBySize[_sizeKey(size)];
    if (list == null) return;
    final i = list.indexWhere((c) => c.key == old.key);
    if (i < 0) return;
    if (old.key != updated.key) {
      if (list.any((c) => c.key == updated.key)) return; // ya existe en esta talla
      final cell = _cells.remove(cellKey(size, old.name));
      if (cell != null) _cells[cellKey(size, updated.name)] = cell;
    }
    list[i] = updated;
    for (final other in _colorsBySize.values) {
      for (final c in other) {
        if (c.key == updated.key && !identical(c, updated)) {
          c.hex = updated.hex;
          c.hex2 = updated.hex2;
        }
      }
    }
    notifyListeners();
  }

  /// Quita un color de esa talla. Si era el último, la talla vuelve a ser una
  /// sola fila con esas existencias.
  void removeColorFrom(String size, VariantColor color) {
    final list = _colorsBySize[_sizeKey(size)];
    if (list == null) return;
    list.removeWhere((c) => c.key == color.key);
    if (list.isEmpty) {
      final cell = _cells.remove(cellKey(size, color.name));
      if (cell != null) _cells[cellKey(size, null)] = cell;
      _colorsBySize.remove(_sizeKey(size));
    }
    notifyListeners();
  }

  /// La × de una fila: el color en esa talla, o la talla si no tiene colores
  void removeCombo(String key) {
    final matches = combos.where((c) => c.key == key);
    if (matches.isEmpty) return;
    final combo = matches.first;
    if (combo.color != null) return removeColorFrom(combo.size, combo.color!);
    removeSize(combo.size);
  }

  /// Colores usados en otras tallas que esta todavía no tiene (para ponerlos con un toque)
  List<VariantColor> suggestionsFor(String size) {
    final mine = colorsOf(size).map((c) => c.key).toSet();
    return [for (final c in colors) if (!mine.contains(c.key)) c];
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
    return [
      for (final c in combos)
        ProductVariant(
          id: cellFor(c.key).id,
          businessId: businessId,
          productId: productId,
          attributeName: attributeName.trim().isEmpty ? 'Talla' : attributeName.trim(),
          attributeValue: c.size,
          attribute2Name: c.color == null ? null : 'Color',
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

  /// Nombre en español para cualquier color, por su tono, qué tan vivo es y qué
  /// tan claro u oscuro ("#6F6E6C" → "Gris", "#0B6623" → "Verde oscuro"). Se usa
  /// cuando eligen el color con las barras, la foto, el gotero o el código.
  static String colorNameFor(Color color) {
    final hsl = HSLColor.fromColor(color);
    final h = hsl.hue, s = hsl.saturation, l = hsl.lightness;

    // Sin color: blancos, grises y negros
    if (l >= 0.93) return 'Blanco';
    if (l <= 0.13) return 'Negro';
    if (s < 0.12 || (s < 0.2 && (l < 0.25 || l > 0.85))) {
      if (l > 0.75) return 'Gris claro';
      if (l < 0.35) return 'Gris oscuro';
      return 'Gris';
    }

    String shade(String base, {String? light, String? dark}) {
      if (l > 0.70) return light ?? '$base claro';
      if (l <= 0.30) return dark ?? '$base oscuro';
      return base;
    }

    // Tonos cálidos con poca luz o poco color: cafés, beiges y mostaza
    if (h >= 15 && h < 50) {
      if (l > 0.78 && s < 0.65) return 'Beige';
      // Muy oscuro, apagado, u oscuro sin ser intenso: café. El mostaza es oscuro
      // pero muy vivo, así que sigue de largo
      if (l < 0.3 || s < 0.45 || (l < 0.45 && s < 0.75)) return 'Café';
    }
    if (h < 15 || h >= 345) {
      if (l <= 0.32) return 'Vinotinto';
      return shade('Rojo', light: 'Rosado');
    }
    if (h < 40) return shade('Naranja');
    if (h < 65) return l < 0.42 ? 'Mostaza' : shade('Amarillo');
    if (h < 150) return shade('Verde');
    if (h < 175) return l > 0.65 ? 'Verde menta' : shade('Turquesa');
    if (h < 195) return shade('Turquesa');
    if (h < 250) return shade('Azul', light: 'Azul cielo');
    if (h < 290) return shade('Morado', light: 'Lila');
    // 290–345: rosados, fucsias y vinotintos
    if (l <= 0.32) return 'Vinotinto';
    if (s > 0.6 && l < 0.6) return 'Fucsia';
    return 'Rosado';
  }

  /// Todos los nombres que pone la app sola (paleta y [colorNameFor])
  static final Set<String> _autoNames = {
    for (final k in palette.keys) k.toLowerCase(),
    'multicolor', 'gris claro', 'gris oscuro', 'mostaza', 'turquesa',
    for (final base in ['naranja', 'amarillo', 'verde', 'turquesa', 'azul', 'morado', 'rojo'])
      for (final mod in ['claro', 'oscuro']) '$base $mod',
  };

  /// Colores base por nombre, para poner la muestra cuando escriben el nombre
  static const _baseByName = <String, String>{
    'verde menta': '#98D8C8',
    'azul cielo': '#81D4FA',
    'azul oscuro': '#1A237E',
    'blanco': '#FFFFFF',
    'negro': '#1F1D18',
    'gris': '#9E9E9E',
    'plateado': '#C0C0C0',
    'beige': '#E8D9B5',
    'crema': '#F3E5C0',
    'café': '#6D4C41',
    'cafe': '#6D4C41',
    'marrón': '#6D4C41',
    'marron': '#6D4C41',
    'mostaza': '#B8860B',
    'dorado': '#D4AF37',
    'rojo': '#C62828',
    'vinotinto': '#7B1E3A',
    'vino': '#7B1E3A',
    'rosado': '#F48FB1',
    'rosa': '#F48FB1',
    'fucsia': '#D81B60',
    'naranja': '#EF6C00',
    'amarillo': '#FBC02D',
    'verde': '#2E7D32',
    'turquesa': '#00ACC1',
    'celeste': '#81D4FA',
    'azul': '#1565C0',
    'morado': '#6A1B9A',
    'lila': '#B39DDB',
  };

  static const _lighter = ['claro', 'clarito', 'bajito', 'pastel', 'suave', 'palo'];
  static const _darker = ['oscuro', 'oscurito', 'fuerte', 'profundo', 'intenso'];

  /// La muestra que corresponde a un nombre escrito. `exact` es true si el nombre es
  /// uno que la app conoce tal cual ("Rojo", "Gris oscuro"); false si es un nombre
  /// propio con un color reconocible dentro ("Azul bajito" → un azul claro).
  /// null si no reconoce ningún color ("Pepito").
  static ({String hex, bool exact})? swatchForName(String raw) {
    final n = raw.trim().toLowerCase();
    if (n.isEmpty) return null;
    if (n == 'multicolor' || n == 'estampado') return (hex: ProductVariant.multicolor, exact: true);
    final exactKnown = isPaletteName(n) && !n.contains(' con ');

    // El color base: primero los nombres compuestos ("verde menta" antes que "verde")
    final keys = _baseByName.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    String? base;
    for (final k in keys) {
      if (RegExp('(^|\\s)${RegExp.escape(k)}(\\s|\$)').hasMatch(n)) {
        base = k;
        break;
      }
    }
    if (base == null) return null;
    var hsl = HSLColor.fromColor(Color(int.parse('FF${_baseByName[base]!.substring(1)}', radix: 16)));
    final words = n.split(RegExp(r'\s+'));
    final compound = base.contains(' '); // "azul cielo" ya trae su claridad
    if (!compound && words.any(_lighter.contains)) {
      hsl = hsl.withLightness((hsl.lightness + 0.25).clamp(0.0, 0.88));
    } else if (!compound && words.any(_darker.contains)) {
      hsl = hsl.withLightness((hsl.lightness - 0.18).clamp(0.12, 1.0));
    }
    final c = hsl.toColor();
    final hex = '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    return (hex: hex, exact: exactKnown);
  }

  /// Nombre puesto por la paleta ("Rojo", "Blanco con rojo", "Multicolor") y no
  /// escrito a mano: se puede cambiar solo al elegir otro color
  static bool isPaletteName(String raw) {
    final n = raw.trim().toLowerCase();
    if (n.isEmpty) return true;
    final names = _autoNames;
    if (names.contains(n)) return true;
    final parts = n.split(' con ');
    return parts.length == 2 && names.contains(parts[0].trim()) && names.contains(parts[1].trim());
  }

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

/// Editor visual: tallas arriba y, por cada talla, sus colores y existencias
class VariantEditor extends StatefulWidget {
  final VariantEditorController controller;

  /// Foto del producto, para tomar el color tocando la prenda
  final String? photoPath;

  const VariantEditor({super.key, required this.controller, this.photoPath});

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

  Future<void> _addColor(String size) async {
    final result = await showDialog<VariantColor>(
      context: context,
      builder: (_) => _ColorDialog(
        sizeLabel: size.isEmpty ? null : '${ctrl.attributeName} $size',
        suggestions: ctrl.suggestionsFor(size),
        photoPath: widget.photoPath,
      ),
    );
    if (result != null) ctrl.addColorTo(size, result);
  }

  Future<void> _editColor(String size, VariantColor color) async {
    final result = await showDialog<VariantColor>(
      context: context,
      builder: (_) => _ColorDialog(
        initial: color,
        sizeLabel: size.isEmpty ? null : '${ctrl.attributeName} $size',
        photoPath: widget.photoPath,
      ),
    );
    if (result != null) ctrl.updateColorIn(size, color, result);
  }

  Future<void> _scan(String key) async {
    final code = await CodeReader.pick(context, title: 'Código de la talla o el color', caption: 'Producto');
    if (code != null && code.trim().isNotEmpty) ctrl.setBarcode(key, code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = ctrl.attributeName;
    final section = TextStyle(fontSize: AppText.sizeSmall, fontWeight: FontWeight.w700, color: c.ink);

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
                label: const Text('Ropa', style: TextStyle(fontSize: AppText.sizeCaption)),
                onPressed: () => ctrl.setSizes(['S', 'M', 'L', 'XL']),
              ),
              const SizedBox(width: 4),
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: const Text('Calzado', style: TextStyle(fontSize: AppText.sizeCaption)),
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
                icon: const Icon(Icons.add_outlined),
                onPressed: _addSizeFromInput,
              ),
            ),
            onSubmitted: (_) => _addSizeFromInput(),
          ),

          const SizedBox(height: AppSpace.lg),

          // 2. Existencias: cada talla con sus colores
          Row(
            children: [
              Expanded(child: Text('Existencias', style: section)),
              if (ctrl.combos.isNotEmpty) ...[
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
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Si una ${label.toLowerCase()} viene en varios colores, toca "+ Color" en esa ${label.toLowerCase()}.',
            style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted),
          ),
          const SizedBox(height: AppSpace.sm),
          if (ctrl.sizes.isEmpty)
            // Sin tallas: el producto puede variar solo por color
            _sizeBlock(c, '')
          else
            for (final s in ctrl.sizes) _sizeBlock(c, s),
          if (ctrl.combos.isNotEmpty) ...[
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
            style: TextStyle(fontSize: AppText.sizeSmall, fontWeight: FontWeight.w600, color: c.ink),
          ),
          const SizedBox(height: 2),
          Text(
            '¿Separarlos en talla y color? Las existencias de cada una se conservan.',
            style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: ctrl.splitLegacy, child: const Text('Separar talla y color')),
          ),
        ],
      ),
    );
  }

  /// Una talla: su encabezado con "+ Color" y sus filas de existencias
  Widget _sizeBlock(StockealoColors c, String size) {
    final colors = ctrl.colorsOf(size);
    final title = size.isEmpty ? 'Colores' : '${ctrl.attributeName} $size';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.fromLTRB(AppSpace.sm + 2, 4, 4, AppSpace.sm),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppText.sizeBody, fontWeight: FontWeight.w700, color: c.ink),
                ),
              ),
              TextButton.icon(
                onPressed: () => _addColor(size),
                icon: const Icon(Icons.add_outlined, size: 18),
                label: const Text('Color'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              if (size.isNotEmpty && colors.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Quitar la ${ctrl.attributeName.toLowerCase()} $size',
                  icon: Icon(Icons.delete_outline_outlined, size: 18, color: c.inkMuted),
                  onPressed: () => ctrl.removeSize(size),
                ),
            ],
          ),
          if (colors.isEmpty)
            size.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Agrega tallas arriba o toca "+ Color" si solo varía por color.',
                      style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted),
                    ),
                  )
                : _row(c, size: size, color: null)
          else
            for (final col in colors) _row(c, size: size, color: col),
        ],
      ),
    );
  }

  Widget _row(StockealoColors c, {required String size, required VariantColor? color}) {
    final key = VariantEditorController.cellKey(size, color?.name);
    final cell = ctrl.cellFor(key);
    final hasCode = (cell.barcode ?? '').isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 4, right: 4),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: color == null
                ? Text(
                    'Sin color',
                    style: TextStyle(fontSize: AppText.sizeBody, color: c.inkMuted),
                  )
                : InkWell(
                    onTap: () => _editColor(size, color),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          ColorSwatchDot(hex: color.hex, hex2: color.hex2, size: 18),
                          const SizedBox(width: AppSpace.sm),
                          Flexible(
                            child: Text(
                              color.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: AppText.sizeBody, fontWeight: FontWeight.w600, color: c.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          SizedBox(
            width: 68,
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
            tooltip: hasCode ? 'Código: ${cell.barcode}' : 'Escanear código',
            icon: Icon(
              hasCode ? Icons.qr_code_2_outlined : Icons.qr_code_scanner_outlined,
              size: 18,
              color: hasCode ? c.accent : c.inkMuted,
            ),
            onPressed: () => _scan(key),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: color == null ? 'Quitar la ${ctrl.attributeName.toLowerCase()} $size' : 'Quitar ${color.name} de esta ${ctrl.attributeName.toLowerCase()}',
            icon: Icon(Icons.close_outlined, size: 18, color: c.inkMuted),
            onPressed: () => ctrl.removeCombo(key),
          ),
        ],
      ),
    );
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
              fontSize: AppText.sizeCaption,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
              color: strong ? c.success : c.inkMuted,
            ),
          ),
        );
    final colors = ctrl.colors;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        pill('Total: ${ctrl.totalStock} unid.', strong: true),
        if (colors.isNotEmpty) ...[
          if (ctrl.sizes.length > 1)
            for (final s in ctrl.sizes) pill('$s: ${ctrl.totalForSize(s)}'),
          if (colors.length > 1)
            for (final col in colors) pill('${col.name}: ${ctrl.totalForColor(col)}'),
        ],
      ],
    );
  }
}

/// Elegir nombre y muestra de un color: paleta, código hexadecimal, dos tonos o multicolor
class _ColorDialog extends StatefulWidget {
  final VariantColor? initial;

  /// "Talla M": a qué talla se le agrega el color
  final String? sizeLabel;

  /// Colores ya usados en otras tallas, para ponerlos con un toque
  final List<VariantColor> suggestions;

  /// Foto del producto (si tiene), para tomar el color de ella
  final String? photoPath;

  const _ColorDialog({this.initial, this.sizeLabel, this.suggestions = const [], this.photoPath});

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

  /// La muestra la eligió el dueño a mano para un nombre propio: ya no se cambia
  /// sola al seguir escribiendo el nombre
  bool _swatchPinned = false;

  /// Qué muestra tiene abiertas las barras de "Más colores" (primera o segunda)
  TextEditingController? _slidersFor;

  static String _hexText(String? v) => (v == null || ColorSwatchDot.isMulti(v)) ? '' : v.replaceFirst('#', '');

  @override
  void initState() {
    super.initState();
    _nameTouched = widget.initial != null;
    // Al editar un color con nombre propio, su muestra ya fue elegida: se respeta
    final initial = widget.initial;
    _swatchPinned = initial != null && !VariantEditorController.isPaletteName(initial.name);
  }

  @override
  void dispose() {
    _name.dispose();
    _hex.dispose();
    _hex2.dispose();
    super.dispose();
  }

  /// Al escribir el nombre se pone la muestra que le corresponde ("Rojo" → rojo,
  /// "Azul bajito" → un azul claro), salvo que el dueño ya la haya elegido a mano
  void _nameChanged(String value) {
    setState(() {
      _nameTouched = true;
      if (_swatchPinned) return;
      final match = VariantEditorController.swatchForName(value);
      if (match == null) return;
      if (match.hex == ProductVariant.multicolor) {
        _multi = true;
      } else {
        _multi = false;
        _hex.text = match.hex.replaceFirst('#', '');
      }
    });
  }

  /// "Nombre personalizado" cuando el nombre no es uno de los que la app conoce
  String? get _customNameHint {
    final name = _name.text.trim();
    if (name.isEmpty || VariantEditorController.isPaletteName(name)) return null;
    if (_swatchPinned) return 'Nombre personalizado';
    final match = VariantEditorController.swatchForName(name);
    return match == null
        ? 'Nombre personalizado: elige la muestra abajo'
        : 'Nombre personalizado: pusimos una muestra parecida, cámbiala si quieres';
  }

  void _pick(TextEditingController target, String name, String hex) {
    setState(() {
      // Con un nombre propio, elegir la muestra la deja fija
      if (_nameTouched && !VariantEditorController.isPaletteName(_name.text)) _swatchPinned = true;
      _multi = false;
      target.text = hex.replaceFirst('#', '');
      // El nombre sigue a la paleta salvo que el dueño haya escrito uno propio
      // ("Vinotinto clarito"): así, al cambiar la muestra de un color ya creado,
      // "Rojo" pasa a "Café" en vez de quedar con el nombre viejo
      _proposeName(target, name);
    });
  }

  /// Pone el nombre del color salvo que el dueño haya escrito uno propio. Con dos
  /// tonos arma "Blanco con rojo".
  void _proposeName(TextEditingController target, String name) {
    if (_nameTouched && !VariantEditorController.isPaletteName(_name.text)) return;
    final current = _name.text.trim();
    if (target == _hex) {
      final second = current.contains(' con ') ? current.split(' con ').last.trim() : null;
      _name.text = (_twoTones && second != null) ? '$name con $second' : name;
    } else {
      final first = current.contains(' con ') ? current.split(' con ').first.trim() : current;
      _name.text = first.isEmpty ? name : '$first con ${name.toLowerCase()}';
    }
  }

  /// Color elegido con las barras, la foto o el gotero (no de la paleta): el nombre
  /// propuesto es el del color de la paleta más parecido
  void _setColor(TextEditingController target, Color color) {
    final hex = '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    _pick(target, VariantEditorController.colorNameFor(color), hex);
  }

  Color? _colorOf(TextEditingController target) {
    final hex = ProductVariant.validHex(target.text);
    return hex == null ? null : Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  Future<void> _fromPhoto(TextEditingController target) async {
    final color = await PhotoColorPicker.show(context, widget.photoPath!);
    if (color != null && mounted) _setColor(target, color);
  }

  Future<void> _fromScreen(TextEditingController target) async {
    final hex = await pickScreenColor();
    final color = hex == null ? null : Color(int.parse('FF${hex.substring(1)}', radix: 16));
    if (color != null && mounted) _setColor(target, color);
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

    final hasPhoto = (widget.photoPath ?? '').trim().isNotEmpty;
    // Para quien no encuentra su color en la paleta: barras, foto o gotero
    Widget moreWays(TextEditingController target) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ActionChip(
                  avatar: Icon(_slidersFor == target ? Icons.expand_less_outlined : Icons.tune_outlined, size: 18),
                  label: const Text('Más colores'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _slidersFor = _slidersFor == target ? null : target),
                ),
                if (hasPhoto)
                  ActionChip(
                    avatar: const Icon(Icons.photo_outlined, size: 18),
                    label: const Text('De la foto'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _fromPhoto(target),
                  ),
                if (canUseEyeDropper)
                  ActionChip(
                    avatar: const Icon(Icons.colorize_outlined, size: 18),
                    label: const Text('Tomar de la pantalla'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _fromScreen(target),
                  ),
              ],
            ),
            if (_slidersFor == target) ...[
              const SizedBox(height: AppSpace.sm),
              ColorSliders(value: _colorOf(target), onChanged: (color) => _setColor(target, color)),
            ],
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
          onChanged: (v) => setState(() {
            _multi = false;
            final hex = ProductVariant.validHex(v);
            if (hex != null) {
              _proposeName(ctrl, VariantEditorController.colorNameFor(Color(int.parse('FF${hex.substring(1)}', radix: 16))));
            }
          }),
        );

    final canSave = _name.text.trim().isNotEmpty;
    return AppDialog(
title: widget.initial == null
            ? (widget.sizeLabel == null ? 'Agregar color' : 'Agregar color a la ${widget.sizeLabel!.toLowerCase()}')
            : 'Editar color',
content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.suggestions.isNotEmpty) ...[
                Text('Ya usados', style: TextStyle(fontSize: AppText.sizeSmall, fontWeight: FontWeight.w700, color: c.ink)),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in widget.suggestions)
                      ActionChip(
                        avatar: ColorSwatchDot(hex: s.hex, hex2: s.hex2, size: 18),
                        label: Text(s.name),
                        onPressed: () => Navigator.pop(context, s.copy()),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Text('O uno nuevo', style: TextStyle(fontSize: AppText.sizeSmall, fontWeight: FontWeight.w700, color: c.ink)),
                const SizedBox(height: AppSpace.sm),
              ],
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
                      decoration: InputDecoration(
                        labelText: 'Nombre del color',
                        hintText: 'Ej. Rojo, Azul bajito, Blanco con rojo',
                        helperText: _customNameHint,
                        helperMaxLines: 2,
                        helperStyle: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted),
                      ),
                      onChanged: _nameChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              Text('Muestra', style: TextStyle(fontSize: AppText.sizeSmall, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: AppSpace.sm),
              paletteFor(_hex),
              const SizedBox(height: AppSpace.sm),
              moreWays(_hex),
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
                moreWays(_hex2),
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
              // El código solo lo necesita quien ya lo tiene (por ejemplo, de su marca)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  // Arriba hay que dejar sitio a la etiqueta flotante del campo: sin él,
                  // "Código del color (hexadecimal)" quedaba cortada contra el título
                  childrenPadding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.sm),
                  initiallyExpanded: false,
                  title: Text('Opciones avanzadas', style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
                  children: [
                    hexField(_hex, 'Código del color (hexadecimal)'),
                    if (_twoTones && !_multi) ...[
                      const SizedBox(height: AppSpace.sm),
                      hexField(_hex2, 'Segundo color (hexadecimal)'),
                    ],
                  ],
                ),
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
