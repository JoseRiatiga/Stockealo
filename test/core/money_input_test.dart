import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/utils/money_input.dart';

TextEditingValue _type(String text, [int? cursor]) {
  var v = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: cursor ?? text.length));
  for (final f in MoneyInput.formatters) {
    v = f.formatEditUpdate(TextEditingValue.empty, v);
  }
  return v;
}

void main() {
  test('puntos de mil mientras se escribe (#20)', () {
    expect(_type('999999').text, '999.999');
    expect(_type('1000000').text, '1.000.000');
    expect(_type('12').text, '12');
    expect(_type('').text, '');
    expect(_type('abc').text, '');
  });

  test('el cursor se queda junto a las mismas cifras', () {
    // «1.000|00» → al borrar puntos y volver a ponerlos, el cursor sigue antes de «00»
    final v = _type('1.00000', 5);
    expect(v.text, '100.000');
    expect(v.selection.baseOffset, 5);
  });

  test('leer y escribir valores', () {
    expect(MoneyInput.parse('100.000'), 100000);
    expect(MoneyInput.parse('\$ 2.500'), 2500);
    expect(MoneyInput.parse(''), 0);
    expect(MoneyInput.text(100000), '100.000');
    expect(MoneyInput.text(1234.6), '1.235');
    expect(MoneyInput.text(0), '');
  });
}
