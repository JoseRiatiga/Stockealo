class CurrencyOption {
  final String code;
  final String label;

  const CurrencyOption(this.code, this.label);
}

/// Opciones de monedas disponibles en Stockealo
const List<CurrencyOption> kAvailableCurrencies = [
  CurrencyOption('COP', 'COP (Pesos colombianos)'),
  CurrencyOption('USD', 'USD (Dólares estadounidenses)'),
  CurrencyOption('MXN', 'MXN (Pesos mexicanos)'),
  CurrencyOption('EUR', 'EUR (Euros)'),
  CurrencyOption('ARS', 'ARS (Pesos argentinos)'),
  CurrencyOption('CLP', 'CLP (Pesos chilenos)'),
  CurrencyOption('PEN', 'PEN (Soles peruanos)'),
  CurrencyOption('OTRA', 'Otra moneda'),
];

/// Obtiene la etiqueta descriptiva para un código de moneda dado
String getCurrencyLabel(String code) {
  final found = kAvailableCurrencies.firstWhere(
    (c) => c.code == code,
    orElse: () => CurrencyOption(code, code),
  );
  return found.label;
}
