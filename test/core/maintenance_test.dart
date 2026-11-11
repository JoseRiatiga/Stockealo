import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/admin/admin_team_page.dart';
import 'package:stockealo/core/services/maintenance_service.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/core/widgets/maintenance_gate.dart';
import 'package:stockealo/features/store/data/online_store_service.dart';
import 'package:stockealo/store_web/store_page.dart';

MaintenanceState _m(String state, int level, Set<String> scopes) => MaintenanceState.fromJson({
      'state': state,
      'level': level,
      'scopes': scopes.toList(),
      'message': 'Mejorando la velocidad',
      'starts_at': DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String(),
      'ends_at': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(),
    });

Widget _app(Widget child) => MaterialApp(theme: AppTheme.build(Brightness.light), home: child);

void main() {
  // A propósito SIN initializeDateFormatting: así arrancan el panel y las tiendas
  // si alguien olvida cargarlo, y antes eso dejaba la pantalla en gris
  tearDown(() => MaintenanceService.instance.debugSet(MaintenanceState.none));

  test('la hora se escribe en español sin depender de intl', () {
    final now = DateTime(2026, 11, 8, 10);
    expect(MaintenanceGate.when(DateTime(2026, 11, 8, 16, 5), now: now), 'hoy a las 4:05 p. m.');
    expect(MaintenanceGate.when(DateTime(2026, 11, 12, 0, 30), now: now), '12 de noviembre a las 12:30 a. m.');
    expect(MaintenanceGate.when(DateTime(2026, 11, 8, 12), now: now), 'hoy a las 12:00 p. m.');
    expect(MaintenanceGate.when(null), '');
  });

  group('estado del mantenimiento', () {
    test('cada nivel hace lo suyo', () {
      final aviso = _m('active', 1, {'app', 'stores'});
      expect(aviso.cloudPaused, isFalse);
      expect(aviso.storesClosed, isFalse);

      final pausa = _m('active', 2, {'app', 'stores', 'payments'});
      expect(pausa.cloudPaused, isTrue);
      expect(pausa.appClosed, isFalse);
      expect(pausa.storesClosed, isTrue);
      expect(pausa.paymentsPaused, isTrue);

      final cierre = _m('active', 3, {'app'});
      expect(cierre.appClosed, isTrue);
      expect(cierre.storesClosed, isFalse); // las tiendas no se marcaron

      final programado = _m('notice', 3, {'app'});
      expect(programado.appClosed, isFalse); // todavía no empieza
      expect(MaintenanceState.fromJson(const {'state': 'none'}).active, isFalse);
    });

    test('el administrador no queda bloqueado', () {
      final svc = MaintenanceService.instance;
      svc.debugSet(_m('active', 3, {'app'}));
      expect(svc.appClosed, isTrue);
      expect(svc.cloudPaused, isTrue);
      svc.debugSet(_m('active', 3, {'app'}), admin: true);
      expect(svc.appClosed, isFalse);
      expect(svc.cloudPaused, isFalse);
    });
  });

  group('en la app', () {
    testWidgets('cierre total: pantalla de mantenimiento en vez de la app', (tester) async {
      MaintenanceService.instance.debugSet(_m('active', 3, {'app'}));
      await tester.pumpWidget(_app(const MaintenanceGate(child: Text('Inventario'))));
      expect(find.text('Estamos en mantenimiento'), findsOneWidget);
      expect(find.text('Mejorando la velocidad'), findsOneWidget);
      expect(find.text('Inventario'), findsNothing);
    });

    testWidgets('nube en pausa: la app sigue, con su franja', (tester) async {
      MaintenanceService.instance.debugSet(_m('active', 2, {'app'}));
      await tester.pumpWidget(_app(const MaintenanceGate(child: Text('Inventario'))));
      expect(find.text('Inventario'), findsOneWidget);
      expect(find.textContaining('Puedes seguir vendiendo'), findsOneWidget);
    });

    testWidgets('sin mantenimiento no se ve nada extra', (tester) async {
      await tester.pumpWidget(_app(const MaintenanceGate(child: Text('Inventario'))));
      expect(find.text('Inventario'), findsOneWidget);
      expect(find.byIcon(Icons.construction_outlined), findsNothing);
    });
  });

  group('en la tienda en línea', () {
    const store = PublicStore(
      slug: 'loliando',
      whatsapp: '573001234567',
      businessName: 'Loliando',
      currency: 'COP',
      products: [StoreProduct(id: '1', name: 'Pijama', category: 'Ropa', price: 50000)],
    );

    testWidgets('cerrada: aviso y WhatsApp del negocio', (tester) async {
      await tester.pumpWidget(_app(StorePage(
        slug: 'loliando',
        loader: (_) async => store,
        maintenanceLoader: () async => _m('active', 2, {'stores'}),
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('La tienda está en mantenimiento'), findsOneWidget);
      expect(find.text('Escribir al negocio por WhatsApp'), findsOneWidget);
      expect(find.text('Pijama'), findsNothing);
    });

    testWidgets('mantenimiento solo de la app: la tienda abre normal', (tester) async {
      await tester.pumpWidget(_app(StorePage(
        slug: 'loliando',
        loader: (_) async => store,
        maintenanceLoader: () async => _m('active', 3, {'app'}),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Pijama'), findsOneWidget);
    });
  });

  test('el registro de acciones se lee en español', () {
    expect(
      AdminTeamPageLabels.label({'action': 'grant_pro', 'detail': {'days': 30}}),
      'Dio Pro (30 días) a un negocio',
    );
    expect(
      AdminTeamPageLabels.label({'action': 'set_admin', 'detail': {'email': 'ana@x.com', 'role': 'SUPPORT'}}),
      'Puso a ana@x.com como Soporte',
    );
    expect(AdminTeamPageLabels.label({'action': 'end_maintenance'}), 'Terminó el mantenimiento');
  });
}
