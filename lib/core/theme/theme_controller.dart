import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import 'app_tokens.dart';

/// Preferencias visuales de este dispositivo
@immutable
class ThemePrefs {
  final ThemeMode themeMode;

  /// 'brand' (verde Stockealo), 'business' (color del negocio activo) o "#RRGGBB"
  final String accentChoice;

  /// Tamaño de letra: uno de [ThemeController.textScales]
  final double textScale;

  /// Barras sólidas en vez de cristal (accesibilidad o equipos lentos)
  final bool reduceTransparency;

  const ThemePrefs({
    this.themeMode = ThemeMode.system,
    this.accentChoice = 'brand',
    this.textScale = 1.0,
    this.reduceTransparency = false,
  });

  ThemePrefs copyWith({ThemeMode? themeMode, String? accentChoice, double? textScale, bool? reduceTransparency}) =>
      ThemePrefs(
        themeMode: themeMode ?? this.themeMode,
        accentChoice: accentChoice ?? this.accentChoice,
        textScale: textScale ?? this.textScale,
        reduceTransparency: reduceTransparency ?? this.reduceTransparency,
      );

  @override
  bool operator ==(Object other) =>
      other is ThemePrefs &&
      other.themeMode == themeMode &&
      other.accentChoice == accentChoice &&
      other.textScale == textScale &&
      other.reduceTransparency == reduceTransparency;

  @override
  int get hashCode => Object.hash(themeMode, accentChoice, textScale, reduceTransparency);
}

/// Un ajuste cambiado y aún sin guardar, para la hoja "Revisar cambios"
class PreferenceChange {
  final String label;
  final String before;
  final String after;

  const PreferenceChange(this.label, this.before, this.after);
}

/// Preferencias visuales: modo claro u oscuro, color, tamaño de letra y
/// transparencias. Los cambios se ven al instante y se guardan al confirmarlos
/// (barra "N cambios · Descartar · Revisar" de Ajustes).
class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  static const _themeModeKey = 'theme_mode';
  static const _accentChoiceKey = 'accent_choice';
  static const _textScaleKey = 'text_scale';
  static const _reduceTransparencyKey = 'reduce_transparency';

  /// Clave anterior a la 0.9.0 (sí/no al color del negocio)
  static const _legacyUseBusinessColorKey = 'use_business_color';

  static final Map<double, String> textScales = {
    0.9: 'Pequeña',
    1.0: 'Normal',
    1.15: 'Grande',
    1.3: 'Muy grande',
  };

  ThemePrefs _saved = const ThemePrefs();
  ThemePrefs _current = const ThemePrefs();

  /// Lo que se ve ahora (puede tener cambios sin guardar)
  ThemePrefs get prefs => _current;

  ThemeMode get themeMode => _current.themeMode;
  bool get isDarkMode => _current.themeMode == ThemeMode.dark;
  String get accentChoice => _current.accentChoice;
  bool get useBusinessColor => _current.accentChoice == 'business';
  double get textScale => _current.textScale;
  bool get reduceTransparency => _current.reduceTransparency;

  /// Color elegido por el negocio activo ("#RRGGBB"), lo informa BusinessRepository
  String? _businessColorHex;
  String? get businessColorHex => _businessColorHex;

  /// Acento de la interfaz según la elección
  Color get accent => accentFor(_current.accentChoice);

  Color accentFor(String choice) => switch (choice) {
        'brand' => AppPalette.brand,
        'business' => AppPalette.fromHex(_businessColorHex) ?? AppPalette.brand,
        _ => AppPalette.fromHex(choice) ?? AppPalette.brand,
      };

  Future<void> initialize() async {
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query(
        'app_settings',
        where: 'key IN (?, ?, ?, ?, ?)',
        whereArgs: [_themeModeKey, _accentChoiceKey, _textScaleKey, _reduceTransparencyKey, _legacyUseBusinessColorKey],
      );
      final values = {for (final r in rows) r['key'] as String: r['value'] as String?};
      final scale = double.tryParse(values[_textScaleKey] ?? '') ?? 1.0;
      _saved = ThemePrefs(
        themeMode: switch (values[_themeModeKey]) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.system,
        },
        accentChoice: values[_accentChoiceKey] ?? (values[_legacyUseBusinessColorKey] == '1' ? 'business' : 'brand'),
        textScale: textScales.containsKey(scale) ? scale : 1.0,
        reduceTransparency: values[_reduceTransparencyKey] == '1',
      );
      _current = _saved;
    } catch (_) {}
    notifyListeners();
  }

  void _update(ThemePrefs next) {
    if (next == _current) return;
    _current = next;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) => _update(_current.copyWith(themeMode: mode));
  void setAccentChoice(String choice) => _update(_current.copyWith(accentChoice: choice));
  void setTextScale(double scale) => _update(_current.copyWith(textScale: scale));
  void setReduceTransparency(bool value) => _update(_current.copyWith(reduceTransparency: value));

  /// Atajo del encabezado: cambia y guarda en el acto, sin pasar por la revisión
  Future<void> toggleTheme() async {
    final mode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
    _saved = _saved.copyWith(themeMode: mode);
    _update(_current.copyWith(themeMode: mode));
    await _persist({_themeModeKey: _modeValue(mode)});
  }

  bool get hasPendingChanges => _current != _saved;

  /// Lista de cambios sin guardar, con el valor anterior y el nuevo
  List<PreferenceChange> get pendingChanges => [
        if (_current.themeMode != _saved.themeMode)
          PreferenceChange('Modo oscuro', themeModeLabel(_saved.themeMode), themeModeLabel(_current.themeMode)),
        if (_current.accentChoice != _saved.accentChoice)
          PreferenceChange('Color del tema', accentLabel(_saved.accentChoice), accentLabel(_current.accentChoice)),
        if (_current.textScale != _saved.textScale)
          PreferenceChange('Tamaño de letra', textScales[_saved.textScale]!, textScales[_current.textScale]!),
        if (_current.reduceTransparency != _saved.reduceTransparency)
          PreferenceChange('Reducir transparencias', _saved.reduceTransparency ? 'Activado' : 'Desactivado',
              _current.reduceTransparency ? 'Activado' : 'Desactivado'),
      ];

  Future<void> saveChanges() async {
    final next = _current;
    _saved = next;
    notifyListeners();
    await _persist({
      _themeModeKey: _modeValue(next.themeMode),
      _accentChoiceKey: next.accentChoice,
      _textScaleKey: next.textScale.toString(),
      _reduceTransparencyKey: next.reduceTransparency ? '1' : '0',
    });
  }

  void discardChanges() => _update(_saved);

  /// El negocio activo cambió (o cambió su color)
  void setBusinessColor(String? hex) {
    if (_businessColorHex == hex) return;
    _businessColorHex = hex;
    if (useBusinessColor || _saved.accentChoice == 'business') notifyListeners();
  }

  static String themeModeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.dark => 'Oscuro',
        ThemeMode.light => 'Claro',
        ThemeMode.system => 'Como el teléfono',
      };

  static String accentLabel(String choice) {
    if (choice == 'brand') return 'Verde Stockealo';
    if (choice == 'business') return 'Color del negocio';
    final name = AppPalette.businessColors.entries
        .where((e) => AppPalette.toHex(e.value) == choice)
        .map((e) => e.key)
        .firstOrNull;
    if (name == null) return choice;
    return switch (name) {
      'indigo' => 'Índigo',
      'cafe' => 'Café',
      _ => '${name[0].toUpperCase()}${name.substring(1)}',
    };
  }

  static String _modeValue(ThemeMode mode) =>
      mode == ThemeMode.dark ? 'dark' : (mode == ThemeMode.light ? 'light' : 'system');

  Future<void> _persist(Map<String, String> values) async {
    try {
      final db = await AppDatabase.instance.database;
      final batch = db.batch();
      values.forEach((key, value) {
        batch.insert('app_settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
      });
      await batch.commit(noResult: true);
    } catch (_) {}
  }
}
