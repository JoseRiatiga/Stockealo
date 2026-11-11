/// Revisa un código de barras de producto: reconoce el formato y comprueba el
/// último número (dígito de control) de EAN-13, EAN-8 y UPC-A, como en el diseño
/// aprobado («la suma da 52, para llegar a 60 faltan 8 y el código termina en 8»).
/// Los demás códigos (internos, Code 128, QR) se aceptan tal cual.
class BarcodeCheck {
  /// «EAN-13», «EAN-8», «UPC-A» o «Código propio»
  final String format;
  final String code;

  /// Peso de cada número (1 o 3) en los formatos que se comprueban
  final List<int> weights;

  /// Suma de los números por su peso (sin el último)
  final int sum;

  /// El último número que debería tener; null si el formato no se comprueba
  final int? expected;

  const BarcodeCheck._(this.format, this.code, this.weights, this.sum, this.expected);

  /// Se comprueba el último número (EAN o UPC)
  bool get checked => expected != null;

  /// Cuadra (o es un formato que no se comprueba)
  bool get valid => expected == null || int.parse(code[code.length - 1]) == expected;

  int get last => int.parse(code[code.length - 1]);

  /// El mismo código con el último número corregido
  String? get fixed => expected == null || valid ? null : '${code.substring(0, code.length - 1)}$expected';

  /// La cuenta en palabras
  String get explanation {
    if (!checked) return 'Este código no lleva número de control: se guarda tal cual.';
    final next = ((sum + 9) ~/ 10) * 10;
    final base = 'Revisamos el último número: la suma da $sum, para llegar a $next faltan $expected';
    return valid
        ? '$base y el código termina en $last. Cuadra.'
        : '$base, pero el código termina en $last. No cuadra: el último número debería ser $expected.';
  }

  static final _digits = RegExp(r'^\d+$');

  factory BarcodeCheck.of(String raw) {
    final code = raw.trim();
    final numeric = _digits.hasMatch(code);
    if (!numeric || !const {8, 12, 13}.contains(code.length)) {
      return BarcodeCheck._('Código propio', code, const [], 0, null);
    }
    // EAN-13: pesos 1,3,1,3… desde la izquierda. EAN-8 y UPC-A: 3,1,3,1…
    final firstWeight = code.length == 13 ? 1 : 3;
    final weights = [for (var i = 0; i < code.length - 1; i++) i.isEven ? firstWeight : (firstWeight == 1 ? 3 : 1)];
    var sum = 0;
    for (var i = 0; i < weights.length; i++) {
      sum += int.parse(code[i]) * weights[i];
    }
    final expected = (10 - sum % 10) % 10;
    final format = switch (code.length) { 13 => 'EAN-13', 8 => 'EAN-8', _ => 'UPC-A' };
    return BarcodeCheck._(format, code, weights, sum, expected);
  }
}
