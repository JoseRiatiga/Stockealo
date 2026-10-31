import 'package:flutter/material.dart';

/// Sistema de diseño V1 de Stockealo: fondo cálido tipo papel, tarjetas sólidas con
/// borde fino y sin sombras, verde de la marca solo en lo importante.
///
/// Las pantallas no escriben colores a mano: leen [StockealoColors] con
/// `context.colors` (ver docs/design-system.md).
class AppPalette {
  AppPalette._();

  /// Verde de Stockealo (acento por defecto)
  static const Color brand = Color(0xFF1E6B4E);

  // --- Modo claro ---
  static const Color paper = Color(0xFFF6F3EC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF1EDE4);
  static const Color line = Color(0xFFECE7DC);
  static const Color lineStrong = Color(0xFFDDD6C8);
  static const Color ink = Color(0xFF1F1D18);
  static const Color inkMuted = Color(0xFF6E6A60);
  static const Color inkFaint = Color(0xFF8F8A7E);
  static const Color success = Color(0xFF1E6B4E);
  static const Color warning = Color(0xFF8A5300);
  static const Color danger = Color(0xFFB42318);
  static const Color info = Color(0xFF1D5FA8);
  static const Color successSoft = Color(0xFFE3F0E9);
  static const Color warningSoft = Color(0xFFFBEFD9);
  static const Color dangerSoft = Color(0xFFFBE7E5);
  static const Color infoSoft = Color(0xFFE4EEF9);

  // --- Modo oscuro (cálido, no solo invertido) ---
  static const Color paperDark = Color(0xFF14130F);
  static const Color surfaceDark = Color(0xFF1E1C18);
  static const Color surfaceMutedDark = Color(0xFF272420);
  static const Color lineDark = Color(0xFF2F2C26);
  static const Color lineStrongDark = Color(0xFF3D3932);
  static const Color inkDark = Color(0xFFF2EEE5);
  static const Color inkMutedDark = Color(0xFFB1AB9F);
  static const Color inkFaintDark = Color(0xFF8E887C);
  static const Color successDark = Color(0xFF5CC497);
  static const Color warningDark = Color(0xFFE8B25A);
  static const Color dangerDark = Color(0xFFF2877C);
  static const Color infoDark = Color(0xFF7DB2EC);
  static const Color successSoftDark = Color(0xFF1C2E25);
  static const Color warningSoftDark = Color(0xFF33281A);
  static const Color dangerSoftDark = Color(0xFF3A201D);
  static const Color infoSoftDark = Color(0xFF1C2A3A);

  /// Colores que un negocio puede elegir. Todos llevan texto blanco encima con
  /// contraste AA (lo comprueba test/core/theme/app_tokens_test.dart).
  static const Map<String, Color> businessColors = {
    'verde': Color(0xFF1E6B4E),
    'azul': Color(0xFF1D5FA8),
    'indigo': Color(0xFF4338CA),
    'morado': Color(0xFF6D28D9),
    'rosa': Color(0xFFBE185D),
    'rojo': Color(0xFFB42318),
    'terracota': Color(0xFFA9481F),
    'cafe': Color(0xFF7C4A1E),
    'turquesa': Color(0xFF0F766E),
    'grafito': Color(0xFF3F3F46),
  };

  /// Color "#RRGGBB" de la paleta del negocio; null si no es válido
  static Color? fromHex(String? hex) {
    if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return null;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  /// "#RRGGBB" de un color, para guardarlo en el negocio
  static String toHex(Color color) =>
      '#${(color.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Espaciados (múltiplos de 4)
class AppSpace {
  AppSpace._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Radios de esquina
class AppRadius {
  AppRadius._();
  static const double control = 12;
  static const double card = 16;
  static const double sheet = 24;
  static const double pill = 999;
}

/// Colores de la interfaz según el modo y el acento activo
@immutable
class StockealoColors extends ThemeExtension<StockealoColors> {
  final Color paper;
  final Color surface;
  final Color surfaceMuted;
  final Color line;
  final Color lineStrong;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color accent;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color successSoft;
  final Color warningSoft;
  final Color dangerSoft;
  final Color infoSoft;

  /// Fondo de las barras de cristal (encabezado y pestañas)
  final Color glass;

  /// Fondo de los avisos (oscuro y discreto en ambos modos)
  final Color toast;
  final Color onToast;

  const StockealoColors({
    required this.paper,
    required this.surface,
    required this.surfaceMuted,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.accent,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.successSoft,
    required this.warningSoft,
    required this.dangerSoft,
    required this.infoSoft,
    required this.glass,
    required this.toast,
    required this.onToast,
  });

  factory StockealoColors.light({Color accent = AppPalette.brand}) => StockealoColors(
        paper: AppPalette.paper,
        surface: AppPalette.surface,
        surfaceMuted: AppPalette.surfaceMuted,
        line: AppPalette.line,
        lineStrong: AppPalette.lineStrong,
        ink: AppPalette.ink,
        inkMuted: AppPalette.inkMuted,
        inkFaint: AppPalette.inkFaint,
        accent: accent,
        onAccent: Colors.white,
        success: AppPalette.success,
        warning: AppPalette.warning,
        danger: AppPalette.danger,
        info: AppPalette.info,
        successSoft: AppPalette.successSoft,
        warningSoft: AppPalette.warningSoft,
        dangerSoft: AppPalette.dangerSoft,
        infoSoft: AppPalette.infoSoft,
        glass: const Color(0xB8FFFFFF),
        toast: AppPalette.ink,
        onToast: AppPalette.paper,
      );

  factory StockealoColors.dark({Color accent = AppPalette.brand}) => StockealoColors(
        paper: AppPalette.paperDark,
        surface: AppPalette.surfaceDark,
        surfaceMuted: AppPalette.surfaceMutedDark,
        line: AppPalette.lineDark,
        lineStrong: AppPalette.lineStrongDark,
        ink: AppPalette.inkDark,
        inkMuted: AppPalette.inkMutedDark,
        inkFaint: AppPalette.inkFaintDark,
        accent: accent,
        onAccent: Colors.white,
        success: AppPalette.successDark,
        warning: AppPalette.warningDark,
        danger: AppPalette.dangerDark,
        info: AppPalette.infoDark,
        successSoft: AppPalette.successSoftDark,
        warningSoft: AppPalette.warningSoftDark,
        dangerSoft: AppPalette.dangerSoftDark,
        infoSoft: AppPalette.infoSoftDark,
        glass: const Color(0xC21E1C18),
        toast: const Color(0xFF2E2B25),
        onToast: AppPalette.inkDark,
      );

  @override
  StockealoColors copyWith({Color? accent}) {
    return StockealoColors(
      paper: paper,
      surface: surface,
      surfaceMuted: surfaceMuted,
      line: line,
      lineStrong: lineStrong,
      ink: ink,
      inkMuted: inkMuted,
      inkFaint: inkFaint,
      accent: accent ?? this.accent,
      onAccent: onAccent,
      success: success,
      warning: warning,
      danger: danger,
      info: info,
      successSoft: successSoft,
      warningSoft: warningSoft,
      dangerSoft: dangerSoft,
      infoSoft: infoSoft,
      glass: glass,
      toast: toast,
      onToast: onToast,
    );
  }

  @override
  StockealoColors lerp(ThemeExtension<StockealoColors>? other, double t) {
    if (other is! StockealoColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return StockealoColors(
      paper: l(paper, other.paper),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      line: l(line, other.line),
      lineStrong: l(lineStrong, other.lineStrong),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      inkFaint: l(inkFaint, other.inkFaint),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      info: l(info, other.info),
      successSoft: l(successSoft, other.successSoft),
      warningSoft: l(warningSoft, other.warningSoft),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      infoSoft: l(infoSoft, other.infoSoft),
      glass: l(glass, other.glass),
      toast: l(toast, other.toast),
      onToast: l(onToast, other.onToast),
    );
  }
}

/// Estilos de texto propios de Stockealo
class AppText {
  AppText._();

  /// Tipografía de la app (incluida en el instalador; si falta, se usa la del sistema)
  static const String fontFamily = 'Inter';

  /// Montos y cantidades: números de ancho fijo para que las cifras queden alineadas
  static TextStyle amount(BuildContext context, {double size = 15, FontWeight weight = FontWeight.w700, Color? color}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -0.2,
        color: color ?? context.colors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

extension StockealoThemeContext on BuildContext {
  /// Colores del sistema de diseño: `context.colors.accent`, `context.colors.inkMuted`...
  StockealoColors get colors =>
      Theme.of(this).extension<StockealoColors>() ??
      (Theme.of(this).brightness == Brightness.dark ? StockealoColors.dark() : StockealoColors.light());
}
