import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/team/data/authorization_service.dart';
import 'package:stockealo/features/team/presentation/widgets/authorization_gate.dart';

/// 0.15.0, etapa 3: autorización de un solo uso, solo con internet
void main() {
  testWidgets('sin conexión, pedir autorización lo dice y la acción no sigue', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await AuthorizationGate.allow(
              context,
              businessId: 'b1',
              action: 'Venta de \$50.000',
              reasons: const ['El descuento es de 25 % y tu límite es 10 %.'],
              amount: 50000,
            ),
            child: const Text('Cobrar'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Cobrar'));
    await tester.pumpAndSettle();
    expect(find.text('Necesitas autorización'), findsOneWidget);
    expect(find.textContaining('tu límite es 10 %'), findsOneWidget);

    await tester.tap(find.text('Pedir autorización'));
    await tester.pumpAndSettle();
    expect(find.textContaining('necesitas internet'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('la solicitud se lee de la nube y sabe cuándo venció', () {
    final r = AuthRequest.fromJson({
      'id': 'x',
      'business_id': 'b1',
      'number': 4821,
      'action': 'Salida de caja',
      'amount': 80000,
      'requested_by': 'u2',
      'requested_name': 'Luis',
      'status': 'APROBADA',
      'decided_name': 'Ana',
      'created_at': '2026-11-14T15:00:00Z',
      'expires_at': '2026-11-14T15:05:00Z',
    });
    expect(r.number, 4821);
    expect(r.status, AuthRequest.approved);
    expect(r.expired(DateTime.utc(2026, 11, 14, 15, 4)), isFalse);
    expect(r.expired(DateTime.utc(2026, 11, 14, 15, 6)), isTrue);
  });
}
