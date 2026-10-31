import 'package:flutter/material.dart';
import 'app_tokens.dart';

/// Tema de la app construido con el sistema de diseño V1 (ver app_tokens.dart).
///
/// [accent] es el verde de Stockealo, o el color del negocio si el usuario activó
/// "Usar el color del negocio en la app": cambia el botón principal, la pestaña
/// activa y los detalles de color; fondos y textos no cambian.
class AppTheme {
  AppTheme._();

  // Compatibilidad con pantallas que aún no usan context.colors
  static const Color primaryGreen = AppPalette.brand;
  static const Color alertRed = AppPalette.danger;
  static const Color warningAmber = AppPalette.warning;
  static const Color textMain = AppPalette.ink;
  static const Color textMuted = AppPalette.inkMuted;

  static ThemeData get lightTheme => build(Brightness.light);
  static ThemeData get darkTheme => build(Brightness.dark);

  static ThemeData build(Brightness brightness, {Color accent = AppPalette.brand}) {
    final isDark = brightness == Brightness.dark;
    final c = isDark ? StockealoColors.dark(accent: accent) : StockealoColors.light(accent: accent);

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      onPrimary: c.onAccent,
      secondary: accent,
      onSecondary: c.onAccent,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceTint: Colors.transparent,
      outline: c.lineStrong,
      outlineVariant: c.line,
      error: c.danger,
      onError: Colors.white,
    );

    final baseText = (isDark ? Typography.material2021().white : Typography.material2021().black)
        .apply(fontFamily: AppText.fontFamily, bodyColor: c.ink, displayColor: c.ink);

    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: color, width: width),
        );

    final roundedControl = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control));
    const buttonText = TextStyle(fontFamily: AppText.fontFamily, fontSize: 15, fontWeight: FontWeight.w600);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: AppText.fontFamily,
      textTheme: baseText,
      scaffoldBackgroundColor: c.paper,
      canvasColor: c.paper,
      dividerColor: c.line,
      splashFactory: InkSparkle.splashFactory,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.paper,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: c.ink,
        ),
        iconTheme: IconThemeData(color: c.ink),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: c.line),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 14),
        border: border(c.lineStrong),
        enabledBorder: border(c.line),
        focusedBorder: border(accent, 1.6),
        errorBorder: border(c.danger),
        focusedErrorBorder: border(c.danger, 1.6),
        labelStyle: TextStyle(color: c.inkMuted),
        floatingLabelStyle: TextStyle(color: accent),
        hintStyle: TextStyle(color: c.inkFaint),
        prefixIconColor: c.inkMuted,
        suffixIconColor: c.inkMuted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: c.onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: roundedControl,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: c.onAccent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: roundedControl,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          side: BorderSide(color: c.lineStrong),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: roundedControl,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: roundedControl,
          textStyle: buttonText.copyWith(fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: c.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: accent,
        side: BorderSide(color: c.line),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(fontFamily: AppText.fontFamily, color: c.ink, fontSize: 13),
        secondaryLabelStyle: TextStyle(fontFamily: AppText.fontFamily, color: c.onAccent, fontSize: 13),
        checkmarkColor: c.onAccent,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          side: BorderSide(color: c.line),
        ),
        titleTextStyle: TextStyle(fontFamily: AppText.fontFamily, fontSize: 18, fontWeight: FontWeight.w700, color: c.ink),
        contentTextStyle: TextStyle(fontFamily: AppText.fontFamily, fontSize: 14, height: 1.4, color: c.inkMuted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: c.lineStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.toast,
        contentTextStyle: TextStyle(fontFamily: AppText.fontFamily, color: c.onToast, fontSize: 14),
        actionTextColor: c.onToast,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: accent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? c.onAccent : c.inkMuted),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: AppText.fontFamily,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? c.ink : c.inkMuted,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.onAccent : c.inkFaint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : c.surfaceMuted,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : c.lineStrong,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent, linearTrackColor: c.surfaceMuted),
      listTileTheme: ListTileThemeData(iconColor: c.inkMuted, textColor: c.ink),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.toast, borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(fontFamily: AppText.fontFamily, color: c.onToast, fontSize: 12),
      ),
    );
  }
}
