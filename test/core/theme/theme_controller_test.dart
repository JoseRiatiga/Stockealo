import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_tokens.dart';
import 'package:stockealo/core/theme/theme_controller.dart';

void main() {
  final theme = ThemeController.instance;

  tearDown(theme.discardChanges);

  test('los cambios se ven al instante y quedan pendientes', () {
    expect(theme.hasPendingChanges, isFalse);
    theme.setAccentChoice('#BE185D');
    theme.setTextScale(1.15);

    expect(theme.accent, AppPalette.fromHex('#BE185D'));
    expect(theme.textScale, 1.15);
    final changes = theme.pendingChanges;
    expect(changes.map((c) => c.label), ['Color del tema', 'Tamaño de letra']);
    expect(changes.first.before, 'Verde Stockealo');
    expect(changes.first.after, 'Rosa');
    expect(changes.last.after, 'Grande');
  });

  test('descartar vuelve a lo guardado', () {
    theme.setThemeMode(ThemeMode.dark);
    theme.setReduceTransparency(true);
    expect(theme.pendingChanges, hasLength(2));

    theme.discardChanges();
    expect(theme.hasPendingChanges, isFalse);
    expect(theme.themeMode, ThemeMode.system);
    expect(theme.reduceTransparency, isFalse);
  });

  test('volver al valor original no cuenta como cambio', () {
    theme.setTextScale(1.3);
    theme.setTextScale(1.0);
    expect(theme.hasPendingChanges, isFalse);
  });

  test('el color del negocio sigue al negocio activo', () {
    theme.setBusinessColor('#1D5FA8');
    theme.setAccentChoice('business');
    expect(theme.accent, AppPalette.fromHex('#1D5FA8'));
    theme.setBusinessColor(null);
    expect(theme.accent, AppPalette.brand);
  });

  test('nombres de los colores en español', () {
    expect(ThemeController.accentLabel('brand'), 'Verde Stockealo');
    expect(ThemeController.accentLabel('business'), 'Color del negocio');
    expect(ThemeController.accentLabel('#4338CA'), 'Índigo');
    expect(ThemeController.accentLabel('#7C4A1E'), 'Café');
  });

  group('claro u oscuro (0.12.1)', () {
    tearDown(() async => theme.setThemeModeNow(ThemeMode.system));

    test('el interruptor de Apariencia aplica y guarda en el acto, sin dejar cambios pendientes', () async {
      await theme.setThemeModeNow(ThemeMode.dark);
      expect(theme.themeMode, ThemeMode.dark);
      expect(theme.hasPendingChanges, isFalse);
      await theme.setThemeModeNow(ThemeMode.light);
      expect(theme.themeMode, ThemeMode.light);
      expect(theme.hasPendingChanges, isFalse);
    });

    test('el acceso rápido cambia lo que se ve aunque la app siga al sistema', () async {
      await theme.setThemeModeNow(ThemeMode.system);
      // El sistema está en oscuro: antes no cambiaba nada; ahora pasa a claro
      await theme.toggleTheme(current: Brightness.dark);
      expect(theme.themeMode, ThemeMode.light);
      await theme.toggleTheme(current: Brightness.light);
      expect(theme.themeMode, ThemeMode.dark);
    });
  });
}
