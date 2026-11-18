import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Campos de dinero con puntos de mil mientras se escribe («999.999»), 0.16.8 (#20).
/// Un solo lugar: los campos usan [formatters], leen con [parse] y llenan con [text].
abstract final class MoneyInput {
  static final _format = NumberFormat.decimalPattern('es_CO');

  /// Solo números enteros, con puntos de mil
  static final formatters = <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly, ThousandsFormatter()];

  /// «100.000» → 100000; vacío → 0. Ignora puntos, comas y el signo $
  static double parse(String text) => double.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  /// 100000 → «100.000»; 0 o menos → vacío
  static String text(num value) => value <= 0 ? '' : _format.format(value.round());
}

/// Pone los puntos de mil y deja el cursor donde estaba respecto a las cifras
class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final text = MoneyInput._format.format(int.parse(digits));
    // Cuántas cifras quedan a la derecha del cursor: se conservan al poner los puntos
    final cursor = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsAfter = newValue.text.substring(cursor).replaceAll(RegExp(r'[^0-9]'), '').length;
    var offset = text.length, seen = 0;
    while (offset > 0 && seen < digitsAfter) {
      offset--;
      if (text[offset] != '.') seen++;
    }
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset));
  }
}
