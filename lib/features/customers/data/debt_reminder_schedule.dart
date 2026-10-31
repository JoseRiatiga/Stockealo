import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/currency_formatter.dart';

/// Recordatorio programado de cobro (Stockealo Pro): cada [everyDays] días, a la
/// hora elegida, el celular avisa "Hoy toca cobrarle a X". Nunca se envía nada
/// solo: el aviso abre WhatsApp con el mensaje listo y el dueño decide.
class DebtReminderSchedule {
  /// Frecuencias que se ofrecen, en días
  static const frequencies = [1, 3, 7, 15, 30];

  final String customerId;
  final String businessId;
  final int everyDays;
  final int hour;
  final int minute;

  /// Día desde el que se cuentan los periodos
  final DateTime startsOn;

  const DebtReminderSchedule({
    required this.customerId,
    required this.businessId,
    required this.everyDays,
    required this.hour,
    required this.minute,
    required this.startsOn,
  });

  Map<String, dynamic> toJson() => {
        'customerId': customerId,
        'businessId': businessId,
        'everyDays': everyDays,
        'hour': hour,
        'minute': minute,
        'startsOn': startsOn.toIso8601String(),
      };

  static DebtReminderSchedule? fromJson(Map<String, dynamic> j) {
    final customerId = j['customerId'] as String?;
    final businessId = j['businessId'] as String?;
    final startsOn = DateTime.tryParse(j['startsOn'] as String? ?? '');
    if (customerId == null || businessId == null || startsOn == null) return null;
    final every = (j['everyDays'] as num?)?.toInt() ?? 7;
    return DebtReminderSchedule(
      customerId: customerId,
      businessId: businessId,
      everyDays: every < 1 ? 7 : every,
      hour: ((j['hour'] as num?)?.toInt() ?? 9).clamp(0, 23),
      minute: ((j['minute'] as num?)?.toInt() ?? 0).clamp(0, 59),
      startsOn: startsOn,
    );
  }

  /// Las próximas [count] fechas del aviso, todas después de [now]
  List<DateTime> nextOccurrences(DateTime now, {int count = 4}) {
    var when = DateTime(startsOn.year, startsOn.month, startsOn.day, hour, minute);
    if (!when.isAfter(now)) {
      // Salta los periodos que ya pasaron sin recorrerlos uno por uno
      final days = DateTime(now.year, now.month, now.day).difference(DateTime(when.year, when.month, when.day)).inDays;
      final periods = days ~/ everyDays;
      when = DateTime(when.year, when.month, when.day + periods * everyDays, hour, minute);
      while (!when.isAfter(now)) {
        when = DateTime(when.year, when.month, when.day + everyDays, hour, minute);
      }
    }
    return [
      for (var i = 0; i < count; i++) DateTime(when.year, when.month, when.day + i * everyDays, hour, minute),
    ];
  }

  String get frequencyLabel => frequencyText(everyDays);

  static String frequencyText(int days) => switch (days) {
        1 => 'Todos los días',
        7 => 'Cada semana',
        15 => 'Cada 15 días',
        30 => 'Cada mes',
        _ => 'Cada $days días',
      };

  static String notificationTitle(String customerName) => 'Hoy toca cobrarle a $customerName';

  static String notificationBody(double debt, String currency) =>
      'Debe ${CurrencyFormatter.formatIn(debt, currency)}. Toca para enviarle el recordatorio por WhatsApp.';
}

/// Dónde se guardan los recordatorios (app_settings de la cuenta)
class DebtReminderStore {
  DebtReminderStore._();
  static final DebtReminderStore instance = DebtReminderStore._();

  static const key = 'debt_reminders';

  Future<Map<String, DebtReminderSchedule>> load() async {
    return decode(await AppDatabase.instance.getSetting(key));
  }

  @visibleForTesting
  static Map<String, DebtReminderSchedule> decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return {
        for (final s in list.map(DebtReminderSchedule.fromJson).whereType<DebtReminderSchedule>()) s.customerId: s,
      };
    } catch (_) {
      return {};
    }
  }

  Future<DebtReminderSchedule?> forCustomer(String customerId) async => (await load())[customerId];

  Future<void> save(DebtReminderSchedule schedule) async {
    final all = await load();
    all[schedule.customerId] = schedule;
    await _write(all);
  }

  Future<void> remove(String customerId) async {
    final all = await load();
    if (all.remove(customerId) != null) await _write(all);
  }

  Future<void> _write(Map<String, DebtReminderSchedule> all) =>
      AppDatabase.instance.setSetting(key, jsonEncode([for (final s in all.values) s.toJson()]));
}
