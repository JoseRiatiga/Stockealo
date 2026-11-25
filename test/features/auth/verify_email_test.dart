import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/core/permissions/permissions.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/presentation/widgets/verify_email_notice.dart';
import 'package:stockealo/features/home/data/app_functions.dart';
import 'package:stockealo/features/team/data/team_repository.dart';

// Registro sin código (0.18.4)
void main() {
  test('la respuesta de register-account se lee bien', () {
    expect(AuthRepository.registerModeOf({'mode': 'created'}), 'created');
    expect(AuthRepository.registerModeOf({'mode': 'code'}), 'code');
    expect(AuthRepository.registerModeOf('raro'), isNull);
    expect(AuthRepository.registerModeOf(null), isNull);
    expect(AuthRepository.registerErrorOf({'error': 'rate_limited'}), 'rate_limited');
    expect(AuthRepository.registerErrorOf('texto'), isNull);
  });

  test('el aviso cerrado en Inicio vuelve a los 7 días', () {
    final now = DateTime(2026, 11, 24, 10);
    expect(EmailVerification.shouldShowOnHome(now: now), isTrue);
    expect(EmailVerification.shouldShowOnHome(now: now, dismissedAt: now.subtract(const Duration(days: 6))), isFalse);
    expect(EmailVerification.shouldShowOnHome(now: now, dismissedAt: now.subtract(const Duration(days: 7))), isTrue);
  });

  test('«Verificar correo» está en el buscador y vive en Ajustes', () {
    final f = findFunctions('verificar correo', role: Permissions.owner, services: false).first;
    expect(f.id, 'verify_email');
    expect(f.tab, 3);
  });

  test('el mensaje de invitación sin verificar dice qué hacer', () {
    expect(TeamRepository.unverifiedInviteMessage, contains('verificar su correo'));
    expect(TeamRepository.unverifiedInviteMessage, contains('Verificar'));
  });

  group('aviso «Verifica tu correo»', () {
    tearDown(() => AuthRepository.emailVerified.value = null);

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: const Scaffold(body: VerifyEmailNotice()),
        ));

    testWidgets('sale solo si la nube dice que falta verificar', (tester) async {
      AuthRepository.emailVerified.value = false;
      await pump(tester);
      await tester.pump();
      expect(find.text('Verifica tu correo para proteger tu cuenta'), findsOneWidget);
      // En Ajustes no se puede cerrar
      expect(find.text('Ahora no'), findsNothing);

      AuthRepository.emailVerified.value = true;
      await tester.pump();
      expect(find.text('Verifica tu correo para proteger tu cuenta'), findsNothing);
    });

    testWidgets('sin saber (sin conexión) no se muestra', (tester) async {
      await pump(tester);
      await tester.pump();
      expect(find.text('Verifica tu correo para proteger tu cuenta'), findsNothing);
    });
  });
}
