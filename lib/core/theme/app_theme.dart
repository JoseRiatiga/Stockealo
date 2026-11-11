import 'package:flutter/material.dart';
import 'app_tokens.dart';

/// Tema de la app con el sistema de diseño del re-diseño 0.13.0 (ver app_tokens.dart).
///
/// [accent] es el color del negocio (o el verde de Stockealo): cambia el botón
/// principal, la opción activa y los detalles de color. Fondos y textos no cambian.
/// Los widgets de Material sin estilo propio toman de aquí la escala de letra, las
/// esquinas y los colores, así que se ven como el diseño aprobado sin código extra.
class AppTheme {
  AppTheme._();

  // Compatibilidad con pantallas que aún no usan context.colors (se quitan en el re-diseño)
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
    final a = c.accent; // ya ajustado para que el texto blanco se lea

    final scheme = ColorScheme.fromSeed(
      seedColor: a,
      brightness: brightness,
    ).copyWith(
      primary: a,
      onPrimary: c.onAccent,
      secondary: a,
      onSecondary: c.onAccent,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceMuted,
      surfaceContainerHighest: c.surfaceMuted,
      outline: c.lineStrong,
      outlineVariant: c.line,
      error: c.danger,
      onError: Colors.white,
    );

    TextStyle t(double size, FontWeight weight, Color color, {double? height, double? spacing}) => TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: spacing,
          color: color,
        );

    // La escala de Material apuntando a la escala de Stockealo
    final textTheme = TextTheme(
      displayLarge: t(AppText.sizeFigure, FontWeight.w700, c.ink, spacing: -0.6),
      displayMedium: t(AppText.sizeDisplay, FontWeight.w700, c.ink, spacing: -0.6),
      displaySmall: t(AppText.sizeDisplay, FontWeight.w700, c.ink, spacing: -0.6),
      headlineLarge: t(AppText.sizeDisplay, FontWeight.w700, c.ink, spacing: -0.5),
      headlineMedium: t(AppText.sizePage, FontWeight.w700, c.ink, spacing: -0.5),
      headlineSmall: t(AppText.sizePage, FontWeight.w700, c.ink, spacing: -0.5),
      titleLarge: t(AppText.sizeHeading, FontWeight.w700, c.ink, spacing: -0.2),
      titleMedium: t(AppText.sizeTitle, FontWeight.w600, c.ink),
      titleSmall: t(AppText.sizeBody, FontWeight.w600, c.ink),
      bodyLarge: t(AppText.sizeBodyLarge, FontWeight.w400, c.ink, height: 1.5),
      bodyMedium: t(AppText.sizeBody, FontWeight.w400, c.ink, height: 1.45),
      bodySmall: t(AppText.sizeCaption, FontWeight.w400, c.inkMuted, height: 1.4),
      labelLarge: t(AppText.sizeBody, FontWeight.w600, c.ink),
      labelMedium: t(AppText.sizeSmall, FontWeight.w500, c.inkMuted),
      labelSmall: t(AppText.sizeCaption, FontWeight.w500, c.inkMuted),
    );

    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: color, width: width),
        );

    final roundedControl = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control));
    final buttonText = t(AppText.sizeBody, FontWeight.w600, c.ink);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 12);
    const buttonMin = Size(44, 44);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: AppText.fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: c.paper,
      canvasColor: c.paper,
      dividerColor: c.line,
      splashFactory: InkSparkle.splashFactory,
      extensions: [c],
      iconTheme: IconThemeData(color: c.ink, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: c.line)),
        titleTextStyle: t(AppText.sizeHeading, FontWeight.w700, c.ink, spacing: -0.2),
        iconTheme: IconThemeData(color: c.ink, size: 20),
      ),
      cardTheme: CardThemeData(
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
        enabledBorder: border(c.lineStrong),
        focusedBorder: border(a, 2),
        errorBorder: border(c.danger),
        focusedErrorBorder: border(c.danger, 2),
        labelStyle: t(AppText.sizeBody, FontWeight.w500, c.inkMuted),
        floatingLabelStyle: t(AppText.sizeBody, FontWeight.w600, a),
        hintStyle: t(AppText.sizeBody, FontWeight.w400, c.inkFaint),
        helperStyle: t(AppText.sizeCaption, FontWeight.w400, c.inkMuted),
        errorStyle: t(AppText.sizeCaption, FontWeight.w500, c.danger),
        prefixIconColor: c.inkMuted,
        suffixIconColor: c.inkMuted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: a,
          foregroundColor: c.onAccent,
          elevation: 0,
          minimumSize: buttonMin,
          padding: buttonPadding,
          shape: roundedControl,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: a,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.surfaceMuted,
          disabledForegroundColor: c.inkFaint,
          minimumSize: buttonMin,
          padding: buttonPadding,
          shape: roundedControl,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          backgroundColor: c.surface,
          side: BorderSide(color: c.lineStrong),
          minimumSize: buttonMin,
          padding: buttonPadding,
          shape: roundedControl,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: a,
          minimumSize: buttonMin,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          shape: roundedControl,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.ink,
          minimumSize: buttonMin,
          shape: roundedControl,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: a,
        foregroundColor: c.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      ),
      // Chips: la opción elegida va en negro (en oscuro, en blanco), como las categorías del diseño
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.ink,
        disabledColor: c.surfaceMuted,
        side: BorderSide(color: c.line),
        shape: const StadiumBorder(),
        showCheckmark: false,
        labelStyle: t(AppText.sizeSmall, FontWeight.w600, c.ink),
        secondaryLabelStyle: t(AppText.sizeSmall, FontWeight.w600, c.surface),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: c.surface,
          foregroundColor: c.inkMuted,
          selectedBackgroundColor: c.surfaceMuted,
          selectedForegroundColor: c.ink,
          side: BorderSide(color: c.line),
          textStyle: t(AppText.sizeSmall, FontWeight.w600, c.ink),
        ),
      ),
      // Menús ⋮: tarjeta blanca con borde fino y sin sombra
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: c.lineStrong),
        ),
        textStyle: t(AppText.sizeBody, FontWeight.w400, c.ink),
        labelTextStyle: WidgetStatePropertyAll(t(AppText.sizeBody, FontWeight.w400, c.ink)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            side: BorderSide(color: c.lineStrong),
          )),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: t(AppText.sizeBody, FontWeight.w400, c.ink),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            side: BorderSide(color: c.lineStrong),
          )),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          side: BorderSide(color: c.line),
        ),
        titleTextStyle: t(AppText.sizeHeading, FontWeight.w700, c.ink, spacing: -0.2),
        contentTextStyle: t(AppText.sizeBody, FontWeight.w400, c.inkMuted, height: 1.5),
      ),
      // Reloj para elegir la hora: tarjeta, relleno y el color del negocio
      timePickerTheme: TimePickerThemeData(
        backgroundColor: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          side: BorderSide(color: c.line),
        ),
        helpTextStyle: t(AppText.sizeBodyLarge, FontWeight.w700, c.ink),
        hourMinuteShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        hourMinuteColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Color.alphaBlend(a.withValues(alpha: 0.14), c.surface) : c.surfaceMuted,
        ),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected) ? a : c.ink,
        ),
        hourMinuteTextStyle: t(AppText.sizeClock, FontWeight.w600, c.ink),
        dayPeriodShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        dayPeriodBorderSide: BorderSide(color: c.lineStrong),
        dayPeriodColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected) ? a : c.surface,
        ),
        dayPeriodTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.onAccent : c.inkMuted,
        ),
        dayPeriodTextStyle: t(AppText.sizeBody, FontWeight.w600, c.ink),
        dialBackgroundColor: c.surfaceMuted,
        dialHandColor: a,
        dialTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.onAccent : c.ink,
        ),
        dialTextStyle: t(AppText.sizeBodyLarge, FontWeight.w500, c.ink),
        entryModeIconColor: c.inkMuted,
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: c.inkMuted),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: a,
          textStyle: t(AppText.sizeBody, FontWeight.w700, a),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: c.surfaceMuted,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            borderSide: BorderSide(color: a, width: 2),
          ),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          side: BorderSide(color: c.line),
        ),
        headerBackgroundColor: c.surface,
        headerForegroundColor: c.ink,
        todayBorder: BorderSide(color: a),
      ),
      // Hojas que suben: una sola forma, con su asa (las pantallas no dibujan la suya)
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: c.lineStrong,
        dragHandleSize: const Size(40, 5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.toast,
        contentTextStyle: t(AppText.sizeBody, FontWeight.w500, c.onToast),
        actionTextColor: c.onToast,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: a,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? c.onAccent : c.inkMuted),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => t(
            AppText.sizeCaption,
            states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            states.contains(WidgetState.selected) ? c.ink : c.inkMuted,
          ),
        ),
      ),
      // Interruptor como el del diseño: círculo blanco, riel del color del negocio
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? a : c.lineStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbIcon: const WidgetStatePropertyAll(null),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? a : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(c.onAccent),
        side: BorderSide(color: c.lineStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? a : c.lineStrong,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: a, linearTrackColor: c.surfaceMuted),
      listTileTheme: ListTileThemeData(
        iconColor: c.inkMuted,
        textColor: c.ink,
        titleTextStyle: t(AppText.sizeBody, FontWeight.w600, c.ink),
        subtitleTextStyle: t(AppText.sizeSmall, FontWeight.w400, c.inkMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.toast, borderRadius: BorderRadius.circular(AppRadius.small)),
        textStyle: t(AppText.sizeCaption, FontWeight.w500, c.onToast),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: c.danger,
        textColor: Colors.white,
        textStyle: t(AppText.sizeCaption, FontWeight.w700, Colors.white),
      ),
    );
  }
}
