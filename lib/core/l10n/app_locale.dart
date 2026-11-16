import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Toda la app en español (0.16.0, fase 5): los calendarios, los selectores de hora y
/// los botones del sistema («Cancelar», «Aceptar», «Pegar») ya no salen en inglés.
abstract final class AppLocale {
  static const locale = Locale('es', 'CO');
  static const supported = [Locale('es', 'CO'), Locale('es')];
  static const delegates = <LocalizationsDelegate<dynamic>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
}
