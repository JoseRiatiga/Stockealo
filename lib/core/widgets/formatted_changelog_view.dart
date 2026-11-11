import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Muestra las novedades de una versión. Entiende Markdown básico (títulos `#`,
/// viñetas `-` y `1.`, `**negrita**`, `_cursiva_` y `código`) sin paquetes extra.
class FormattedChangelogView extends StatelessWidget {
  final String rawChangelog;

  const FormattedChangelogView({super.key, required this.rawChangelog});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lines = rawChangelog.split('\n');
    final baseStyle = AppText.body(context, color: c.inkMuted);
    final boldStyle = AppText.body(context, weight: FontWeight.w600, color: c.ink);
    final italicStyle = baseStyle.copyWith(fontStyle: FontStyle.italic);
    final codeStyle = AppText.mono(context, size: AppText.sizeSmall, color: c.ink).copyWith(backgroundColor: c.surfaceMuted);

    final widgets = <Widget>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: AppSpace.xs + 2));
        continue;
      }

      // Títulos (#, ##, ###)
      if (line.startsWith('#')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xs),
          child: Text(line.replaceAll(RegExp(r'^#+\s*'), ''), style: AppText.body(context, weight: FontWeight.w700)),
        ));
        continue;
      }

      // Viñetas numeradas (1. , 2. )
      final numberMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(line);
      if (numberMatch != null) {
        widgets.add(_item(
          context,
          leading: Text('${numberMatch.group(1)}.', style: AppText.body(context, weight: FontWeight.w700, color: c.accent)),
          spans: _spans(numberMatch.group(2)!.trim(), baseStyle, boldStyle, italicStyle, codeStyle),
        ));
        continue;
      }

      // Viñetas (- , * , • )
      if (line.startsWith('- ') || line.startsWith('* ') || line.startsWith('• ')) {
        widgets.add(_item(
          context,
          leading: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(width: 6, height: 6, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
          ),
          spans: _spans(line.substring(2).trim(), baseStyle, boldStyle, italicStyle, codeStyle),
        ));
        continue;
      }

      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text.rich(TextSpan(children: _spans(line, baseStyle, boldStyle, italicStyle, codeStyle))),
      ));
    }

    if (widgets.isEmpty) {
      widgets.add(Text('Mejoras de rendimiento y estabilidad.', style: baseStyle));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  Widget _item(BuildContext context, {required Widget leading, required List<InlineSpan> spans}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 20, child: leading),
            Expanded(child: Text.rich(TextSpan(children: spans))),
          ],
        ),
      );

  /// Convierte `**negrita**`, `_cursiva_` y `código` en partes de texto con su estilo
  List<InlineSpan> _spans(String text, TextStyle base, TextStyle bold, TextStyle italic, TextStyle code) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(\*\*(.*?)\*\*|`(.*?)`|_(.*?)_)');
    var last = 0;
    for (final m in regex.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      if (m.group(2) != null) {
        spans.add(TextSpan(text: m.group(2), style: bold));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(text: ' ${m.group(3)} ', style: code));
      } else if (m.group(4) != null) {
        spans.add(TextSpan(text: m.group(4), style: italic));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: base));
    return spans;
  }
}
