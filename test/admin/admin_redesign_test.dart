import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/admin/admin_widgets.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/pro/data/pro_service.dart';

/// Re-diseño del panel (24 nov): textos legibles, pagos sin terminar y pantallas vacías
void main() {
  final now = DateTime(2026, 11, 24, 15);

  test('un pago pendiente de más de 24 horas dice «Sin terminar»', () {
    expect(adminPaymentState('PENDING', now.subtract(const Duration(hours: 2)), now: now).label, 'Pendiente');
    expect(adminPaymentState('PENDING', now.subtract(const Duration(days: 15)), now: now).label, 'Sin terminar');
    expect(adminPaymentState('APPROVED', now, now: now).tone, AdminTone.good);
    expect(adminPaymentState('DECLINED', now, now: now).label, 'Rechazado');
  });

  test('los planes se leen como en la app', () {
    expect(proPlanIdLabel('business_month_cop'), 'Pro · Mensual');
    expect(proPlanIdLabel('services_year_cop'), 'Pro Servicios · Anual');
    expect(proPlanName('business', 'week'), 'Pro · Semanal');
  });

  test('fechas del panel: hoy, ayer y el día con su nombre', () {
    expect(adminWhen(DateTime(2026, 11, 24, 9, 5), now: now), startsWith('hoy 9:05'));
    expect(adminWhen(DateTime(2026, 11, 23, 21), now: now), startsWith('ayer 9:00'));
    expect(adminWhen(DateTime(2026, 11, 1), now: now), '01/11/2026');
    expect(adminDayTitle(DateTime(2026, 11, 24), now: now), 'Hoy');
    expect(adminDayTitle(DateTime(2026, 11, 20), now: now), 'viernes 20 de noviembre');
    expect(adminInitials('Jose Riatiga', 'x@y.com'), 'JR');
    expect(adminInitials(null, 'ana@x.com'), 'A');
  });

  testWidgets('la pantalla vacía trae ícono, título y explicación', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(
        body: AdminLoadState(
          loading: false,
          error: null,
          empty: true,
          emptyText: 'Sin errores en estos días',
          emptyDetail: 'Si algo falla, aparece aquí.',
          emptyIcon: Icons.check_circle_outline,
        ),
      ),
    ));
    expect(find.text('Sin errores en estos días'), findsOneWidget);
    expect(find.text('Si algo falla, aparece aquí.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });
}
