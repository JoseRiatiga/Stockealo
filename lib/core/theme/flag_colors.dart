import 'package:flutter/material.dart';

/// Colores oficiales (aproximados) de las banderas de los países de la app.
/// Las banderas se dibujan con [CountryFlag]: los emojis de bandera no se ven en
/// Windows ni en la web (salen como "CO", "MX").
class FlagColors {
  FlagColors._();

  static const white = Color(0xFFFFFFFF);
  static const colombiaYellow = Color(0xFFFCD116);
  static const colombiaBlue = Color(0xFF003893);
  static const colombiaRed = Color(0xFFCE1126);
  static const mexicoGreen = Color(0xFF006847);
  static const mexicoRed = Color(0xFFCE1126);
  static const mexicoEagle = Color(0xFF8C6A2F);
  static const peruRed = Color(0xFFD91023);
  static const argentinaBlue = Color(0xFF74ACDF);
  static const argentinaSun = Color(0xFFF6B40E);
  static const chileBlue = Color(0xFF0039A6);
  static const chileRed = Color(0xFFD52B1E);
  static const usaRed = Color(0xFFB22234);
  static const usaBlue = Color(0xFF3C3B6E);
  static const spainRed = Color(0xFFAA151B);
  static const spainYellow = Color(0xFFF1BF00);
  static const border = Color(0x33000000);
}
