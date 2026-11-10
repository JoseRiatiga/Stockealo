import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/app_version.dart';
import 'package:stockealo/core/services/web_update_service.dart';

void main() {
  test('la constante de versión es igual a la de pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final value = line.substring('version:'.length).trim();
    expect('$kAppVersion+$kAppBuildNumber', value,
        reason: 'Al subir la versión en pubspec.yaml, cámbiala también en lib/core/app_version.dart');
  });

  group('versión nueva en la web', () {
    test('avisa solo si el número de compilación publicado es mayor', () {
      expect(WebUpdateService.isNewer({'version': '0.12.0', 'build_number': '37'}, currentBuild: 36), isTrue);
      expect(WebUpdateService.isNewer({'version': '0.11.0', 'build_number': '36'}, currentBuild: 36), isFalse);
      expect(WebUpdateService.isNewer({'version': '0.10.0', 'build_number': '30'}, currentBuild: 36), isFalse);
    });

    test('acepta el número como texto o como entero', () {
      expect(WebUpdateService.isNewer({'build_number': 40}, currentBuild: 36), isTrue);
    });

    test('un version.json raro no muestra aviso', () {
      expect(WebUpdateService.isNewer({}, currentBuild: 36), isFalse);
      expect(WebUpdateService.isNewer({'build_number': 'abc'}, currentBuild: 36), isFalse);
    });
  });
}
