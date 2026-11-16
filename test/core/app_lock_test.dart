import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/security/app_lock.dart';
import 'package:stockealo/core/security/app_lock_gate.dart';
import 'package:stockealo/core/theme/app_theme.dart';

/// 0.16.0, fase 6: bloqueo con PIN o huella
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'lock-test';
  final appDb = AppDatabase.instance;
  final lock = AppLock.instance;

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_lock_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
    }
    await loader.load();
  });

  setUp(() async {
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    await appDb.database;
    lock.resetForTest();
  });

  tearDownAll(() async {
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('el PIN se guarda cifrado y se revisa', () async {
    expect(AppLock.validPin('12'), isFalse);
    expect(AppLock.validPin('1234'), isTrue);
    expect(AppLock.validPin('1234567'), isFalse);
    await lock.enable('4821');
    expect(await lock.isOn(), isTrue);
    expect(await appDb.getSetting('app_lock_pin_hash'), isNot(contains('4821')), reason: 'nunca tal cual');
    lock.locked.value = true;
    expect(await lock.check('0000'), isFalse);
    expect(lock.locked.value, isTrue);
    expect(await lock.check('4821'), isTrue);
    expect(lock.locked.value, isFalse);
    await lock.disable();
    expect(await lock.isOn(), isFalse);
    expect(await appDb.getSetting('app_lock_pin_hash'), isNull);
  });

  test('cinco intentos fallidos: espera 30 segundos, aunque después ponga el bueno', () async {
    await lock.enable('4821');
    for (var i = 0; i < AppLock.maxFails; i++) {
      expect(await lock.check('1111'), isFalse);
    }
    expect(lock.waitLeft, isNotNull);
    expect(await lock.check('4821'), isFalse, reason: 'mientras espera, nada entra');
  });

  test('vuelve a pedir el PIN solo si pasó el tiempo elegido', () async {
    await lock.enable('4821');
    await lock.setAfter(5);
    lock.onLeave();
    await lock.onReturn(now: DateTime.now().add(const Duration(minutes: 2)));
    expect(lock.locked.value, isFalse);
    lock.onLeave();
    await lock.onReturn(now: DateTime.now().add(const Duration(minutes: 6)));
    expect(lock.locked.value, isTrue);
    // Apagado: nunca bloquea
    lock.resetForTest();
    await lock.disable();
    lock.onLeave();
    await lock.onReturn(now: DateTime.now().add(const Duration(hours: 1)));
    expect(lock.locked.value, isFalse);
  });

  Future<void> pumpGate(WidgetTester tester, {required Future<void> Function() onUsePassword}) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: AppLockGate(title: 'Variedades Rosita', onUsePassword: onUsePassword, child: const Scaffold(body: Text('La app'))),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  testWidgets('la pantalla del PIN tapa la app y se abre con el PIN', (tester) async {
    await tester.runAsync(() => lock.enable('2580'));
    await pumpGate(tester, onUsePassword: () async {});
    expect(find.text('Escribe tu PIN'), findsOneWidget);
    expect(find.text('La app'), findsNothing);
    expect(tester.takeException(), isNull);
    for (final d in ['2', '5', '8', '0']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.text('La app'), findsOneWidget);
    expect(find.text('Escribe tu PIN'), findsNothing);
  });

  testWidgets('«¿Olvidaste tu PIN?» apaga el bloqueo y lleva a la contraseña', (tester) async {
    await tester.runAsync(() => lock.enable('2580'));
    var usedPassword = false;
    await pumpGate(tester, onUsePassword: () async => usedPassword = true);
    await tester.tap(find.text('¿Olvidaste tu PIN? Entra con tu contraseña'));
    // Borrar el PIN son varias escrituras en la base: en un equipo lento tarda más
    for (var i = 0; i < 60 && !usedPassword; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(usedPassword, isTrue);
    expect(await tester.runAsync(() => lock.isOn()), isFalse);
  });

  testWidgets('un PIN de 6 números se revisa al completarlo (los primeros no cuentan como fallos)', (tester) async {
    await tester.runAsync(() => lock.enable('258013'));
    await pumpGate(tester, onUsePassword: () async {});
    Future<void> type(String pin) async {
      for (final d in pin.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
    }

    // Dos intentos equivocados: antes contaban 3 fallos cada uno y bloqueaba 30 s
    await type('111111');
    await type('222222');
    expect(lock.waitLeft, isNull);
    await type('258013');
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.text('La app'), findsOneWidget);
  });
}
