import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/countries.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../business/data/business_repository.dart';
import '../../customers/data/customer_repository.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../products/data/product_repository.dart';

/// Cuándo usa Stocky la IA para lo que sus reglas no entienden
enum StockyAiMode {
  /// Solo reglas: nunca gasta preguntas
  off,

  /// Responde con reglas y ofrece un botón para preguntarle a la IA (por defecto)
  ask,

  /// Pregunta a la IA sin preguntar primero
  auto;

  String get label => switch (this) {
        off => 'Apagada',
        ask => 'Preguntar antes',
        auto => 'Automática',
      };

  String get description => switch (this) {
        off => 'Stocky solo responde lo que ya sabe. No gasta preguntas.',
        ask => 'Si Stocky no entiende, te ofrece preguntarle a la IA.',
        auto => 'Si Stocky no entiende, le pregunta a la IA directamente.',
      };
}

/// Resultado de una pregunta a la IA
class StockyAiResult {
  final String? answer;

  /// Preguntas que le quedan hoy a la cuenta (null si no se sabe)
  final int? remaining;
  final int? limit;

  /// Código de error del servidor: daily_limit, global_limit, ai_unavailable, offline…
  final String? error;
  final bool cached;

  const StockyAiResult({this.answer, this.remaining, this.limit, this.error, this.cached = false});

  bool get ok => answer != null;

  /// Mensaje para el usuario cuando no hubo respuesta
  String get errorMessage => switch (error) {
        'daily_limit' => 'Ya usaste tus ${limit ?? ''} preguntas a la IA de hoy. Mañana tienes más; mientras tanto respondo con lo que ya sé.',
        'global_limit' => 'La IA está muy ocupada hoy. Vuelve a intentarlo mañana; mientras tanto respondo con lo que ya sé.',
        'question_too_long' => 'Tu pregunta es muy larga. Intenta resumirla en una o dos frases.',
        'offline' => 'Necesitas conexión a internet para preguntarle a la IA.',
        'not_authenticated' => 'Inicia sesión de nuevo para usar la IA.',
        _ => 'La IA no está disponible en este momento. Inténtalo en un rato.',
      };
}

/// Puente con la Edge Function `stocky-chat`. El límite diario lo controla el servidor;
/// aquí solo se arma el contexto (cifras ya calculadas, sin datos de clientes) y se
/// guarda el modo elegido por el usuario.
class StockyAiService {
  StockyAiService._();
  static final StockyAiService instance = StockyAiService._();

  static const modeKey = 'stocky_ai_mode';
  static const maxQuestionLength = 300;

  /// Modo actual; se escucha desde el chat para refrescar el interruptor
  final mode = ValueNotifier<StockyAiMode>(StockyAiMode.ask);

  /// Últimas preguntas restantes conocidas (para el texto del botón)
  final remaining = ValueNotifier<int?>(null);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final saved = await AppDatabase.instance.getSetting(modeKey);
      mode.value = StockyAiMode.values.firstWhere((m) => m.name == saved, orElse: () => StockyAiMode.ask);
    } catch (_) {}
  }

  Future<void> setMode(StockyAiMode value) async {
    mode.value = value;
    try {
      await AppDatabase.instance.setSetting(modeKey, value.name);
    } catch (_) {}
  }

  /// Consulta cuántas preguntas quedan hoy, sin gastar ninguna
  /// Con [businessId] el servidor aplica el límite de Pro si ese negocio lo tiene
  Future<void> refreshStatus([String? businessId]) async {
    final client = SupabaseService.instance.client;
    if (client == null) return;
    businessId ??= BusinessRepository.instance.currentActiveBusiness?.id;
    try {
      final res = await client.functions.invoke('stocky-chat', body: {'action': 'status', 'business_id': businessId});
      final data = res.data;
      if (data is Map && data['remaining'] is num) remaining.value = (data['remaining'] as num).toInt();
    } catch (e) {
      debugPrint('Stocky IA: no se pudo leer el cupo: $e');
    }
  }

  Future<StockyAiResult> ask(String question, String businessId) async {
    final client = SupabaseService.instance.client;
    if (client == null) return const StockyAiResult(error: 'offline');
    final trimmed = question.trim();
    if (trimmed.length > maxQuestionLength) return const StockyAiResult(error: 'question_too_long');

    try {
      final context = await buildContext(businessId);
      final res = await client.functions.invoke(
        'stocky-chat',
        body: {'action': 'ask', 'business_id': businessId, 'question': trimmed, 'context': context},
      );
      return _parse(res.data);
    } on FunctionException catch (e) {
      final result = _parse(e.details);
      return result.error != null ? result : const StockyAiResult(error: 'ai_unavailable');
    } catch (e) {
      debugPrint('Stocky IA: $e');
      return const StockyAiResult(error: 'offline');
    }
  }

  StockyAiResult _parse(Object? data) {
    if (data is! Map) return const StockyAiResult(error: 'ai_unavailable');
    final left = data['remaining'] is num ? (data['remaining'] as num).toInt() : null;
    if (left != null) remaining.value = left;
    final answer = data['answer'];
    return StockyAiResult(
      answer: answer is String && answer.trim().isNotEmpty ? answer.trim() : null,
      remaining: left,
      limit: data['limit'] is num ? (data['limit'] as num).toInt() : null,
      error: data['error'] as String?,
      cached: data['cached'] == true,
    );
  }

  /// Resumen del negocio que se le pasa a la IA: solo cifras y nombres de productos.
  /// Nunca nombres, teléfonos ni datos de clientes.
  @visibleForTesting
  Future<Map<String, dynamic>> buildContext(String businessId) async {
    final business = BusinessRepository.instance.currentActiveBusiness;
    final currency = business?.currency ?? 'COP';
    String money(num value) => CurrencyFormatter.formatIn(value, currency);

    Future<Map<String, dynamic>> period(String name) async {
      final s = await DashboardRepository.instance.getDashboardSummary(businessId, period: name);
      return {
        'ventas': money((s['periodTotal'] as num?) ?? 0),
        'transacciones': (s['periodCount'] as num?)?.toInt() ?? 0,
        'ganancia': money((s['periodProfit'] as num?) ?? 0),
      };
    }

    final products = await ProductRepository.instance.getAllProducts(businessId);
    final outOfStock = products.where((p) => p.stock <= 0).toList();
    final lowStock = products.where((p) => p.stock > 0 && p.stock <= p.minStock).toList();
    final inventoryCost = products.fold<double>(0, (sum, p) => sum + (p.stock > 0 ? p.stock * p.purchasePrice : 0));

    final customers = await CustomerRepository.instance.getCustomers(businessId);
    final debtors = customers.where((c) => c.debtBalance > 0).toList();
    final totalDebt = debtors.fold<double>(0, (sum, c) => sum + c.debtBalance);

    final db = await AppDatabase.instance.database;
    final top = await db.rawQuery('''
      SELECT product_name, SUM(quantity) AS qty
      FROM sales WHERE business_id = ? AND date >= ?
      GROUP BY product_name ORDER BY qty DESC LIMIT 5
    ''', [businessId, DateTime.now().subtract(const Duration(days: 30)).toIso8601String()]);
    final stagnant = await db.rawQuery('''
      SELECT name FROM products
      WHERE business_id = ? AND is_active = 1 AND stock > 0
        AND id NOT IN (SELECT DISTINCT product_id FROM sales WHERE business_id = ? AND date >= ? AND product_id IS NOT NULL)
      LIMIT 5
    ''', [businessId, businessId, DateTime.now().subtract(const Duration(days: 14)).toIso8601String()]);

    return {
      'fecha': DateTime.now().toIso8601String().substring(0, 10),
      'negocio': {
        'nombre': business?.name,
        'pais': countryByCode(business?.country).name,
        'moneda': currency,
      },
      'hoy': await period('today'),
      'ultimos_7_dias': await period('week'),
      'este_mes': await period('month'),
      'inventario': {
        'productos': products.length,
        'agotados': outOfStock.length,
        'stock_bajo': lowStock.length,
        'valor_a_costo': money(inventoryCost),
      },
      'agotados': [for (final p in outOfStock.take(8)) p.name],
      'con_stock_bajo': [for (final p in lowStock.take(8)) '${p.name} (quedan ${_qty(p.stock)}, mínimo ${_qty(p.minStock)})'],
      'mas_vendidos_30_dias': [for (final r in top) '${r['product_name']} (${_qty(r['qty'] as num? ?? 0)} unidades)'],
      'sin_ventas_14_dias': [for (final r in stagnant) r['name']],
      'fiados': {'total_por_cobrar': money(totalDebt), 'clientes_con_deuda': debtors.length},
    };
  }

  static String _qty(num value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);
}
