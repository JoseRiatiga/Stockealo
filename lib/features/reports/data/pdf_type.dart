/// Tamaños de letra de los PDF (catálogo, cartel del QR), en puntos de papel. Son la
/// escala del papel, distinta de la de la pantalla ([AppText]) (0.16.0).
abstract final class PdfPt {
  static const tiny = 6.5;
  static const micro = 7.0;
  static const footnote = 7.5;
  static const caption = 8.0;
  static const note = 8.5;
  static const small = 9.0;
  static const label = 10.0;
  static const body = 11.0;
  static const item = 12.0;
  static const subtitle = 16.0;
  static const title = 22.0;
}
