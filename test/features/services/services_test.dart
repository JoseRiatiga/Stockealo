import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/models/app_user.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/sales/data/sales_repository.dart';
import 'package:stockealo/features/services/data/order_whatsapp.dart';
import 'package:stockealo/features/services/data/services_repository.dart';
import 'package:stockealo/features/services/models/service_models.dart';
import 'package:stockealo/features/services/presentation/screens/services_tab.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'services-test';
  const businessId = 'biz-lav';
  final appDb = AppDatabase.instance;
  final repo = ServicesRepository.instance;
  final now = DateTime(2026, 11, 10, 9);
  final business = Business(
    id: businessId,
    userId: 'u1',
    name: 'Lavadero El Brillo',
    servicesEnabled: true,
    serviceType: ServiceTemplate.lavadero.code,
    createdAt: now,
  );

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_services_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  setUp(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    final db = await appDb.database;
    await db.insert('users', {'id': 'u1', 'email': 'ana@x.com', 'password': authManagedPassword, 'created_at': '2026-10-01'});
    await db.insert('businesses', business.toMap());
    AuthRepository.debugCurrentUser = AppUser(id: 'u1', email: 'ana@x.com', name: 'Ana', createdAt: now);
  });

  tearDown(() => AuthRepository.debugCurrentUser = null);

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('los servicios de ejemplo del lavadero se agregan una sola vez', () async {
    // Desde la 0.12.0 el lavadero usa la plantilla de motos y carros
    expect(await repo.seedTemplate(businessId, ServiceTemplate.lavadero), ServiceTemplate.lavadero.examples.length);
    expect(await repo.seedTemplate(businessId, ServiceTemplate.lavadero), 0);
    final list = await repo.getServices(businessId);
    expect(list.first.name, 'Lavado sencillo');
    expect(list.first.commissionPct, 40);
    expect(list.first.priceFor('CARRO'), 20000);
  });

  test('la orden avanza por el tablero, guarda las horas y numera por día', () async {
    const line = WorkOrderLine(serviceId: 's1', name: 'Lavado completo', price: 15000, staffIds: ['juan']);
    final first = await repo.createOrder(businessId: businessId, lines: [line], plate: 'abc-12d', now: now);
    final second = await repo.createOrder(businessId: businessId, lines: [line], plate: 'XYZ 98A', now: now);
    expect(first.plate, 'ABC12D');
    expect([first.number, second.number], ['1', '2']);
    expect(first.nextStatus, WorkOrder.inProgress);

    final washing = await repo.moveTo(first, WorkOrder.inProgress, now: now.add(const Duration(minutes: 5)));
    final ready = await repo.moveTo(washing, WorkOrder.ready, now: now.add(const Duration(minutes: 30)));
    expect(ready.statusTimes.keys, containsAll([WorkOrder.waiting, WorkOrder.inProgress, WorkOrder.ready]));
    expect(ready.since, now.add(const Duration(minutes: 30)));
    expect(ready.nextStatus, WorkOrder.delivered);

    final cancelled = await repo.cancel(second);
    expect(cancelled.status, WorkOrder.cancelled);
    expect((await repo.getBoard(businessId)).length, 2, reason: 'las canceladas de hoy siguen a la vista');

    expect((await repo.ordersByPlate(businessId, 'abc 12d')).single.id, first.id);
    expect((await repo.platesStartingWith(businessId, 'AB')).single.plate, 'ABC12D');
  });

  test('cobrar una orden: una venta por servicio sin tocar el inventario, descuento repartido y fiado', () async {
    final order = await repo.createOrder(
      businessId: businessId,
      plate: 'ABC12D',
      customerName: 'Carlos',
      lines: const [
        WorkOrderLine(serviceId: 's1', name: 'Lavado completo', price: 15000, staffIds: ['juan']),
        WorkOrderLine(serviceId: 's2', name: 'Lavado de casco', price: 5000, staffIds: ['juan', 'pedro']),
      ],
      now: now,
    );
    final sales = await SalesRepository.instance.recordServiceSale(
      order: order,
      paymentMethod: 'FIADO',
      customerName: 'Carlos',
      discountAmount: 2000,
      staffNames: const {'juan': 'Juan', 'pedro': 'Pedro'},
      now: now,
    );
    expect(sales.map((s) => s.totalAmount), [13500, 4500]);
    expect(sales.every((s) => s.isService), isTrue);

    final db = await appDb.database;
    final rows = await db.query('sales', orderBy: 'total DESC');
    expect(rows.every((r) => r['product_id'] == null), isTrue);
    expect(rows.first['notes'], 'Placa ABC12D · Atendió: Juan');
    expect(rows.last['notes'], 'Placa ABC12D · Atendió: Juan, Pedro');
    expect(await db.query('stock_movements'), isEmpty);
    expect((await db.query('customers')).single['debt_balance'], 18000);

    final paid = await repo.markPaid(order,
        saleIds: [for (final s in sales) s.id], paymentMethod: 'FIADO', total: 18000, discount: 2000, tip: 3000);
    expect(paid.status, WorkOrder.delivered);
    expect(paid.isPaid, isTrue);
    expect(() => repo.cancel(paid), throwsStateError);

    // Anular un servicio desde Ventas no toca inventario (antes fallaba sin producto)
    final listed = await SalesRepository.instance.getSales(businessId: businessId);
    final casco = listed.firstWhere((s) => s.productName == 'Lavado de casco');
    expect(casco.productId, '');
    await SalesRepository.instance.cancelSale(casco);
    expect((await db.query('sales')).length, 1);
    expect(await db.query('stock_movements'), isEmpty);
    expect((await db.query('customers')).single['debt_balance'], 13500);
  });

  test('el aviso de listo usa las palabras de la plantilla', () {
    WorkOrder order(String? kind) => WorkOrder(
          id: 'o', businessId: businessId, number: '3', plate: 'ABC12D', vehicleKind: kind, customerName: 'Carlos Pérez',
          lines: const [WorkOrderLine(serviceId: 's', name: 'Lavado', price: 15000)], createdAt: now, updatedAt: now,
        );
    expect(
      OrderWhatsApp.readyMessage(order('MOTO'), business),
      'Hola Carlos, te saluda Lavadero El Brillo: tu moto ABC12D ya está lista. Total: \$15.000. ¡Te esperamos!',
    );
    expect(OrderWhatsApp.readyMessage(order('CARRO'), business), contains('tu carro ABC12D ya está listo'));
    final barberia = business.copyWith(serviceType: ServiceTemplate.barberia.code);
    final msg = OrderWhatsApp.readyMessage(order(null), barberia);
    expect(msg, contains('tu servicio ya está listo'));
    expect(msg.toLowerCase(), isNot(contains('moto')));
  });

  Future<void> settle(WidgetTester tester, Finder until) async {
    for (var i = 0; i < 30 && until.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  testWidgets('la primera vez se elige la plantilla del negocio', (tester) async {
    final nuevo = business.copyWith(servicesEnabled: false);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: ServicesTab(business: Business.fromMap({...nuevo.toMap(), 'service_type': null}), userRole: 'OWNER'),
    ));
    await tester.pump();
    expect(find.text('¿Qué tipo de negocio es?'), findsOneWidget);
    expect(find.text('Lavadero de motos y carros'), findsOneWidget);
    expect(find.text('Barbería o peluquería'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 1200.0]) {
    testWidgets('pestaña Servicios: tablero, recibir, asistencia, historial y catálogo a ${width.toInt()} px', (tester) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await repo.seedTemplate(businessId, ServiceTemplate.lavadero);
        final juan = repo.newStaff(businessId, 'Juan Gómez');
        await repo.saveStaff(juan);
        final completo = (await repo.getServices(businessId)).firstWhere((s) => s.name == 'Lavado completo');
        await repo.createOrder(
          businessId: businessId,
          plate: 'ABC12D',
          vehicleKind: 'MOTO',
          lines: [WorkOrderLine(serviceId: completo.id, name: completo.name, price: 15000)],
        );
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: ServicesTab(business: business, userRole: 'OWNER'),
      ));
      await settle(tester, find.text('ABC12D'));

      // Tablero: el trabajo con su servicio pendiente y el aviso de marcar asistencia
      expect(find.text('ABC12D'), findsOneWidget);
      expect(find.text('Empezar'), findsOneWidget);
      expect(find.textContaining('Marca quién vino hoy'), findsOneWidget);
      expect(find.text('Juan · Sin marcar'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Recibir: los precios cambian según el tipo de vehículo
      await tester.tap(find.text('Recibir').first);
      await settle(tester, find.text('Tipo de vehículo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carro'));
      await settle(tester, find.text('Lavado completo · \$30.000'));
      expect(find.text('Lavado completo · \$30.000'), findsOneWidget);
      expect(find.textContaining('Lavado de casco'), findsNothing, reason: 'el casco es solo para motos');
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asistencia'));
      await settle(tester, find.text('Juan Gómez'));
      expect(find.text('Llegó'), findsOneWidget);
      expect(find.text('No vino'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Historial'));
      await settle(tester, find.textContaining('ABC12D'));
      expect(find.textContaining('ABC12D'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Catálogo y precios'));
      await settle(tester, find.textContaining('Camioneta'));
      expect(find.text('Moto \$15.000 · Carro \$30.000 · Camioneta \$35.000'), findsOneWidget);
      expect(find.text('Moto \$5.000'), findsOneWidget, reason: 'lavado de casco');
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    });
  }
}
