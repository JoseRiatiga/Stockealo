import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/design/status_pill.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/auth/presentation/logout_confirm.dart';
import 'package:stockealo/features/team/data/activity_line.dart';
import 'package:stockealo/features/team/data/activity_repository.dart';

/// 0.16.1: la actividad del equipo se lee clara en Inicio, y cerrar sesión pregunta
void main() {
  ActivityEntry entry(String action, String summary, {Map<String, dynamic>? data}) => ActivityEntry(
        id: 'a',
        businessId: 'b',
        actorEmail: 'jose@x.co',
        actorName: 'Jose Riatiga',
        action: action,
        summary: summary,
        createdAt: DateTime(2026, 11, 14, 20, 34),
        data: data,
      );

  test('un ajuste de muchas variantes queda corto, con lo que cambió y la etiqueta', () {
    final l = ActivityLine.of(entry(
      ActivityAction.stockAdjust,
      'Ajustó test: M · Negro: 1 → 5, S · Azul: 0 → 5, M · Fucsia: 0 → 5, S · Amarillo: 0 → 5, S · Verde: 0 → 5, '
      'M · Azul oscuro: 0 → 5 (queda 30) · Nuevo lote',
      data: {'diff': 29},
    ));
    expect(l.title, 'Ajustó el stock de test');
    expect(l.detail, 'M · Negro: 1 → 5, S · Azul: 0 → 5 y 4 más · queda 30');
    expect(l.value, '+29');
    expect(l.valueUp, isTrue);
    expect(l.tag, 'Nuevo lote');
    expect(l.tone, AppTone.info);
  });

  test('una venta: el valor a la derecha y la variante y el pago en el detalle', () {
    final l = ActivityLine.of(entry(ActivityAction.sale, 'Vendió 1 × test (S · Verde) por \$25.000 (mixto)'));
    expect(l.title, 'Vendió 1 × test');
    expect(l.value, '\$25.000');
    expect(l.detail, 'S · Verde · Mixto');
    expect(l.tone, AppTone.success);
  });

  test('un producto nuevo y un texto sin forma conocida', () {
    final l = ActivityLine.of(entry(ActivityAction.productCreate, 'Creó test2: \$2.000, 10 en stock'));
    expect(l.title, 'Creó test2');
    expect(l.value, '\$2.000');
    expect(l.detail, '10 en stock');
    final other = ActivityLine.of(entry(ActivityAction.memberJoin, 'Se unió al equipo como Cajero'));
    expect(other.title, 'Se unió al equipo como Cajero');
    expect(other.detail, isNull);
    expect(other.value, isNull);
    expect(ActivityLine.of(entry(ActivityAction.sale, '   ')).title, 'Movimiento del equipo');
  });

  test('una baja muestra cuánto bajó', () {
    final l = ActivityLine.of(entry(ActivityAction.shrinkage, 'Ajustó arroz: 10 → 7 (queda 7) · Se dañó', data: {'diff': -3}));
    expect(l.value, '−3');
    expect(l.valueUp, isFalse);
    expect(l.tag, 'Se dañó');
    expect(l.detail, '10 → 7 · queda 7');
  });

  test('el aviso de cerrar sesión dice si hay cambios sin subir', () {
    expect(LogoutConfirm.message(0), contains('correo y tu contraseña'));
    expect(LogoutConfirm.message(1), contains('1 cambio sin subir'));
    expect(LogoutConfirm.message(3), contains('3 cambios sin subir'));
  });

  testWidgets('cerrar sesión pregunta antes y se puede cancelar', (tester) async {
    bool? answer;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => answer = await LogoutConfirm.ask(context, pending: () async => 2),
            child: const Text('salir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('salir'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cerrar sesión?'), findsOneWidget);
    expect(find.textContaining('2 cambios sin subir'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
    await tester.tap(find.text('salir'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });
}
