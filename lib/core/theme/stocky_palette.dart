import 'package:flutter/painting.dart';

/// Colores de Stocky, la ardilla tendera. Son los mismos en claro y en oscuro:
/// es un personaje, no parte de la interfaz.
abstract final class StockyPalette {
  static const furDark = Color(0xFFB86B35);
  static const fur = Color(0xFFD28A4E);
  static const body = Color(0xFFC9783E);
  static const muzzle = Color(0xFFF3D9B8);
  static const ink = Color(0xFF241F1B);
  static const blush = Color(0xFFE8836F);
  static const mouth = Color(0xFF4A2A20);

  // Delantal verde Stockealo con el logo estampado en un color
  static const apron = Color(0xFF1E6B4E);
  static const printLight = Color(0xFFCFEBDD);
  static const printShade = Color(0xFFA9D9C2);

  static const sparkleGold = Color(0xFFE0B44A);
  static const sparkleGreen = Color(0xFF2E8A66);
  static const thought = Color(0xFFD9C9B3);
  static const sweat = Color(0xFF8EC5E8);

  /// Fondo suave del círculo donde se muestra la cara (botón, chat)
  static const halo = Color(0xFFF6EBDD);
}
