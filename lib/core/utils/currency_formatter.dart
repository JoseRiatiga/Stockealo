import 'package:intl/intl.dart';

class CurrencyFormatter {
  static String currencySymbol = r'$';
  static String currencyCode = 'COP';

  /// Formatea un valor numérico a moneda con el símbolo al inicio (ej. $2.000)
  static String format(num amount, {bool includeSymbol = true, int decimalDigits = 0}) {
    final pattern = decimalDigits > 0 ? '#,##0.${'0' * decimalDigits}' : '#,##0';
    final numberFormatter = NumberFormat(pattern, 'es_CO');
    final formattedNumber = numberFormatter.format(amount);
    return includeSymbol ? '$currencySymbol$formattedNumber' : formattedNumber;
  }

  /// Alias de formato
  static String formatCOP(num amount) => format(amount);

  /// Convierte texto de input numérico a valor limpio
  static double parse(String text) {
    if (text.isEmpty) return 0.0;
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }
}
