import 'package:flutter/material.dart';

/// Un visualizador enriquecido de notas de versión (Changelog)
/// que interpreta Markdown básico (títulos, negritas, código y viñetas)
/// sin requerir dependencias externas y con diseño moderno.
class FormattedChangelogView extends StatelessWidget {
  final String rawChangelog;
  final bool isDark;

  const FormattedChangelogView({
    super.key,
    required this.rawChangelog,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final lines = rawChangelog.split('\n');
    final baseTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final boldTextColor = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
    final headerTextColor = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);

    final baseStyle = TextStyle(
      fontSize: 12.5,
      height: 1.45,
      color: baseTextColor,
    );

    final boldStyle = TextStyle(
      fontSize: 12.5,
      height: 1.45,
      fontWeight: FontWeight.bold,
      color: boldTextColor,
    );

    final codeStyle = TextStyle(
      fontSize: 11.5,
      fontFamily: 'monospace',
      fontWeight: FontWeight.w600,
      backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
      color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
    );

    final italicStyle = TextStyle(
      fontSize: 12.5,
      height: 1.45,
      fontStyle: FontStyle.italic,
      color: baseTextColor,
    );

    final List<Widget> widgets = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        continue;
      }

      // 1. Títulos Markdown (#, ##, ###)
      if (line.startsWith('#')) {
        final cleanTitle = line.replaceAll(RegExp(r'^#+\s*'), '');
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: headerTextColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    cleanTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: headerTextColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // 2. Viñetas numeradas (1. , 2. )
      final numberMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(line);
      if (numberMatch != null) {
        final numStr = numberMatch.group(1)!;
        final cleanLine = numberMatch.group(2)!.trim();
        final spans = _parseInlineSpans(cleanLine, baseStyle, boldStyle, italicStyle, codeStyle);

        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 2, right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    numStr,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(children: spans),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // 3. Viñetas (- , * , • )
      if (line.startsWith('- ') || line.startsWith('* ') || line.startsWith('• ')) {
        final cleanLine = line.substring(2).trim();
        final spans = _parseInlineSpans(cleanLine, baseStyle, boldStyle, italicStyle, codeStyle);

        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 5.5, right: 8),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(children: spans),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // 4. Párrafo normal con posibles negritas o código
      final spans = _parseInlineSpans(line, baseStyle, boldStyle, italicStyle, codeStyle);
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: RichText(
            text: TextSpan(children: spans),
          ),
        ),
      );
    }

    if (widgets.isEmpty) {
      widgets.add(
        Text(
          '• Mejoras continuas en rendimiento y estabilidad general.',
          style: baseStyle,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  /// Convierte patrones `**negrita**`, `_cursiva_` y `code` en Spans de texto formateados
  List<InlineSpan> _parseInlineSpans(
    String text,
    TextStyle baseStyle,
    TextStyle boldStyle,
    TextStyle italicStyle,
    TextStyle codeStyle,
  ) {
    final List<InlineSpan> spans = [];
    final regex = RegExp(r'(\*\*(.*?)\*\*|`(.*?)`|_(.*?)_)');
    int lastIndex = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: baseStyle,
        ));
      }

      if (match.group(2) != null) {
        // Encontró **negrita**
        spans.add(TextSpan(
          text: match.group(2),
          style: boldStyle,
        ));
      } else if (match.group(3) != null) {
        // Encontró `codigo`
        spans.add(TextSpan(
          text: ' ${match.group(3)} ',
          style: codeStyle,
        ));
      } else if (match.group(4) != null) {
        // Encontró _cursiva_
        spans.add(TextSpan(
          text: match.group(4),
          style: italicStyle,
        ));
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: baseStyle,
      ));
    }

    return spans;
  }
}
