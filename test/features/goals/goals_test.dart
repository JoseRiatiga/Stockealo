import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/permissions/permissions.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/models/app_user.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/goals/data/goals_repository.dart';
import 'package:stockealo/features/goals/models/sales_goal.dart';
import 'package:stockealo/features/goals/presentation/goals_widgets.dart';

/// Metas de ventas (0.16.0, fase 0)
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'goals-test';
  const businessId = 'biz-goals';
  final appDb = AppDatabase.instance;
  final repo = GoalsRepository.instance;
  final business = Business(id: businessId, userId: 'u1', name: 'Variedades Rosita', color: '#1E6B4E', createdAt: DateTime(2026, 11, 1));

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  var n = 0;
  Future<void> sale(DateTime at, double total, {bool voided = false}) async {
    final db = await appDb.database;
    n++;
    await db.insert('sales', {
      'id': 's$n',
      'business_id': businessId,
      'product_id': 'p1',
      'product_name': 'Arroz',
      'quantity': 1,
      'date': at.toIso8601String(),
      'total': total,
      'total_cost': 0,
      'net_profit': total,
      'payment_method': 'EFECTIVO',
      'payment_status': 'PAGADO',
      'created_at': at.toIso8601String(),
      if (voided) 'voided_at': at.toIso8601String(),
    });
  }

  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    dbDir = await Directory.systemTemp.createTemp('stockealo_goals_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  setUp(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    final db = await appDb.database;
    await db.insert('users', {'id': 'u1', 'email': 'rosa@x.com', 'password': authManagedPassword, 'created_at': '2026-10-01'});
    await db.insert('businesses', business.toMap());
    await db.insert('products', {
      'id': 'p1', 'business_id': businessId, 'code': 'C-1', 'name': 'Arroz', 'category': 'Granos',
      'purchase_price': 0, 'sale_price': 1000, 'stock': 100, 'min_stock': 5,
      'created_at': '2026-10-01', 'updated_at': '2026-10-01',
    });
    AuthRepository.debugCurrentUser = AppUser(id: 'u1', email: 'rosa@x.com', name: 'Rosa Pérez', createdAt: DateTime(2026, 10, 1));
  });

  tearDown(() => AuthRepository.debugCurrentUser = null);

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('la semana empieza el lunes y el mes el día 1', () {
    final sun = DateTime(2026, 11, 15, 18); // domingo
    expect(GoalPeriod.week.startOf(sun), DateTime(2026, 11, 9));
    expect(GoalPeriod.week.endOf(DateTime(2026, 11, 9)), DateTime(2026, 11, 16));
    expect(GoalPeriod.month.startOf(sun), DateTime(2026, 11, 1));
    expect(GoalPeriod.month.endOf(DateTime(2026, 12, 1)), DateTime(2027, 1, 1));
    expect(GoalPeriod.month.previous(DateTime(2026, 1, 1)), DateTime(2025, 12, 1));
  });

  test('cómo va: porcentaje, lo que falta, por día y si va al ritmo', () {
    final p = GoalProgress(
      period: GoalPeriod.month,
      goal: 3000000,
      sold: 1000000,
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 12, 1),
      now: DateTime(2026, 11, 16, 10),
    );
    expect(p.percent, 33);
    expect(p.missing, 2000000);
    expect(p.daysLeft, 15); // del 16 al 30, contando hoy
    expect(p.perDay.round(), 133333);
    expect(p.onPace, isFalse); // a la mitad del mes debería llevar 1.600.000
    final ok = GoalProgress(period: GoalPeriod.week, goal: 700, sold: 400, from: DateTime(2026, 11, 9), to: DateTime(2026, 11, 16), now: DateTime(2026, 11, 12));
    expect(ok.onPace, isTrue); // 4 de 7 días: 400 es justo el ritmo
  });

  test('la meta vale desde el periodo en que se puso y la nueva reemplaza a la vieja', () async {
    await repo.setGoal(businessId: businessId, period: GoalPeriod.month, amount: 5000000, now: DateTime(2026, 9, 10));
    await repo.setGoal(businessId: businessId, period: GoalPeriod.month, amount: 8000000, now: DateTime(2026, 11, 3));
    final all = await repo.list(businessId);
    expect(GoalsRepository.goalFor(all, GoalPeriod.month, DateTime(2026, 8, 1)), isNull);
    expect(GoalsRepository.goalFor(all, GoalPeriod.month, DateTime(2026, 10, 1))!.amount, 5000000);
    expect(GoalsRepository.goalFor(all, GoalPeriod.month, DateTime(2026, 11, 1))!.amount, 8000000);
    // Cambiarla dos veces en el mismo mes deja un solo registro
    await repo.setGoal(businessId: businessId, period: GoalPeriod.month, amount: 9000000, now: DateTime(2026, 11, 20));
    expect((await repo.list(businessId)).length, 2);
    // Quitarla (0) = sin meta desde ese mes
    await repo.setGoal(businessId: businessId, period: GoalPeriod.month, amount: 0, now: DateTime(2026, 12, 2));
    expect(GoalsRepository.goalFor(await repo.list(businessId), GoalPeriod.month, DateTime(2026, 12, 1)), isNull);
    // La meta de una persona no se mezcla con la del negocio
    await repo.setGoal(businessId: businessId, period: GoalPeriod.week, amount: 500000, memberUserId: 'u2', memberName: 'Luis', now: DateTime(2026, 11, 10));
    final again = await repo.list(businessId);
    expect(GoalsRepository.goalFor(again, GoalPeriod.week, DateTime(2026, 11, 9)), isNull);
    expect(GoalsRepository.goalFor(again, GoalPeriod.week, DateTime(2026, 11, 9), member: 'u2')!.amount, 500000);
  });

  test('lo vendido cuenta solo el periodo, sin anuladas y con las devoluciones restando', () async {
    await repo.setGoal(businessId: businessId, period: GoalPeriod.week, amount: 1000000, now: DateTime(2026, 11, 9));
    await sale(DateTime(2026, 11, 8, 20), 300000); // semana anterior
    await sale(DateTime(2026, 11, 9, 9), 200000);
    await sale(DateTime(2026, 11, 11, 15), 150000);
    await sale(DateTime(2026, 11, 11, 16), 90000, voided: true);
    await sale(DateTime(2026, 11, 12, 10), -50000); // devolución
    await sale(DateTime.utc(2026, 11, 13, 15), 100000); // bajada de la nube, en UTC
    final p = (await repo.businessProgress(businessId, GoalPeriod.week, now: DateTime(2026, 11, 13, 18)))!;
    expect(p.sold, 400000);
    expect(p.percent, 40);
    final daily = await repo.dailySales(businessId, p.from, p.to);
    expect(daily.length, 7);
    expect(daily[0], 200000);
    expect(daily[2], 150000);
    // Historial: la semana anterior tenía la misma meta (se puso el 9, no antes) → sin meta
    expect(await repo.businessHistory(businessId, GoalPeriod.week, now: DateTime(2026, 11, 13)), isEmpty);
    final next = await repo.businessHistory(businessId, GoalPeriod.week, now: DateTime(2026, 11, 18));
    expect(next.single.sold, 400000);
    expect(next.single.reached, isFalse);
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child)));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  testWidgets('Inicio: sin meta, el dueño ve la invitación; con meta, las barras', (tester) async {
    await pump(tester, GoalsCard(business: business, role: Permissions.owner));
    expect(find.text('Ponle una meta a tus ventas'), findsOneWidget);
    await tester.runAsync(() async {
      await repo.setGoal(businessId: businessId, period: GoalPeriod.week, amount: 2000000);
      await repo.setGoal(businessId: businessId, period: GoalPeriod.month, amount: 8000000);
      await sale(DateTime.now(), 500000);
    });
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.text('Esta semana'), findsOneWidget);
    expect(find.text('Este mes'), findsOneWidget);
    expect(find.text('25 %'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inicio: un cajero sin meta propia no ve nada', (tester) async {
    await pump(tester, GoalsCard(business: business, role: Permissions.cashier));
    expect(find.text('Ponle una meta a tus ventas'), findsNothing);
    expect(find.text('Metas'), findsNothing);
  });

  testWidgets('Reportes › Metas: gráfica y lo de Pro invita a Pro en el plan gratis', (tester) async {
    await tester.runAsync(() async {
      await repo.setGoal(businessId: businessId, period: GoalPeriod.month, amount: 8000000);
      await sale(DateTime.now(), 1200000);
    });
    await pump(tester, GoalsView(business: business, role: Permissions.owner));
    expect(find.byType(GoalChart), findsOneWidget);
    expect(find.text('Metas del equipo'), findsOneWidget);
    expect(find.text('Ver Pro'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
