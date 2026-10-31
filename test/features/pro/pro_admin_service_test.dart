import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/pro/data/pro_admin_service.dart';

void main() {
  test('los códigos se leen de la fila del servidor', () {
    final code = ProCode.fromRow({
      'code': 'STK-ABCD-EFGH',
      'kind': 'global',
      'days': 30,
      'max_uses': 2,
      'uses': 2,
      'note': 'Prueba',
      'created_at': '2026-10-31T10:00:00Z',
      'redeemed_by': 'ana@correo.com, luis@correo.com',
    });
    expect(code.kindLabel, 'Pro Global');
    expect(code.durationLabel, '1 mes');
    expect(code.exhausted, isTrue);
    expect(code.redeemedBy, contains('ana@correo.com'));
  });

  test('un código sin días es permanente y sin usos no está agotado', () {
    final code = ProCode.fromRow({
      'code': 'STK-ABCD-EFGH',
      'kind': 'business',
      'days': null,
      'max_uses': 1,
      'uses': 0,
      'note': null,
      'created_at': '2026-10-31T10:00:00Z',
    });
    expect(code.kindLabel, 'Pro Negocio');
    expect(code.durationLabel, 'Permanente');
    expect(code.exhausted, isFalse);
  });

  test('cada error del servidor tiene su mensaje', () {
    expect(ProAdminService.errorMessage('admin_only'), contains('no es administradora'));
    expect(ProAdminService.errorMessage('invalid_count'), contains('1 a 50'));
    expect(ProAdminService.errorMessage('invalid_days'), contains('días'));
    expect(ProAdminService.errorMessage('otra cosa'), contains('Inténtalo de nuevo'));
  });
}
