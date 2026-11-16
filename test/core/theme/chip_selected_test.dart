import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';

/// 0.16.2: un chip elegido se lee (letra clara sobre fondo oscuro), en claro y oscuro
void main() {
  for (final brightness in Brightness.values) {
    testWidgets('el chip elegido se lee (${brightness.name})', (tester) async {
      final theme = AppTheme.build(brightness);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Row(children: [
            FilterChip(label: const Text('L'), selected: true, onSelected: (_) {}),
            FilterChip(label: const Text('D'), selected: false, onSelected: (_) {}),
          ]),
        ),
      ));
      Color colorOf(String text) {
        final span = tester.renderObject<RenderParagraph>(find.text(text)).text;
        Color? color = span.style?.color;
        span.visitChildren((s) {
          color ??= s.style?.color;
          return color == null;
        });
        return color ?? theme.colorScheme.onSurface;
      }
      final selectedBg = theme.chipTheme.selectedColor!;
      expect(colorOf('L'), isNot(selectedBg), reason: 'la letra no puede ser del color del fondo');
      expect(colorOf('L'), isNot(colorOf('D')));
    });
  }
}
