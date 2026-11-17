import 'package:intl/intl.dart';

class CurrencyFormatter {
  static String currencySymbol = r'$';
  static String currencyCode = 'COP';

  /// Símbolo de cada moneda; las que no están aquí usan "$"
  static const Map<String, String> _symbols = {'EUR': '€', 'PEN': 'S/ '};

  /// Usa la moneda del negocio activo en todos los montos de la app
  static void useCurrency(String? code) {
    currencyCode = code ?? 'COP';
    currencySymbol = _symbols[currencyCode] ?? r'$';
  }

  /// Formatea un valor numérico a moneda con el símbolo al inicio (ej. $2.000)
  static String format(num amount, {bool includeSymbol = true, int decimalDigits = 0}) {
    final pattern = decimalDigits > 0 ? '#,##0.${'0' * decimalDigits}' : '#,##0';
    final numberFormatter = NumberFormat(pattern, 'es_CO');
    // El signo va antes del símbolo: «-$4.500», no «$-4.500» (0.16.4)
    final sign = amount < 0 ? '-' : '';
    final formattedNumber = numberFormatter.format(amount.abs());
    return includeSymbol ? '$sign$currencySymbol$formattedNumber' : '$sign$formattedNumber';
  }

  /// Formatea con una moneda concreta sin cambiar la del negocio activo (vista previa)
  static String formatIn(num amount, String currencyCode) {
    final symbol = _symbols[currencyCode] ?? r'$';
    final sign = amount < 0 ? '-' : '';
    return '$sign$symbol${format(amount.abs(), includeSymbol: false)}';
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
