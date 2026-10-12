import 'package:intl/intl.dart';

class CurrencyFormatter {
  static String currencySymbol = r'$';
  static String currencyCode = 'COP';

  /// Formatea un valor numérico a moneda (por defecto pesos colombianos sin decimales: $ 50.000)
  static String format(num amount, {bool includeSymbol = true, int decimalDigits = 0}) {
    final formatter = NumberFormat.currency(
      locale: 'es_CO',
      symbol: includeSymbol ? '$currencySymbol ' : '',
      decimalDigits: decimalDigits,
    );
    return formatter.format(amount);
  }

  /// Convierte texto de input numérico a valor limpio
  static double parse(String text) {
    if (text.isEmpty) return 0.0;
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }
}
