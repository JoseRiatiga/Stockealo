import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/admin/admin_businesses_page.dart';
import 'package:stockealo/admin/admin_payments_page.dart';
import 'package:stockealo/admin/admin_team_page.dart';
import 'package:stockealo/admin/admin_user_detail.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/pro/data/pro_admin_service.dart';

/// Re-diseño del panel (24 nov): la ficha, el registro, Pagos y Negocios se dibujan sin
/// desbordes con datos de ejemplo. Con PREVIEW_OUT guarda las imágenes para revisarlas.
void main() {
  final now = DateTime.now();
  String iso(DateTime d) => d.toUtc().toIso8601String();

  Future<dynamic> fake(String fn, Map<String, dynamic>? params) async => switch (fn) {
        'admin_user_detail' => {
            'account': {
              'email': 'jose@ejemplo.com',
              'name': 'Jose Riatiga',
              'phone': '+573001234567',
              'created_at': iso(DateTime(2026, 10, 16)),
              'last_sign_in_at': iso(now.subtract(const Duration(hours: 1))),
              'email_confirmed_at': iso(DateTime(2026, 10, 16)),
              'provider': 'email',
            },
            'businesses': [
              {
                'id': 'b1',
                'name': 'LAVADERO',
                'role': 'OWNER',
                'country': 'CO',
                'pro': {'active': true, 'kind': 'services', 'ends_at': iso(now.add(const Duration(days: 17)))},
              },
              {
                'id': 'b2',
                'name': 'Miselanea',
                'role': 'CASHIER',
                'country': 'CO',
                'pro': {'active': true, 'kind': 'business', 'ends_at': iso(now.add(const Duration(days: 364)))},
                'store_slug': 'miselanea',
                'store_enabled': true,
              },
            ],
            'redemptions': [
              {'code': 'STK-ABCD-1234', 'business': 'Miselanea', 'redeemed_at': iso(DateTime(2026, 11, 3))},
            ],
            'payments': [
              {'amount_in_cents': 2990000, 'currency': 'COP', 'plan_id': 'business_month_cop', 'status': 'PENDING', 'created_at': iso(DateTime(2026, 11, 9))},
            ],
            'subscriptions': [
              {'kind': 'business', 'source': 'manual', 'starts_at': iso(DateTime(2026, 11, 23)), 'ends_at': iso(now.add(const Duration(days: 364))), 'active': true, 'business': 'Miselanea'},
              {'kind': 'services', 'source': 'manual', 'starts_at': iso(DateTime(2026, 11, 11)), 'ends_at': iso(now.add(const Duration(days: 17))), 'active': true, 'business': 'LAVADERO'},
              {'kind': 'business', 'source': 'manual', 'starts_at': iso(DateTime(2026, 11, 10)), 'ends_at': iso(DateTime(2026, 11, 11)), 'active': false, 'business': 'LAVADERO'},
            ],
          },
        'admin_list_notes' => {'notes': [], 'contacted': null},
        'admin_branch_slots' => {'allowance': 3, 'open': 0, 'slots': []},
        'admin_list_admins' => [
            {'email': 'jose@ejemplo.com', 'role': 'OWNER'},
          ],
        'admin_list_actions' => [
            {'action': 'grant_branch_slots', 'admin_email': 'jose@ejemplo.com', 'created_at': iso(now), 'detail': {'business_id': 'b1', 'slots': 1, 'days': 17}},
            {'action': 'grant_pro', 'admin_email': 'jose@ejemplo.com', 'created_at': iso(now.subtract(const Duration(days: 1))), 'detail': {'business_id': 'b2', 'days': 365, 'kind': 'business'}},
            {'action': 'feedback_update', 'admin_email': 'jose@ejemplo.com', 'created_at': iso(now.subtract(const Duration(days: 1))), 'detail': {'status': 'DESCARTADO'}},
            {'action': 'create_codes', 'admin_email': 'jose@ejemplo.com', 'created_at': iso(now.subtract(const Duration(days: 3))), 'detail': {'count': 1, 'days': 30, 'kind': 'business'}},
          ],
        'admin_find_businesses' => [
            {'id': 'b1', 'name': 'LAVADERO', 'owner_email': 'jose@ejemplo.com', 'country': 'CO', 'pro': true},
            {'id': 'b2', 'name': 'Miselanea', 'owner_email': 'olinda@ejemplo.com', 'country': 'CO', 'pro': true},
            {'id': 'b3', 'name': 'Minimercado La Esquina', 'owner_email': 'soporte@ejemplo.com', 'country': 'CO', 'pro': false},
          ],
        'admin_list_payments' => [
            {'reference': 'STK-5239', 'business_name': 'Yeddgd', 'user_email': 'jose@ejemplo.com', 'kind': 'business', 'period': 'month', 'amount_in_cents': 2990000, 'currency': 'COP', 'status': 'PENDING', 'created_at': iso(DateTime(2026, 11, 9))},
            {'reference': 'STK-2E8C', 'business_name': 'test', 'user_email': 'soporte@ejemplo.com', 'kind': 'business', 'period': 'week', 'amount_in_cents': 200000, 'currency': 'COP', 'status': 'APPROVED', 'payment_method': 'NEQUI', 'created_at': iso(DateTime(2026, 11, 3))},
          ],
        _ => null,
      };

  setUp(() {
    ProAdminService.debugRpc = fake;
    ProAdminService.instance.role.value = 'OWNER';
  });
  tearDown(() {
    ProAdminService.debugRpc = null;
    ProAdminService.instance.role.value = 'VIEWER';
  });

  final screens = <String, Widget Function()>{
    'ficha': () => const SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: SizedBox(width: 520, child: AdminUserDetailDialog(email: 'jose@ejemplo.com')),
        ),
    'registro': () => const AdminTeamPage(),
    'pagos': () => const AdminPaymentsPage(),
    'negocios': () => const AdminBusinessesPage(),
  };

  for (final entry in screens.entries) {
    for (final size in const [Size(1440, 900), Size(390, 1400)]) {
      testWidgets('${entry.key} a ${size.width.toInt()} px sin desbordes', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: RepaintBoundary(key: key, child: entry.value())),
        ));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull);
        final out = Platform.environment['PREVIEW_OUT'];
        if (out != null) {
          await tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            File('$out/panel_${entry.key}_${size.width.toInt()}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
      });
    }
  }

  testWidgets('la ficha muestra lo nuevo: plan, sedes e historial legible', (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: SingleChildScrollView(child: AdminUserDetailDialog(email: 'jose@ejemplo.com'))),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Jose Riatiga'), findsOneWidget);
    expect(find.text('JR'), findsOneWidget);
    expect(find.textContaining('Sedes 0 de 3'), findsOneWidget);
    expect(find.textContaining('Pro · Mensual · sin terminar'), findsOneWidget);
    // «Cupos de sede» solo en el negocio del que es dueño (antes salía también como cajero)
    expect(find.text('Cupos de sede'), findsOneWidget);
  });
}
