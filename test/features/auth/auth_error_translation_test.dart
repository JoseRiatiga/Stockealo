import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  String translate(Object e) => AuthRepository.translateAuthError(e);

  group('translateAuthError', () {
    test('credenciales inválidas', () {
      expect(
        translate(const AuthException('Invalid login credentials', code: 'invalid_credentials')),
        'Correo o contraseña incorrectos.',
      );
    });

    test('código OTP expirado', () {
      expect(
        translate(const AuthException('Token has expired or is invalid', code: 'otp_expired')),
        'El código ingresado es incorrecto o ya expiró.',
      );
    });

    test('correo sin confirmar', () {
      expect(
        translate(const AuthException('Email not confirmed', code: 'email_not_confirmed')),
        'Debes confirmar tu correo antes de ingresar.',
      );
    });

    test('límite de envío de correos', () {
      expect(
        translate(const AuthException('For security purposes, you can only request this after 30 seconds.',
            code: 'over_email_send_rate_limit')),
        startsWith('Por seguridad'),
      );
    });

    test('sin conexión', () {
      expect(
        translate(AuthRetryableFetchException(message: 'ClientException: Failed host lookup')),
        startsWith('Necesitas conexión a internet'),
      );
    });

    test('conserva mensajes propios ya traducidos', () {
      expect(
        translate(Exception('Ingresa un correo electrónico válido.')),
        'Ingresa un correo electrónico válido.',
      );
    });

    test('no expone errores desconocidos al usuario', () {
      expect(
        translate(const AuthException('unexpected_failure: stack trace...')),
        'No se pudo completar la operación. Inténtalo de nuevo.',
      );
    });
  });
}
