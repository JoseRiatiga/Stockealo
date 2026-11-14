import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Candados del re-diseño 0.13.0 (docs/inventario-rediseno.md, sección 4).
///
/// Cuentan lo que queda del diseño viejo en lib/. Los números SOLO pueden bajar:
/// si alguien agrega un color a mano, un `isDark`, un tamaño de letra suelto, un
/// SnackBar o un AlertDialog, la prueba falla. Cuando un bloque del re-diseño los
/// quita, se baja el número aquí. Al terminar el re-diseño todos quedan en 0.
const _locks = <String, int>{
  'colores a mano (Color(0x…))': 0,
  'colores de Material a mano (Colors.x)': 0,
  'claro/oscuro decidido a mano (isDark)': 2, // el tema de la app y la plantilla Moda de la tienda (oscura a propósito)
  'tamaños de letra sueltos (fontSize: 13)': 26,
  'avisos viejos (SnackBar)': 0,
  'ventanas armadas a mano (AlertDialog)': 0,
  'íconos redondeados (familia vieja)': 0,
  'ventana vieja (ModernDialog)': 0,
};

/// Archivos donde los colores escritos a mano son DATOS, no diseño: la paleta, las
/// banderas, los colores que elige el negocio, el dibujo de Stocky, etc.
const _colorData = {
  'lib/core/theme/app_tokens.dart',
  'lib/core/theme/flag_colors.dart',
  'lib/core/theme/stocky_palette.dart',
  'lib/core/design/country_flag.dart',
  'lib/core/design/color_swatch_dot.dart',
  'lib/core/design/color_sliders.dart',
  'lib/features/products/presentation/widgets/photo_color_picker.dart',
  'lib/features/business/presentation/business_identity.dart',
  'lib/features/auth/presentation/widgets/stocky_mascot.dart',
  'lib/features/products/presentation/widgets/story_catalog_modal.dart',
};

Map<String, int> _count() {
  final patterns = <String, RegExp>{
    'colores a mano (Color(0x…))': RegExp(r'Color\(0x'),
    'colores de Material a mano (Colors.x)': RegExp(r'\bColors\.(?!transparent\b|white\b|black\b)[a-zA-Z]+'),
    'claro/oscuro decidido a mano (isDark)': RegExp(r'\bisDark\b|Brightness\.dark|brightness =='),
    'tamaños de letra sueltos (fontSize: 13)': RegExp(r'fontSize:\s*[0-9]'),
    'avisos viejos (SnackBar)': RegExp(r'SnackBar\('),
    'ventanas armadas a mano (AlertDialog)': RegExp(r'AlertDialog\('),
    'íconos redondeados (familia vieja)': RegExp(r'Icons\.[a-z0-9_]+_rounded'),
    'ventana vieja (ModernDialog)': RegExp(r'ModernDialog|ModernConfirmDialog'),
  };
  final totals = {for (final k in patterns.keys) k: 0};
  final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  for (final file in files) {
    final path = file.path.replaceAll('\\', '/');
    final text = file.readAsStringSync();
    patterns.forEach((key, re) {
      if (key.startsWith('colores') && _colorData.contains(path)) return;
      if (key.startsWith('avisos') && path.endsWith('app_toast.dart')) return;
      if (key.startsWith('claro/oscuro') && path.startsWith('lib/core/theme/')) return;
      totals[key] = totals[key]! + re.allMatches(text).length;
    });
  }
  return totals;
}

void main() {
  final totals = _count();
  for (final entry in _locks.entries) {
    test('candado: ${entry.key} no sube de ${entry.value}', () {
      expect(
        totals[entry.key],
        lessThanOrEqualTo(entry.value),
        reason: 'Volvió algo del diseño viejo: ${entry.key}. Usa las fichas del sistema '
            '(context.colors, AppText, AppDialog, AppSheet, AppToast, íconos _outlined).',
      );
    });
  }

  test('los candados se bajan cuando un bloque quita cosas viejas', () {
    final slack = <String>[];
    for (final entry in _locks.entries) {
      if (totals[entry.key]! < entry.value) slack.add('${entry.key}: ${entry.value} → ${totals[entry.key]}');
    }
    expect(slack, isEmpty, reason: 'Baja estos números en design_locks_test.dart: ${slack.join('; ')}');
  });
}
