import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/admin/admin_health_section.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/pro/data/pro_admin_service.dart';

final _healthJson = {
  'no_cloud': [
    {'email': 'ana@correo.com', 'name': 'Ana', 'phone': '3001234567', 'created_at': '2026-11-01T10:00:00Z'},
  ],
  'expiring': [
    {'business': 'Miselanea', 'owner_email': 'olinda@correo.com', 'phone': '+57 311 000 0000', 'ends_at': '2026-11-12T00:00:00Z'},
  ],
  'failed_payments': [
    {'user_email': 'pepe@correo.com', 'business': 'Tienda Pepe', 'amount_in_cents': 990000, 'created_at': '2026-11-07T00:00:00Z'},
  ],
  'inactive_30d': 2,
  'usage': {
    'db_bytes': 14243507,
    'db_limit_bytes': 524288000,
    'storage_bytes': 2513245,
    'storage_objects': 18,
    'storage_limit_bytes': 1073741824,
  },
};

void main() {
  test('número de WhatsApp: agrega el 57 a los celulares de 10 dígitos', () {
    expect(whatsappDigits('3117697927'), '573117697927');
    expect(whatsappDigits('+57 311 769 7927'), '573117697927');
    expect(whatsappDigits('123'), isNull);
    expect(whatsappDigits(null), isNull);
  });

  test('la salud se lee con el uso de Supabase', () {
    final h = AdminHealth.fromJson(_healthJson);
    expect(h.noCloud.single['email'], 'ana@correo.com');
    expect(h.expiring.length, 1);
    expect(h.inactive30d, 2);
    expect(h.allGood, isFalse);
    expect(AdminHealth.bytesLabel(h.dbBytes), '13,6 MB');
    expect(AdminHealth.bytesLabel(h.storageLimitBytes), '1,0 GB');
    expect(h.dbUse, closeTo(0.027, 0.001));
  });

  test('la ficha se lee sin datos de ventas ni productos', () {
    final d = AdminUserDetail.fromJson({
      'account': {
        'email': 'ana@correo.com',
        'name': 'Ana',
        'phone': '3001234567',
        'provider': 'google',
        'created_at': '2026-11-01T10:00:00Z',
        'email_confirmed_at': '2026-11-01T10:01:00Z',
      },
      'businesses': [
        {
          'id': 'b1',
          'name': 'Loliando',
          'role': 'OWNER',
          'country': 'CO',
          'pro': {'active': true, 'ends_at': null},
          'store_slug': 'loliando',
          'store_enabled': true,
        },
      ],
      'redemptions': [],
      'payments': [],
      'subscriptions': [],
    });
    expect(d.providerLabel, 'Google');
    expect(d.businesses.single.roleLabel, 'Dueño');
    expect(d.businesses.single.pro, isTrue);
    expect(d.businesses.single.proUntil, isNull); // permanente
  });

  for (final width in [360.0, 1200.0]) {
    testWidgets('la salud se ve bien a ${width.toInt()} px', (tester) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(child: AdminHealthSection(health: AdminHealth.fromJson(_healthJson))),
        ),
      ));
      expect(find.text('Salud de Stockealo'), findsOneWidget);
      expect(find.text('1 cuenta sin negocio en la nube'), findsOneWidget);
      expect(find.text('1 Pro vence en los próximos 7 días'), findsOneWidget);
      expect(find.text('Uso de Supabase'), findsOneWidget);
      expect(find.text('13,6 MB de 500,0 MB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
