import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// En SQL, las comillas dobles son para nombres de columna. El SQLite del celular
/// acepta `role = "OWNER"` como texto, pero el de la web no: lo toma como una
/// columna que no existe y la consulta falla. Así se congelaba la web al crear un
/// negocio (0.16.3). Los textos van con comillas simples o, mejor, como parámetro.
void main() {
  test('ninguna consulta compara con un texto entre comillas dobles', () {
    final bad = RegExp(r'''(=|<>|!=|\bIN\s*\(|\bLIKE)\s*"[^"$]*"''', caseSensitive: false);
    final sqlHint = RegExp(r'\b(where|WHERE|SELECT|UPDATE|DELETE|AND|OR)\b');
    final found = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (bad.hasMatch(line) && sqlHint.hasMatch(line)) found.add('${file.path.replaceAll(r'\', '/')}:${i + 1}: ${line.trim()}');
      }
    }
    expect(found, isEmpty, reason: 'Usa comillas simples o un parámetro (?):\n${found.join('\n')}');
  });
}
