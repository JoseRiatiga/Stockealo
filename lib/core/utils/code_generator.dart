import 'dart:math';

class CodeGenerator {
  /// Genera un código de barras / SKU numérico único de 8 dígitos
  /// Fácilmente escaneable como CODE128 o QR
  static String generateUniqueCode() {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    // Tomar los últimos 4 dígitos de milisegundos + 4 dígitos aleatorios
    final suffix = timestamp.substring(timestamp.length - 4);
    final randomPart = (1000 + random.nextInt(9000)).toString();
    return 'STK-$suffix$randomPart';
  }

  /// Genera un código estrictamente numérico (ej. para compatibilidad EAN/UPC)
  static String generateNumericCode() {
    final random = Random();
    final millis = DateTime.now().millisecondsSinceEpoch % 1000000;
    final rand = random.nextInt(900000) + 100000;
    return '$rand$millis'.substring(0, 12);
  }
}
