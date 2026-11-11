import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sistema de diseño de Stockealo (re-diseño 0.13.0, aprobado el 11 nov 2026):
/// claro y limpio, tarjetas blancas con borde fino y sin sombras, el color de cada
/// negocio solo en lo activo y un color propio para cada estado.
/// Tablero aprobado: https://claude.ai/artifact/JQtmF7vnoWhwMBujRAMitb
///
/// Las pantallas no escriben colores a mano: leen [StockealoColors] con
/// `context.colors`, la letra con [AppText] y las medidas con [AppSpace] y
/// [AppRadius] (ver docs/design-system.md y docs/inventario-rediseno.md).
class AppPalette {
  AppPalette._();

  /// Verde de Stockealo (color por defecto de los negocios)
  static const Color brand = Color(0xFF1E6B4E);

  /// Verde de WhatsApp (color de su marca, para el botón de enviar por WhatsApp)
  static const Color whatsapp = Color(0xFF25D366);

  // --- Modo claro (principal) ---
  static const Color paper = Color(0xFFF6F7F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEEF0F3);
  static const Color line = Color(0xFFE6E8EC);
  static const Color lineStrong = Color(0xFFD5D9E0);
  static const Color ink = Color(0xFF14161A);
  static const Color inkMuted = Color(0xFF5B6170);
  static const Color inkFaint = Color(0xFF646B78);
  static const Color success = Color(0xFF15703A);
  static const Color warning = Color(0xFFA8490A);
  static const Color danger = Color(0xFFB91C1C);
  static const Color info = Color(0xFF1D4ED8);
  static const Color successSoft = Color(0xFFDCFCE7);
  static const Color warningSoft = Color(0xFFFEF3C7);
  static const Color dangerSoft = Color(0xFFFEE2E2);
  static const Color infoSoft = Color(0xFFDBEAFE);

  // --- Modo oscuro (completo, no solo invertido) ---
  static const Color paperDark = Color(0xFF0E1013);
  static const Color surfaceDark = Color(0xFF16191E);
  static const Color surfaceMutedDark = Color(0xFF1E2228);
  static const Color lineDark = Color(0xFF262A31);
  static const Color lineStrongDark = Color(0xFF343943);
  static const Color inkDark = Color(0xFFF2F4F7);
  static const Color inkMutedDark = Color(0xFFA3AAB8);
  static const Color inkFaintDark = Color(0xFF8A91A0);
  static const Color successDark = Color(0xFF4ADE80);
  static const Color warningDark = Color(0xFFFBBF24);
  static const Color dangerDark = Color(0xFFF87171);
  static const Color infoDark = Color(0xFF60A5FA);
  static const Color successSoftDark = Color(0xFF14281D);
  static const Color warningSoftDark = Color(0xFF2E2614);
  static const Color dangerSoftDark = Color(0xFF351B1C);
  static const Color infoSoftDark = Color(0xFF172539);

  /// Contraste WCAG entre dos colores (de 1 a 21)
  static double contrast(Color a, Color b) {
    double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    double lum(Color c) => 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
    final la = lum(a), lb = lum(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// El color del negocio, oscurecido lo justo para que el texto blanco encima se
  /// lea (contraste 4.5). Los colores de la paleta ya cumplen y no cambian.
  static Color readable(Color accent) {
    var hsl = HSLColor.fromColor(accent);
    var color = accent;
    while (contrast(Colors.white, color) < 4.5 && hsl.lightness > 0.05) {
      hsl = hsl.withLightness(hsl.lightness - 0.02);
      color = hsl.toColor();
    }
    return color;
  }

  /// Dorado de Stockealo Pro (la corona de las opciones Pro)
  static const Color proGold = Color(0xFFF2B21B);

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
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Colores de las series de las gráficas (categorías): el acento primero y luego
/// tonos de la paleta que se distinguen entre sí en claro y en oscuro
List<Color> chartSeries(StockealoColors c) => [
      c.accent,
      c.info,
      c.warning,
      AppPalette.businessColors['morado']!,
      AppPalette.businessColors['terracota']!,
    ];

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

  /// Etiquetas pequeñas, teclas y cuadritos de código
  static const double small = 8;

  /// Íconos con fondo y miniaturas de producto
  static const double tile = 10;

  /// Botones, campos y filas
  static const double control = 12;

  /// Tarjetas
  static const double card = 16;

  /// Ventanas y hojas que suben
  static const double sheet = 22;
  static const double pill = 999;
}

/// Tiempos del movimiento. Cortos y discretos; con «reducir movimiento» activado
/// en el celular todo aparece de una vez ([AppMotion.of]).
class AppMotion {
  AppMotion._();
  static const Duration quick = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);

  /// El tiquete que «sale de la impresora»
  static const Duration print = Duration(milliseconds: 900);
  static const Curve curve = Curves.easeOutCubic;

  /// La duración pedida, o cero si la persona pidió menos movimiento
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
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

  factory StockealoColors.light({Color accent = AppPalette.brand}) => StockealoColors._light(AppPalette.readable(accent));

  factory StockealoColors._light(Color accent) => StockealoColors(
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
        // Sin cristal en el diseño nuevo: el encabezado es una superficie sólida
        glass: AppPalette.surface,
        toast: AppPalette.ink,
        onToast: AppPalette.paper,
      );

  factory StockealoColors.dark({Color accent = AppPalette.brand}) => StockealoColors._dark(AppPalette.readable(accent));

  factory StockealoColors._dark(Color accent) => StockealoColors(
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
        glass: AppPalette.surfaceDark,
        toast: AppPalette.surfaceMutedDark,
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
      accent: accent == null ? this.accent : AppPalette.readable(accent),
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

/// Letra de Stockealo: Inter (incluida en la app) con UNA escala fija. Las
/// pantallas no escriben `fontSize` sueltos: usan estos estilos.
class AppText {
  AppText._();

  /// Tipografía de la app (incluida en el instalador; si falta, se usa la del sistema)
  static const String fontFamily = 'Inter';

  /// Letra de máquina para códigos de barras y tiquetes (la del sistema, sin descargar nada)
  static const String monoFamily = 'monospace';
  static const List<String> monoFallback = ['Roboto Mono', 'Menlo', 'Consolas', 'Courier New'];

  // La escala completa (cualquier otro tamaño es un error de diseño)
  static const double sizeCaption = 12;
  static const double sizeSmall = 13;
  static const double sizeBody = 14;
  static const double sizeBodyLarge = 15;
  static const double sizeTitle = 16;
  static const double sizeHeading = 20;
  static const double sizePage = 26;
  static const double sizeDisplay = 32;
  static const double sizeFigure = 40;

  /// Solo los números grandes del reloj para elegir la hora
  static const double sizeClock = 52;
  static const List<double> scale = [
    sizeCaption, sizeSmall, sizeBody, sizeBodyLarge, sizeTitle, sizeHeading, sizePage, sizeDisplay, sizeFigure,
  ];

  static TextStyle _s(BuildContext context, double size, FontWeight weight, Color? color, {double? height, double? spacing}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color ?? context.colors.ink,
      );

  /// 12 · etiquetas, ayudas pequeñas, títulos de sección en mayúsculas
  static TextStyle caption(BuildContext context, {FontWeight weight = FontWeight.w500, Color? color}) =>
      _s(context, sizeCaption, weight, color ?? context.colors.inkMuted);

  /// 13 · detalle debajo de un título, texto de ayuda
  static TextStyle small(BuildContext context, {FontWeight weight = FontWeight.w400, Color? color}) =>
      _s(context, sizeSmall, weight, color ?? context.colors.inkMuted, height: 1.4);

  /// 14 · texto normal de listas, botones y campos
  static TextStyle body(BuildContext context, {FontWeight weight = FontWeight.w400, Color? color}) =>
      _s(context, sizeBody, weight, color, height: 1.45);

  /// 15 · texto para leer con calma (explicaciones, mensajes)
  static TextStyle bodyLarge(BuildContext context, {FontWeight weight = FontWeight.w400, Color? color}) =>
      _s(context, sizeBodyLarge, weight, color, height: 1.5);

  /// 16 · título de una tarjeta o de una sección
  static TextStyle title(BuildContext context, {FontWeight weight = FontWeight.w700, Color? color}) =>
      _s(context, sizeTitle, weight, color);

  /// 20 · título de una ventana o de una hoja
  static TextStyle heading(BuildContext context, {FontWeight weight = FontWeight.w700, Color? color}) =>
      _s(context, sizeHeading, weight, color, spacing: -0.2);

  /// 26 · título de una pantalla («Hola, Rosa», «Vender»)
  static TextStyle page(BuildContext context, {FontWeight weight = FontWeight.w700, Color? color}) =>
      _s(context, sizePage, weight, color, spacing: -0.5);

  /// 32 · cifra principal de una tarjeta
  static TextStyle display(BuildContext context, {FontWeight weight = FontWeight.w700, Color? color}) =>
      amount(context, size: sizeDisplay, weight: weight, color: color);

  /// 40 · el total grande (Vender, cierre de caja)
  static TextStyle figure(BuildContext context, {FontWeight weight = FontWeight.w700, Color? color}) =>
      amount(context, size: sizeFigure, weight: weight, color: color);

  /// Códigos de barras, números de comprobante y tiquetes
  static TextStyle mono(BuildContext context, {double size = sizeBody, FontWeight weight = FontWeight.w500, Color? color}) =>
      TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: monoFallback,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: 0.6,
        color: color ?? context.colors.ink,
      );

  /// Montos y cantidades: números de ancho fijo para que las cifras queden alineadas
  static TextStyle amount(BuildContext context, {double size = 15, FontWeight weight = FontWeight.w700, Color? color}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: size >= sizeDisplay ? -0.6 : -0.2,
        color: color ?? context.colors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

extension StockealoThemeContext on BuildContext {
  /// true si la app está en modo oscuro. SOLO para lógica (qué ícono mostrar, sol
  /// o luna), NUNCA para elegir colores: los colores ya cambian solos con
  /// `context.colors`. Los candados del re-diseño no cuentan este uso.
  bool get isDarkTheme => Theme.of(this).brightness == Brightness.dark;

  /// Colores del sistema de diseño: `context.colors.accent`, `context.colors.inkMuted`...
  StockealoColors get colors =>
      Theme.of(this).extension<StockealoColors>() ??
      (Theme.of(this).brightness == Brightness.dark ? StockealoColors.dark() : StockealoColors.light());
}
