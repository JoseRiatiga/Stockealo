import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/core/theme/app_tokens.dart';
import 'package:stockealo/core/widgets/app_toast.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/business/data/transfer_repository.dart';
import 'package:stockealo/features/team/data/person_names.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Arreglos cortos (0.18.6)
void main() {
  test('en computador el aviso mide como máximo 420 px y va centrado; en el celular, a lo ancho', () {
    final phone = AppToast.marginFor(390);
    expect(phone.left, AppSpace.lg);
    expect(phone.right, AppSpace.lg);

    final desktop = AppToast.marginFor(1440);
    expect(1440 - desktop.left - desktop.right, AppToast.maxWidth);
    expect(desktop.left, desktop.right);

    // Justo en el borde: nunca más angosto que el margen de siempre
    final tablet = AppToast.marginFor(600);
    expect(tablet.left, greaterThanOrEqualTo(AppSpace.lg));
  });

  test('una unidad y varias unidades', () {
    expect(unitsText(1), '1 unidad');
    expect(unitsText(0), '0 unidades');
    expect(unitsText(3), '3 unidades');
  });

  test('en la caja se muestra el nombre, no el correo', () {
    PersonNames.debugNames = {'dueno@correo.com': 'Jose Riatiga'};
    addTearDown(() => PersonNames.debugNames = const {});
    expect(PersonNames.display('Dueno@Correo.com'), 'Jose Riatiga');
    // Ya no está en el equipo: la parte antes de la @
    expect(PersonNames.display('ana.perez@correo.com'), 'ana.perez');
    // Lo nuevo ya guarda el nombre
    expect(PersonNames.display('Luis'), 'Luis');
    expect(PersonNames.display(null), '');
  });

  test('solo se avisa cuando la nube cierra la sesión de alguien que sigue adentro', () {
    expect(AuthRepository.sessionClosedByCloud(AuthChangeEvent.signedOut, appLoggedIn: true), isTrue);
    // Tocó «Salir»: la app ya no tenía usuario
    expect(AuthRepository.sessionClosedByCloud(AuthChangeEvent.signedOut, appLoggedIn: false), isFalse);
    expect(AuthRepository.sessionClosedByCloud(AuthChangeEvent.tokenRefreshed, appLoggedIn: true), isFalse);
    // Borrar la cuenta cierra la sesión a propósito: sin aviso (Codex, 25 nov)
    SupabaseService.intentionalSignOut = true;
    addTearDown(() => SupabaseService.intentionalSignOut = false);
    expect(AuthRepository.sessionClosedByCloud(AuthChangeEvent.signedOut, appLoggedIn: true), isFalse);
  });
}
