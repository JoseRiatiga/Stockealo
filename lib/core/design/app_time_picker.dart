import 'package:flutter/material.dart';

/// Selector de hora de Stockealo: solo los números (sin reloj de agujas), con los colores de la app
/// (ver timePickerTheme en app_theme.dart) y los textos en español
Future<TimeOfDay?> showAppTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
  required String helpText,
  TimePickerEntryMode initialEntryMode = TimePickerEntryMode.inputOnly,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    helpText: helpText,
    initialEntryMode: initialEntryMode,
    cancelText: 'Cancelar',
    confirmText: 'Listo',
    hourLabelText: 'Hora',
    minuteLabelText: 'Minutos',
    errorInvalidText: 'Escribe una hora válida',
  );
}

/// Hora como la escribe la app: "9:00 a. m.", "5:30 p. m."
String formatAppTime(TimeOfDay time) {
  final h = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m ${time.period == DayPeriod.am ? 'a. m.' : 'p. m.'}';
}
