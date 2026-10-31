import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_tokens.dart';

/// Contraste WCAG entre dos colores (1 a 21)
double contrast(Color a, Color b) {
  double channel(int v) {
    final s = v / 255;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  double luminance(Color c) => 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue);
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('contraste (WCAG AA = 4.5)', () {
    test('el texto blanco se lee sobre todos los colores de negocio', () {
      for (final entry in AppPalette.businessColors.entries) {
        expect(contrast(Colors.white, entry.value), greaterThanOrEqualTo(4.5), reason: entry.key);
      }
    });

    test('textos del modo claro sobre papel y tarjetas', () {
      for (final bg in [AppPalette.paper, AppPalette.surface]) {
        expect(contrast(AppPalette.ink, bg), greaterThanOrEqualTo(7));
        expect(contrast(AppPalette.inkMuted, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppPalette.danger, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppPalette.warning, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppPalette.success, bg), greaterThanOrEqualTo(4.5));
      }
    });

    test('textos del modo oscuro sobre papel y tarjetas', () {
      for (final bg in [AppPalette.paperDark, AppPalette.surfaceDark]) {
        expect(contrast(AppPalette.inkDark, bg), greaterThanOrEqualTo(7));
        expect(contrast(AppPalette.inkMutedDark, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppPalette.dangerDark, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppPalette.warningDark, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppPalette.successDark, bg), greaterThanOrEqualTo(4.5));
      }
    });

    test('los colores de estado se leen sobre su fondo suave', () {
      expect(contrast(AppPalette.danger, AppPalette.dangerSoft), greaterThanOrEqualTo(4.5));
      expect(contrast(AppPalette.warning, AppPalette.warningSoft), greaterThanOrEqualTo(4.5));
      expect(contrast(AppPalette.success, AppPalette.successSoft), greaterThanOrEqualTo(4.5));
      expect(contrast(AppPalette.info, AppPalette.infoSoft), greaterThanOrEqualTo(4.5));
    });
  });

  group('colores del negocio', () {
    test('convierte entre Color y "#RRGGBB"', () {
      expect(AppPalette.toHex(AppPalette.brand), '#1E6B4E');
      expect(AppPalette.fromHex('#1e6b4e'), AppPalette.brand);
    });

    test('un valor inválido no es un color', () {
      expect(AppPalette.fromHex(null), isNull);
      expect(AppPalette.fromHex('verde'), isNull);
      expect(AppPalette.fromHex('#12345'), isNull);
    });
  });

  test('no se agregan colores escritos a mano fuera del tema', () {
    // Las pantallas usan context.colors. Este número solo puede bajar a medida que
    // se rediseñan; si una pantalla agrega un Color(0x...) nuevo, la prueba falla.
    const baseline = 856;
    final count = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.replaceAll('\\', '/').contains('lib/core/theme/'))
        .map((f) => RegExp(r'Color\(0x').allMatches(f.readAsStringSync()).length)
        .fold<int>(0, (a, b) => a + b);
    expect(count, lessThanOrEqualTo(baseline),
        reason: 'Usa context.colors en vez de Color(0x...). Si quitaste colores, baja el número de baseline.');
  });
}
