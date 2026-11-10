import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/models/app_user.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/reports/data/report_export_service.dart';
import 'package:stockealo/features/sales/data/sales_repository.dart';
import 'package:stockealo/features/services/data/commissions_repository.dart';
import 'package:stockealo/features/services/data/services_repository.dart';
import 'package:stockealo/features/services/models/commission_models.dart';
import 'package:stockealo/features/services/models/service_models.dart';

/// Comisiones y liquidaciones (0.12.0)
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'commissions-test';
  const businessId = 'biz-com';
  final appDb = AppDatabase.instance;
  final services = ServicesRepository.instance;
  final commissions = CommissionsRepository.instance;
  final now = DateTime(2026, 11, 10, 9);
  final business = Business(
    id: businessId,
    userId: 'u1',
    name: 'Lavadero Brillo',
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
    dbDir = await Directory.systemTemp.createTemp('stockealo_commissions_');
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

  /// Lavado de carro $20.000 al 40 % por Juan; polichado $10.000 al 50 % entre Juan y Pedro
  Future<(StaffMember, StaffMember, WorkOrder)> chargedOrder({double discount = 0, double tip = 0}) async {
    final juan = services.newStaff(businessId, 'Juan');
    final pedro = services.newStaff(businessId, 'Pedro');
    await services.saveStaff(juan);
    await services.saveStaff(pedro);
    var order = await services.createOrder(
      businessId: businessId,
      plate: 'ABC12D',
      vehicleKind: 'CARRO',
      lines: [
        WorkOrderLine(serviceId: 's1', name: 'Lavado', price: 20000, commissionPct: 40,
            staffIds: [juan.id], status: WorkOrderLine.done),
        WorkOrderLine(serviceId: 's2', name: 'Polichado', price: 10000, commissionPct: 50,
            staffIds: [juan.id, pedro.id], status: WorkOrderLine.done),
      ],
      now: now,
    );
    final sales = await SalesRepository.instance.recordServiceSale(
      order: order,
      paymentMethod: 'EFECTIVO',
      discountAmount: discount,
      tipAmount: tip,
      now: now,
    );
    order = await services.markPaid(order,
        saleIds: [for (final s in sales) s.id], paymentMethod: 'EFECTIVO', total: 30000 - discount, discount: discount, tip: tip, now: now);
    return (juan, pedro, order);
  }

  test('la comisión se reparte entre quienes hicieron el servicio', () {
    final parts = CommissionsRepository.split(10000, 50, ['a', 'b']);
    expect(parts.map((p) => p.amount), [2500, 2500]);
    expect(parts.map((p) => p.base), [5000, 5000]);
    expect(CommissionsRepository.split(10000, 50, const []), isEmpty);
  });

  test('cobrar deja la comisión sobre lo cobrado, la propina repartida y la ganancia neta', () async {
    // Descuento de $3.000: se reparte 2/3 al lavado y 1/3 al polichado
    final (juan, pedro, _) = await chargedOrder(discount: 3000, tip: 4000);
    final pending = await commissions.pending(businessId);
    final ofJuan = pending.firstWhere((e) => e.staffId == juan.id);
    final ofPedro = pending.firstWhere((e) => e.staffId == pedro.id);
    // Juan: 40 % de 18.000 + 50 % de la mitad de 9.000 + mitad de la propina
    expect(ofJuan.commissions, 7200 + 2250);
    expect(ofJuan.tips, 2000);
    expect(ofJuan.services, 2);
    expect(ofPedro.commissions, 2250);
    expect(ofPedro.tips, 2000);

    final db = await appDb.database;
    final rows = await db.query('sales', orderBy: 'total DESC');
    expect(rows.first['total'], 18000);
    expect(rows.first['total_cost'], 7200);
    expect(rows.first['net_profit'], 10800);
    expect(rows.last['total_cost'], 4500);
  });

  test('pagar marca todo como pagado y queda la liquidación', () async {
    final (juan, _, _) = await chargedOrder(tip: 2000);
    final ofJuan = (await commissions.pending(businessId)).firstWhere((e) => e.staffId == juan.id);
    final payout = await commissions.pay(businessId, ofJuan, staffName: 'Juan', now: now);
    expect(payout.total, 8000 + 2500 + 1000);
    expect((await commissions.pending(businessId)).any((e) => e.staffId == juan.id), isFalse);
    expect((await commissions.payouts(businessId)).single.staffId, juan.id);
    // Lo ganado del día sigue contando para el cierre aunque esté pagado
    final day = await commissions.earnedBetween(businessId, DateTime(2026, 11, 10), DateTime(2026, 11, 11));
    expect(day.firstWhere((e) => e.staffId == juan.id).total, payout.total);
    expect(() => commissions.pay(businessId, const StaffEarnings('x', [])), throwsStateError);
  });

  test('anular un cobro quita lo pendiente y deja ajuste negativo de lo ya pagado', () async {
    final (juan, pedro, order) = await chargedOrder(tip: 2000);
    final ofJuan = (await commissions.pending(businessId)).firstWhere((e) => e.staffId == juan.id);
    await commissions.pay(businessId, ofJuan, now: now);

    await services.reopenPaid(order, note: 'Cobré mal', now: now);
    final pending = await commissions.pending(businessId);
    // Pedro no había cobrado: no le queda nada
    expect(pending.any((e) => e.staffId == pedro.id), isFalse);
    // Juan ya había cobrado: le queda un ajuste que descuenta lo pagado
    final juanNow = pending.firstWhere((e) => e.staffId == juan.id);
    expect(juanNow.total, -(8000 + 2500 + 1000));
    expect(juanNow.items.every((c) => c.kind == Commission.kindAdjustment), isTrue);
  });

  test('el detalle para WhatsApp lleva cada servicio y el total', () {
    final e = StaffEarnings('j', [
      Commission(id: '1', businessId: businessId, staffId: 'j', label: 'Lavado', amount: 8000, date: now, updatedAt: now),
      Commission(id: '2', businessId: businessId, staffId: 'j', label: 'Propina', kind: Commission.kindTip,
          amount: 1000, date: now, updatedAt: now),
    ]);
    final text = CommissionsRepository.detailMessage(staffName: 'Juan Gómez', businessName: 'Brillo', earnings: e, paid: true);
    expect(text, contains('Hola Juan'));
    expect(text, contains('10/11 Lavado: \$8.000'));
    expect(text, contains('Propinas: \$1.000'));
    expect(text, contains('Pagado: \$9.000'));
  });

  test('las hojas de Servicios y Comisiones solo están con Pro Servicios', () {
    expect(ReportSection.available(services: false), isNot(contains(ReportSection.commissions)));
    expect(ReportSection.available(services: true), containsAll([ReportSection.services, ReportSection.commissions]));
  });
}
