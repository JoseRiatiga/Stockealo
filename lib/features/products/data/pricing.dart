/// Precio sugerido por margen (0.15.0): el precio de venta para ganar un porcentaje sobre
/// lo que se cobra (el mismo margen que muestra el formulario: ganancia / precio).
abstract final class Pricing {
  /// Márgenes que se ofrecen con un toque
  static const margins = [20, 30, 40, 50];

  /// Precio para ganar [marginPct] % del precio de venta, redondeado hacia arriba a
  /// [roundTo] (100 en pesos, para que quede un precio «redondo»)
  static double priceForMargin(double cost, num marginPct, {int roundTo = 100}) {
    if (cost <= 0 || marginPct <= 0 || marginPct >= 100) return cost;
    final raw = cost / (1 - marginPct / 100);
    if (roundTo <= 1) return raw;
    return (raw / roundTo).ceil() * roundTo.toDouble();
  }
}
