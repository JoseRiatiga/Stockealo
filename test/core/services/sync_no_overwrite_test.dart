import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/utils/app_clipboard.dart';

/// 0.18.8: lo que encontró el dueño (28 nov) y los dos errores del panel.
void main() {
  group('la subida completa no pisa lo que ya está en la nube', () {
    // Lee el código de syncToCloud: cada subida de estas tablas solo crea lo que falta
    // (ignoreDuplicates). Si alguien la vuelve a cambiar, esta prueba falla.
    final source = File('lib/core/services/supabase_service.dart').readAsStringSync();
    final start = source.indexOf('Future<SyncResult> syncToCloud()');
    final end = source.indexOf('Future<SyncResult> syncFromCloud(', start);
    final body = source.substring(start, end);

    for (final table in ['business_members', 'sales', 'categories', 'businesses']) {
      test('$table: solo crea lo que falta', () {
        final calls = RegExp("(\\.from\\('$table'\\)\\.upsert\\(|_upsertGrouped\\(client!, '$table', )([^;]*);")
            .allMatches(body)
            .map((m) => m.group(0)!)
            .toList();
        expect(calls, isNotEmpty, reason: 'no se encontró la subida de $table');
        for (final call in calls) {
          // Negocios: solo los que faltaban se suben completos (recién creados solo con
          // nombre y tipo), salvo la primera subida después de encender la nube
          final businessesOk = table == 'businesses' && call.contains('toSend');
          expect(call.contains('ignoreDuplicates: onlyMissing') || businessesOk, isTrue,
              reason: 'esta subida de $table pisaría la nube: $call');
        }
      });
    }

    test('los negocios que ya están en la nube no se vuelven a subir', () {
      expect(body, contains("_existingIds(client!, 'businesses', ids)"));
      // Ya en la nube: solo con la copia local pendiente. Faltantes: solo los propios
      expect(body, contains("(pushLocal && inCloud.contains(b['id']))"));
      expect(body, contains("(!inCloud.contains(b['id']) && ownedIds.contains(b['id']))"));
    });

    test('solo la primera subida después de encender la nube manda la copia del equipo', () {
      expect(body, contains('final onlyMissing = !pushLocal;'));
      // Se borra la marca solo si la subida terminó bien
      final clear = body.indexOf('setSetting(pushLocalOnceKey, null)');
      expect(clear, greaterThan(body.indexOf("'sales'")));
      expect(body.indexOf('businessesCount: localBusinesses.length'), greaterThan(clear));
      // La marca se pone al pasar de apagada a encendida
      final enable = source.substring(source.indexOf('Future<void> setCloudSyncEnabled('));
      expect(enable.substring(0, 700), contains('if (enabled && !wasOn) await AppDatabase.instance.setSetting(pushLocalOnceKey'));
    });

    test('«Sincronizar ahora» sube sin pisar y después baja', () {
      final profile = File('lib/features/profile/presentation/screens/profile_screen.dart').readAsStringSync();
      final manual = profile.substring(profile.indexOf('Future<void> _runManualSync()'));
      final up = manual.indexOf('syncToCloud()');
      final down = manual.indexOf('syncFromCloud(');
      expect(up, greaterThanOrEqualTo(0));
      expect(down, greaterThan(up), reason: 'después de subir hay que bajar lo de la nube');
    });
  });

  group('copiar', () {
    test('todos los botones Copiar usan AppClipboard', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.replaceAll('\\', '/').endsWith('core/utils/app_clipboard.dart')) continue;
        if (f.readAsStringSync().contains('Clipboard.setData(')) offenders.add(f.path);
      }
      expect(offenders, isEmpty, reason: 'usa AppClipboard.copy, que avisa si el navegador no deja copiar');
    });

    Future<void> pump(WidgetTester tester, {required bool fail}) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData' && fail) {
          throw PlatformException(code: 'copy_fail', message: 'Clipboard.setData failed.');
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AppClipboard.copy(context, 'STK-123', message: 'Código copiado.'),
              child: const Text('Copiar'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Copiar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('si el navegador no deja copiar, avisa y no lanza error', (tester) async {
      await pump(tester, fail: true);
      expect(tester.takeException(), isNull);
      expect(find.text(AppClipboard.failedMessage), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('si copia, dice que copió', (tester) async {
      await pump(tester, fail: false);
      expect(find.text('Código copiado.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
