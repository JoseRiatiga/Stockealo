import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Utilidad para hash unidireccional seguro de contraseñas con salting
class HashHelper {
  // Salteado criptográfico para mitigar ataques por tablas arcoíris
  static const String _pepper = 'stockealo_sec_pepper_v1_#92@!';

  /// Genera un hash SHA-256 seguro con salting
  static String hashPassword(String password) {
    final saltedPassword = '$password:$_pepper';
    final bytes = utf8.encode(saltedPassword);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verifica si una contraseña ingresada coincide con el hash almacenado.
  /// Incluye compatibilidad con registros antiguos en texto plano para auto-migración.
  static bool verifyPassword(String inputPassword, String storedPasswordOrHash) {
    final computedHash = hashPassword(inputPassword);
    if (computedHash == storedPasswordOrHash) {
      return true;
    }
    // Soporte retrocompatible si la contraseña previa estaba sin cifrar
    if (inputPassword == storedPasswordOrHash) {
      return true;
    }
    return false;
  }
}
