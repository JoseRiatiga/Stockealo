import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// Paginación única para todas las listas. Se usa dos veces por lista con la misma
/// página: compacta arriba (junto al título) y completa abajo. Si todo cabe en una
/// página no se muestra.
///
/// Quien la usa debe volver la pantalla arriba al cambiar de página desde abajo.
class AppPagination extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  /// Versión pequeña para la parte de arriba: "‹ 1 / 3 ›"
  final bool compact;

  const AppPagination({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    this.compact = false,
  });

  bool get _hasPrevious => currentPage > 1;
  bool get _hasNext => currentPage < totalPages;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();
    final c = context.colors;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _arrow(context, Icons.chevron_left_rounded, 'Página anterior', _hasPrevious ? currentPage - 1 : null),
          Text('$currentPage / $totalPages', style: AppText.amount(context, size: 13, weight: FontWeight.w600, color: c.inkMuted)),
          _arrow(context, Icons.chevron_right_rounded, 'Página siguiente', _hasNext ? currentPage + 1 : null),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _hasPrevious ? () => onPageChanged(currentPage - 1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text('Anterior'),
            ),
          ),
        ),
        Text('Página $currentPage de $totalPages', style: TextStyle(fontSize: 13, color: c.inkMuted)),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _hasNext ? () => onPageChanged(currentPage + 1) : null,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text('Siguiente'), SizedBox(width: 4), Icon(Icons.chevron_right_rounded)],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _arrow(BuildContext context, IconData icon, String tooltip, int? target) {
    final c = context.colors;
    return IconButton(
      onPressed: target == null ? null : () => onPageChanged(target),
      icon: Icon(icon),
      tooltip: tooltip,
      color: c.ink,
      disabledColor: c.lineStrong,
      visualDensity: VisualDensity.compact,
    );
  }
}
