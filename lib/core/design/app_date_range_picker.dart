import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_tokens.dart';
import '../utils/business_clock.dart';
import 'app_dialog.dart';

/// Elegir de qué día a qué día (0.16.8, #25): una ventana pequeña con atajos y, si
/// hace falta, el calendario en una ventana, no en toda la pantalla. La usan
/// Promociones (fechas que vienen: [ahead] = true) y Ventas (fechas que pasaron).
/// Devuelve días completos: el fin cuenta todo ese día.
Future<DateTimeRange?> showAppDateRangePicker(
  BuildContext context, {
  DateTimeRange? initial,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = '¿De qué día a qué día?',
  bool ahead = false,
}) {
  final today = _day(appNow());
  final shortcuts = ahead ? _ahead(today) : _past(today);
  DateTime clamp(DateTime d) => d.isBefore(firstDate) ? _day(firstDate) : (d.isAfter(lastDate) ? _day(lastDate) : d);
  return AppDialog.show<DateTimeRange>(
    context: context,
    icon: Icons.date_range_outlined,
    title: title,
    content: Builder(builder: (ctx) {
      final c = ctx.colors;
      final fmt = DateFormat("d 'de' MMM", 'es_CO');
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final (label, range) in shortcuts)
                ActionChip(
                  label: Text(label),
                  onPressed: () => Navigator.pop(ctx, DateTimeRange(start: clamp(range.start), end: clamp(range.end))),
                ),
            ],
          ),
          if (initial != null) ...[
            const SizedBox(height: AppSpace.md),
            Text('Ahora: del ${fmt.format(initial.start)} al ${fmt.format(initial.end)}',
                style: AppText.small(ctx, color: c.inkMuted)),
          ],
          const SizedBox(height: AppSpace.md),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: const Text('Elegir en el calendario'),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: ctx,
                firstDate: firstDate,
                lastDate: lastDate,
                initialDateRange: initial == null ? null : DateTimeRange(start: clamp(_day(initial.start)), end: clamp(_day(initial.end))),
                helpText: title,
                saveText: 'Listo',
                cancelText: 'Cancelar',
                // En una ventana del tamaño de un celular, no en toda la pantalla
                builder: (_, child) => Center(
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620), child: child),
                ),
              );
              if (picked != null && ctx.mounted) Navigator.pop(ctx, picked);
            },
          ),
        ],
      );
    }),
    actions: [
      Builder(builder: (ctx) => TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))),
    ],
  );
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Lunes = 1 … domingo = 7
List<(String, DateTimeRange)> _ahead(DateTime today) {
  final sunday = today.add(Duration(days: 7 - today.weekday));
  final saturday = today.weekday >= DateTime.saturday ? today : today.add(Duration(days: DateTime.saturday - today.weekday));
  final monthEnd = DateTime(today.year, today.month + 1, 0);
  return [
    ('Hoy', DateTimeRange(start: today, end: today)),
    ('Esta semana', DateTimeRange(start: today, end: sunday)),
    ('Fin de semana', DateTimeRange(start: saturday, end: sunday)),
    ('Próximos 7 días', DateTimeRange(start: today, end: today.add(const Duration(days: 6)))),
    ('Este mes', DateTimeRange(start: today, end: monthEnd)),
  ];
}

List<(String, DateTimeRange)> _past(DateTime today) {
  final yesterday = today.subtract(const Duration(days: 1));
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final lastMonthEnd = DateTime(today.year, today.month, 0);
  return [
    ('Hoy', DateTimeRange(start: today, end: today)),
    ('Ayer', DateTimeRange(start: yesterday, end: yesterday)),
    ('Esta semana', DateTimeRange(start: monday, end: today)),
    ('Últimos 7 días', DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today)),
    ('Este mes', DateTimeRange(start: DateTime(today.year, today.month), end: today)),
    ('Mes pasado', DateTimeRange(start: DateTime(lastMonthEnd.year, lastMonthEnd.month), end: lastMonthEnd)),
  ];
}
