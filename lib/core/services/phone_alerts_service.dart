import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../features/business/data/business_repository.dart';
import '../../features/business/models/business.dart';
import '../../features/customers/data/customer_repository.dart';
import '../../features/customers/data/debt_reminder.dart';
import '../../features/customers/data/debt_reminder_schedule.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../features/products/data/product_repository.dart';
import '../database/app_database.dart';
import '../utils/currency_formatter.dart';
import 'data_events.dart';

/// Avisos en la barra del celular, aunque la app esté cerrada:
/// • stock bajo: cuando un producto llega a su mínimo después de una venta
/// • resumen del día: a la hora elegida, con las ventas del día en este celular
/// • cobro de fiados (Pro): "Hoy toca cobrarle a X", con un botón que abre WhatsApp
///   con el mensaje listo (el dueño lo envía; nada sale solo)
///
/// Los dos vienen apagados; al activarlos Android 13+ pide permiso. Todo se calcula
/// con los datos del celular, sin servidor.
class PhoneAlertsService {
  PhoneAlertsService._();
  static final PhoneAlertsService instance = PhoneAlertsService._();

  static const stockKey = 'alerts_stock';
  static const summaryKey = 'alerts_summary';
  static const summaryHourKey = 'alerts_summary_hour';
  static const _notifiedKey = 'alerts_stock_notified';
  static const defaultSummaryHour = 20;

  static const _summaryId = 1;
  static const _stockChannel = AndroidNotificationDetails(
    'stock_alerts',
    'Stock bajo',
    channelDescription: 'Cuando un producto llega a su mínimo',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _summaryChannel = AndroidNotificationDetails(
    'daily_summary',
    'Resumen del día',
    channelDescription: 'Cómo te fue en el día, a la hora que elijas',
  );

  static const _openWhatsAppAction = 'open_whatsapp';
  static const _debtChannel = AndroidNotificationDetails(
    'debt_reminders',
    'Cobro de fiados',
    channelDescription: 'Recordatorios programados para cobrarle a tus clientes',
    importance: Importance.high,
    priority: Priority.high,
    actions: [AndroidNotificationAction(_openWhatsAppAction, 'Abrir WhatsApp', showsUserInterface: true)],
  );

  /// Avisos que se dejan programados por cliente; se completan al abrir la app
  static const debtOccurrences = 4;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Solo Android por ahora (la app no se publica en iOS y en la web no hay avisos del sistema)
  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    if (!isSupported || _ready) return;
    try {
      tz_data.initializeTimeZones();
      await _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notification')),
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
      _ready = true;
      DataEvents.instance.salesVersion.addListener(_onSalesChanged);
      // La app se abrió tocando un aviso de cobro
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) _onNotificationResponse(response);
    } catch (e) {
      debugPrint('Avisos: no se pudieron preparar: $e');
    }
  }

  void _onSalesChanged() {
    checkLowStock();
    refreshDailySummary();
    refreshDebtReminders();
  }

  // ---------------------------------------------------------------------------
  // Preferencias (por cuenta)

  Future<bool> _flag(String key) async => await AppDatabase.instance.getSetting(key) == '1';

  Future<bool> stockAlertsEnabled() => _flag(stockKey);
  Future<bool> summaryEnabled() => _flag(summaryKey);

  Future<int> summaryHour() async =>
      int.tryParse(await AppDatabase.instance.getSetting(summaryHourKey) ?? '') ?? defaultSummaryHour;

  /// Pide el permiso del sistema si hace falta. Devuelve false si el usuario lo negó.
  Future<bool> ensurePermission() async {
    await init();
    if (!_ready) return false;
    if (await _android?.areNotificationsEnabled() == true) return true;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  Future<bool> setStockAlerts(bool value) async {
    if (value && !await ensurePermission()) return false;
    await AppDatabase.instance.setSetting(stockKey, value ? '1' : '0');
    if (value) {
      // Lo que ya está bajo no se avisa de golpe: solo lo que baje de aquí en adelante
      await _saveNotified(await _lowStockIds());
    }
    return true;
  }

  Future<bool> setSummary(bool value) async {
    if (value && !await ensurePermission()) return false;
    await AppDatabase.instance.setSetting(summaryKey, value ? '1' : '0');
    await refreshDailySummary();
    return true;
  }

  Future<void> setSummaryHour(int hour) async {
    await AppDatabase.instance.setSetting(summaryHourKey, '$hour');
    await refreshDailySummary();
  }

  // ---------------------------------------------------------------------------
  // Stock bajo

  Business? get _business => BusinessRepository.instance.currentActiveBusiness;

  Future<Map<String, String>> _lowStockIds() async {
    final business = _business;
    if (business == null) return {};
    final products = await ProductRepository.instance.getAllProducts(business.id);
    return {for (final p in products.where((p) => p.stock <= p.minStock)) p.id: p.name};
  }

  Future<Set<String>> _loadNotified() async {
    final raw = await AppDatabase.instance.getSetting(_notifiedKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveNotified(Map<String, String> low) =>
      AppDatabase.instance.setSetting(_notifiedKey, jsonEncode(low.keys.toList()));

  /// Avisa de los productos que acaban de llegar a su mínimo. Un producto se vuelve
  /// a avisar solo después de reponerse por encima del mínimo.
  Future<void> checkLowStock() async {
    if (!_ready) return;
    try {
      if (!await stockAlertsEnabled()) return;
      final business = _business;
      if (business == null) return;
      final products = await ProductRepository.instance.getAllProducts(business.id);
      final low = {for (final p in products.where((p) => p.stock <= p.minStock)) p.id: p};
      final notified = await _loadNotified();
      final fresh = low.keys.where((id) => !notified.contains(id)).toList();

      if (fresh.length == 1) {
        final p = low[fresh.first]!;
        await _plugin.show(
          p.id.hashCode & 0x7fffffff,
          p.stock <= 0 ? '${p.name} se agotó' : 'Quedan pocas unidades de ${p.name}',
          p.stock <= 0
              ? 'Repónlo para no perder ventas en ${business.name}.'
              : 'Quedan ${p.stock} y tu mínimo es ${p.minStock}.',
          const NotificationDetails(android: _stockChannel),
        );
      } else if (fresh.length > 1) {
        final names = fresh.take(3).map((id) => low[id]!.name).join(', ');
        await _plugin.show(
          business.id.hashCode & 0x7fffffff,
          '${fresh.length} productos por reponer',
          fresh.length > 3 ? '$names y ${fresh.length - 3} más.' : '$names.',
          const NotificationDetails(android: _stockChannel),
        );
      }
      await _saveNotified({for (final e in low.entries) e.key: e.value.name});
    } catch (e) {
      debugPrint('Avisos de stock: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Resumen del día

  /// Texto del resumen con lo registrado hoy en este celular
  @visibleForTesting
  static String summaryText({
    required int salesCount,
    required double total,
    required double profit,
    required int toRestock,
    required String currency,
  }) {
    String money(num v) => CurrencyFormatter.formatIn(v, currency);
    final sales = salesCount == 0
        ? 'Hoy no registraste ventas.'
        : 'Hoy: $salesCount ${salesCount == 1 ? 'venta' : 'ventas'} por ${money(total)}, ganancia ${money(profit)}.';
    final restock = switch (toRestock) {
      0 => '',
      1 => ' 1 producto por reponer.',
      _ => ' $toRestock productos por reponer.',
    };
    return '$sales$restock';
  }

  /// Programa (o quita) el aviso del resumen. Se vuelve a calcular con cada venta y al
  /// abrir la app, así el aviso de la noche lleva las cifras del día.
  Future<void> refreshDailySummary({DateTime? now}) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_summaryId);
      if (!await summaryEnabled()) return;
      final business = _business;
      if (business == null) return;

      final at = now ?? DateTime.now();
      final hour = await summaryHour();
      var when = DateTime(at.year, at.month, at.day, hour);
      String title;
      String body;
      if (when.isAfter(at)) {
        final s = await DashboardRepository.instance.getDashboardSummary(business.id, period: 'today');
        title = 'Resumen de hoy · ${business.name}';
        body = summaryText(
          salesCount: (s['periodCount'] as num?)?.toInt() ?? 0,
          total: (s['periodTotal'] as num?)?.toDouble() ?? 0,
          profit: (s['periodProfit'] as num?)?.toDouble() ?? 0,
          toRestock: ((s['outOfStock'] as num?)?.toInt() ?? 0) + ((s['lowStock'] as num?)?.toInt() ?? 0),
          currency: business.currency,
        );
      } else {
        // Ya pasó la hora de hoy: queda uno para mañana, que se completa al usar la app
        when = when.add(const Duration(days: 1));
        title = 'Resumen del día · ${business.name}';
        body = 'Toca para ver cómo te fue hoy.';
      }

      await _plugin.zonedSchedule(
        _summaryId,
        title,
        body,
        tz.TZDateTime.from(when.toUtc(), tz.UTC),
        const NotificationDetails(android: _summaryChannel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Resumen del día: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Cobro de fiados (Stockealo Pro)

  /// Ids de los avisos de un cliente: uno por cada próxima fecha
  @visibleForTesting
  static List<int> debtNotificationIds(String customerId) {
    final base = 0x10000000 + ((customerId.hashCode & 0x00ffffff) << 2);
    return [for (var i = 0; i < debtOccurrences; i++) base + i];
  }

  Future<void> _cancelDebt(String customerId) async {
    for (final id in debtNotificationIds(customerId)) {
      await _plugin.cancel(id);
    }
  }

  /// Guarda el recordatorio de un cliente y lo programa. false si no hay permiso.
  Future<bool> setDebtReminder(DebtReminderSchedule schedule) async {
    if (!await ensurePermission()) return false;
    await DebtReminderStore.instance.save(schedule);
    await _scheduleDebt(schedule);
    return true;
  }

  Future<void> removeDebtReminder(String customerId) async {
    await DebtReminderStore.instance.remove(customerId);
    if (_ready) await _cancelDebt(customerId);
  }

  /// Vuelve a programar todos los recordatorios con la deuda de hoy. Se llama al
  /// abrir la app, con cada venta y con cada abono.
  Future<void> refreshDebtReminders() async {
    if (!_ready) return;
    try {
      final all = await DebtReminderStore.instance.load();
      for (final schedule in all.values) {
        await _scheduleDebt(schedule);
      }
    } catch (e) {
      debugPrint('Recordatorios de cobro: $e');
    }
  }

  Future<void> _scheduleDebt(DebtReminderSchedule schedule) async {
    if (!_ready) return;
    await _cancelDebt(schedule.customerId);
    final customer = await CustomerRepository.instance.getCustomerById(schedule.customerId);
    if (customer == null) {
      // El cliente ya no existe
      await DebtReminderStore.instance.remove(schedule.customerId);
      return;
    }
    // Sin deuda no hay nada que cobrar; el recordatorio queda guardado por si vuelve a fiar
    if (!customer.hasDebt) return;

    final db = await AppDatabase.instance.database;
    final rows = await db.query('businesses', columns: ['currency'], where: 'id = ?', whereArgs: [schedule.businessId]);
    final currency = rows.isEmpty ? 'COP' : (rows.first['currency'] as String? ?? 'COP');
    final payload = jsonEncode({'type': 'debt', 'customerId': customer.id, 'businessId': schedule.businessId});
    final ids = debtNotificationIds(customer.id);
    final dates = schedule.nextOccurrences(DateTime.now(), count: debtOccurrences);
    for (var i = 0; i < dates.length; i++) {
      await _plugin.zonedSchedule(
        ids[i],
        DebtReminderSchedule.notificationTitle(customer.name),
        DebtReminderSchedule.notificationBody(customer.debtBalance, currency),
        tz.TZDateTime.from(dates[i].toUtc(), tz.UTC),
        const NotificationDetails(android: _debtChannel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    }
  }

  /// Al tocar el aviso (o su botón) se abre WhatsApp con el recordatorio escrito
  Future<void> _onNotificationResponse(NotificationResponse response) async {
    try {
      final raw = response.payload;
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['type'] != 'debt') return;
      final customer = await CustomerRepository.instance.getCustomerById(data['customerId'] as String);
      if (customer == null || !customer.hasDebt) return;
      final db = await AppDatabase.instance.database;
      final rows = await db.query('businesses', columns: ['name'], where: 'id = ?', whereArgs: [customer.businessId]);
      await DebtReminder.send(
        customerName: customer.name,
        debtAmount: customer.debtBalance,
        businessName: rows.isEmpty ? (_business?.name ?? 'Mi negocio') : rows.first['name'] as String,
        phone: customer.phone,
      );
    } catch (e) {
      debugPrint('Aviso de cobro: $e');
    }
  }
}
