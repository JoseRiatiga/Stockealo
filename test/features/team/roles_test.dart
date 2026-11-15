import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/permissions/permissions.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/models/app_user.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/team/data/roles_repository.dart';
import 'package:stockealo/features/team/data/team_repository.dart';
import 'package:stockealo/features/team/models/business_member.dart';
import 'package:stockealo/features/team/models/business_role.dart';
import 'package:stockealo/features/team/presentation/screens/roles_screen.dart';

/// 0.15.0, etapa 2: roles propios del negocio
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'roles-test';
  const bizId = 'biz-roles';
  final appDb = AppDatabase.instance;
  final repo = RolesRepository.instance;
  final now = DateTime(2026, 11, 14, 9);
  final business = Business(id: bizId, userId: 'u1', name: 'Nova Moda', createdAt: now);

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  setUpAll(() async {
    // La cola de la nube lee las preferencias: sin esto la espera de escrituras no termina
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => call.method == 'getAll' ? <String, Object>{} : true,
    );
    dbDir = await Directory.systemTemp.createTemp('stockealo_roles_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  setUp(() async {
    Permissions.applyBusiness();
    Permissions.viewAs.value = null;
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    final db = await appDb.database;
    await db.insert('users', {'id': 'u1', 'email': 'ana@x.com', 'password': authManagedPassword, 'created_at': '2026-10-01'});
    await db.insert('businesses', business.toMap());
    await db.insert('business_members', {
      'id': 'm-owner',
      'business_id': bizId,
      'user_id': 'u1',
      'email': 'ana@x.com',
      'name': 'Ana',
      'role': 'OWNER',
      'status': 'ACTIVE',
      'created_at': now.toIso8601String(),
    });
    await db.insert('business_members', {
      'id': 'm-luis',
      'business_id': bizId,
      'user_id': 'u2',
      'email': 'luis@x.com',
      'name': 'Luis',
      'role': 'CASHIER',
      'status': 'ACTIVE',
      'created_at': now.toIso8601String(),
    });
    AuthRepository.debugCurrentUser = AppUser(id: 'u1', email: 'ana@x.com', name: 'Ana', createdAt: now);
  });

  tearDown(() {
    AuthRepository.debugCurrentUser = null;
    Permissions.applyBusiness();
    Permissions.viewAs.value = null;
  });

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  Future<BusinessMember> luis() async =>
      (await TeamRepository.instance.getMembers(bizId)).firstWhere((m) => m.id == 'm-luis');
  Future<String> roleOfLuis() =>
      TeamRepository.instance.getUserRoleInBusiness(businessId: bizId, userId: 'u2', userEmail: 'luis@x.com');

  group('Permissions con los roles del negocio', () {
    test('el ajuste del Cajero cambia lo que puede; el Dueño siempre todo', () {
      Permissions.applyBusiness(builtins: {Permissions.cashier: {Perm.sell, Perm.costs}});
      expect(Permissions.can('CASHIER', Perm.costs), isTrue);
      expect(Permissions.can('CASHIER', Perm.credit), isFalse);
      expect(Permissions.can('OWNER', Perm.team), isTrue);
      // Un rol desconocido nunca gana lo que se le dio al Cajero
      expect(Permissions.can('SUPPORT', Perm.costs), isFalse);
    });

    test('un rol propio se lee como ROLE:<id>; uno que no existe queda como Cajero', () {
      Permissions.applyBusiness(custom: {'r1': (name: 'Vendedor', perms: {Perm.sell})});
      expect(Permissions.can(Permissions.customRole('r1'), Perm.sell), isTrue);
      expect(Permissions.can(Permissions.customRole('r1'), Perm.cashOwn), isFalse);
      expect(Permissions.labelOf(Permissions.customRole('r1')), 'Vendedor');
      expect(Permissions.can(Permissions.customRole('borrado'), Perm.costs), isFalse);
      expect(Permissions.can(Permissions.customRole('borrado'), Perm.sell), isTrue);
    });

    test('el rol de la nube se elige por lo que tiene', () {
      expect(Permissions.baseFor({Perm.sell, Perm.credit}), Permissions.cashier);
      expect(Permissions.baseFor({Perm.sell, Perm.costs}), Permissions.admin);
    });

    test('apagar un permiso apaga los que lo necesitan', () {
      expect(Permissions.dependentsOf(Perm.sell), containsAll([Perm.voidSale, Perm.discount, Perm.credit, Perm.sellBelowCost]));
      expect(Permissions.dependentsOf(Perm.sell), isNot(contains(Perm.costs)));
    });
  });

  group('RolesRepository', () {
    test('crear un rol propio, asignarlo, cambiarlo y borrarlo', () async {
      final vendedor = repo.newCustom(bizId, name: 'Vendedor', perms: {Perm.sell, Perm.credit}, templateId: 'vendedor');
      await repo.save(vendedor, summary: 'Creó el rol Vendedor');
      expect((await repo.list(bizId)).single.baseRole, Permissions.cashier);

      await repo.assign(await luis(), role: vendedor);
      expect(await roleOfLuis(), Permissions.customRole(vendedor.id));
      expect(Permissions.can(await roleOfLuis(), Perm.credit), isTrue);
      expect(Permissions.can(await roleOfLuis(), Perm.cashOwn), isFalse, reason: 'no maneja plata');
      expect((await luis()).roleDisplayName, 'Vendedor');

      // Con costos ya necesita apoyarse en el Administrador de la nube
      await repo.save(vendedor.copyWith(perms: {Perm.sell, Perm.costs}));
      final db = await appDb.database;
      final row = (await db.query('business_members', where: 'id = ?', whereArgs: ['m-luis'])).single;
      expect(row['role'], Permissions.admin);

      // Borrar: Luis vuelve a su rol de la nube, nunca se queda sin entrar
      await repo.delete((await repo.list(bizId)).single);
      expect(await repo.list(bizId), isEmpty);
      expect(await roleOfLuis(), Permissions.admin);
      await SupabaseService.instance.waitForPendingWrites();
    });

    test('el ajuste del Cajero se guarda y se carga al abrir el negocio', () async {
      await repo.save(repo.builtinWith(bizId, Permissions.cashier, {Perm.sell, Perm.costs}));
      Permissions.applyBusiness();
      expect(Permissions.can('CASHIER', Perm.costs), isFalse);
      await repo.apply(bizId);
      expect(Permissions.can('CASHIER', Perm.costs), isTrue);
      expect((await repo.list(bizId)).single.id, BusinessRole.builtinId(bizId, Permissions.cashier));
      await SupabaseService.instance.waitForPendingWrites();
    });

    test('los límites se guardan con el rol y se cargan por rol; el Dueño no tiene', () async {
      await repo.save(repo.builtinWith(bizId, Permissions.cashier, Permissions.factoryDefaults(Permissions.cashier),
          limits: {RoleLimit.discountPct: 10, RoleLimit.cashOutMax: 50000}));
      Permissions.applyBusiness();
      await repo.apply(bizId);
      expect(Permissions.limitOf('CASHIER', RoleLimit.discountPct), 10);
      expect(Permissions.limitOf('cashier', RoleLimit.cashOutMax), 50000);
      expect(Permissions.limitOf('CASHIER', RoleLimit.creditMax), isNull, reason: 'sin límite');
      expect(Permissions.limitOf('OWNER', RoleLimit.discountPct), isNull);
      final role = (await repo.list(bizId)).single;
      expect(BusinessRole.fromMap(role.toMap()).limits, {RoleLimit.discountPct: 10, RoleLimit.cashOutMax: 50000});
      expect(role.cloudRow()['limits'], {'discountPct': 10.0, 'cashOutMax': 50000.0});
      expect(RolesRepository.limitsSummary(role.limits), 'descuento máximo 10 %, salida de caja máxima \$50000');
      await SupabaseService.instance.waitForPendingWrites();
    });

    test('el resumen dice qué se encendió y qué se apagó', () {
      expect(RolesRepository.changeSummary('Cajero', {Perm.sell, Perm.credit}, {Perm.sell, Perm.costs}),
          'Cambió los permisos de Cajero: +Ver costos; −Fiar');
    });
  });

  group('Pantalla Roles y permisos', () {
    // Solo el dueño: con 2 personas la app enciende sola la nube y las pruebas de
    // pantalla quedarían esperando la subida
    setUp(() async {
      final db = await appDb.database;
      await db.delete('business_members', where: 'id = ?', whereArgs: ['m-luis']);
    });

    Future<void> settle(WidgetTester tester, Finder until) async {
      for (var i = 0; i < 30 && until.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    for (final width in [360.0, 1200.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('se ve sin desbordes y guarda los cambios a ${width.toInt()} px en ${brightness.name}', (tester) async {
          tester.view.physicalSize = Size(width, 2600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.build(brightness),
            home: RolesScreen(business: business, canEdit: true),
          ));
          await settle(tester, find.text('Lo que puede hacer cada rol'));
          expect(find.text('Dueño'), findsWidgets);
          expect(tester.takeException(), isNull);

          // En el celular se elige el Cajero arriba; en el computador está su columna
          final costs = find.bySemanticsLabel(RegExp(r'^Cajero: Ver costos'));
          await tester.scrollUntilVisible(costs, 200, scrollable: find.byType(Scrollable).first);
          await tester.tap(costs);
          await tester.pump();
          expect(find.text('1 cambio sin guardar'), findsOneWidget);
          await tester.tap(find.text('Guardar'));
          await settle(tester, find.textContaining('cambio guardado'));
          expect(Permissions.can('CASHIER', Perm.costs), isTrue);
          expect(find.text('1 cambio sin guardar'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('quien no es el dueño solo puede leer', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: RolesScreen(business: business, canEdit: false),
      ));
      await settle(tester, find.text('Lo que puede hacer cada rol'));
      expect(find.text('Crear rol'), findsNothing);
      expect(find.textContaining('Solo el dueño puede cambiar los roles'), findsOneWidget);
      // Los límites se ven, pero sin Pro (y sin ser el dueño) no se editan
      expect(find.text('LÍMITES'), findsOneWidget);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.every((f) => f.enabled == false), isTrue);
      final switches = tester.widgetList<Switch>(find.byType(Switch));
      expect(switches.every((s) => s.onChanged == null), isTrue);
    });
  });
}
