import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0.18.7: en el computador la rueda del mouse solo movía la franja del centro en
/// varias pantallas (Traslados, producto, panel). La causa siempre era la misma:
/// una lista vertical metida dentro de una columna de ancho fijo. La lista debe
/// ocupar todo el ancho y llevar el relleno de los costados ([ContentListView] o
/// [ContentWidth.gutter] en su padding).
///
/// Este candado lee el código: falla si una lista vertical queda pocas líneas
/// debajo de un ancho máximo. Las ventanas y hojas (AppDialog, showDialog,
/// bottom sheets, listas con shrinkWrap) quedan por fuera: no ocupan la pantalla.
void main() {
  test('ninguna lista vertical queda dentro de una columna de ancho fijo', () {
    final limit = RegExp(r'BoxConstraints\(maxWidth:|ContentWidth\(');
    final scroll = RegExp(r'\b(ListView|SingleChildScrollView|CustomScrollView|GridView)\b');
    final popup = RegExp(r'AppDialog|showDialog|Dialog\(|BottomSheet|showModalBottomSheet|PopupMenu');
    final problems = <String>[];

    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!limit.hasMatch(lines[i])) continue;
        final before = lines.sublist((i - 12).clamp(0, lines.length), i).join('\n');
        if (popup.hasMatch(before) || popup.hasMatch(lines[i])) continue;
        final end = (i + 8).clamp(0, lines.length);
        for (var j = i + 1; j < end; j++) {
          if (!scroll.hasMatch(lines[j])) continue;
          final next = lines.sublist(j, (j + 3).clamp(0, lines.length)).join(' ');
          // Horizontal, o una lista que se encoge a su contenido (hojas): no aplica
          if (next.contains('Axis.horizontal') || next.contains('shrinkWrap: true')) continue;
          problems.add('${file.path.replaceAll('\\', '/')}:${i + 1}');
          break;
        }
      }
    }

    expect(problems, isEmpty,
        reason: 'Lista dentro de un ancho máximo: usa ContentListView o pon ContentWidth.gutter en el padding');
  });
}
