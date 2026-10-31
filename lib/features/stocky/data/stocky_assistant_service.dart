import 'package:flutter/foundation.dart';

import '../../business/data/business_repository.dart';
import '../../customers/data/customer_repository.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../products/data/product_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../../../core/utils/countries.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/database/app_database.dart';

/// Lo que el usuario quiso preguntar, según las reglas de Stocky
enum StockyIntent {
  farewell,
  gratitude,
  praise,
  identity,
  casualCheckIn,
  greeting,
  help,
  businessHealth,
  inventoryValue,
  productCount,
  customerInfo,
  advice,
  sales,
  profit,
  howTo,
  productStock,
  lowStock,
  debts,
  topProducts,
  stagnantProducts,
  unknown,
}

/// Rango de fechas de una pregunta sobre ventas: desde [from] (incluido) hasta [to] (excluido)
class SalesPeriod {
  final String label;
  final DateTime from;
  final DateTime to;

  const SalesPeriod(this.label, this.from, this.to);
}

enum StockyMessageType {
  text,
  salesSummary,
  lowStockAlert,
  debtList,
  topProducts,
  stagnantProducts,
  productLookup,
  businessAdvice,
  help,

  /// Las reglas no entendieron la pregunta: el chat puede ofrecer la IA
  fallback,

  /// Respuesta redactada por la IA
  aiAnswer,
}

class StockyAction {
  final String label;
  final String actionType; // 'navigate_sales', 'navigate_inventory', 'navigate_customers', 'restock_modal', 'quick_sale', 'whatsapp_debtor'
  final dynamic payload;

  const StockyAction({
    required this.label,
    required this.actionType,
    this.payload,
  });
}

class StockyAssistantMessage {
  final String id;
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final StockyMessageType type;
  final List<StockyAction> actions;
  final Map<String, dynamic>? data;

  StockyAssistantMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.timestamp,
    this.type = StockyMessageType.text,
    this.actions = const [],
    this.data,
  });
}

class StockyAssistantService {
  static final StockyAssistantService instance = StockyAssistantService._internal();
  StockyAssistantService._internal();

  /// Historial en memoria de mensajes de chat por negocio durante la sesión activa.
  /// Se mantiene entre aperturas y cierres del modal, y se limpia al cerrar sesión.
  final Map<String, List<StockyAssistantMessage>> _sessionConversations = {};

  bool hasConversation(String businessId) {
    return _sessionConversations.containsKey(businessId) &&
        _sessionConversations[businessId]!.isNotEmpty;
  }

  List<StockyAssistantMessage> getConversation(String businessId) {
    return _sessionConversations.putIfAbsent(businessId, () => []);
  }

  void addMessage(String businessId, StockyAssistantMessage message) {
    final list = getConversation(businessId);
    list.add(message);
  }

  void clearConversation(String businessId) {
    _sessionConversations.remove(businessId);
  }

  void clearAllConversations() {
    _sessionConversations.clear();
  }

  /// Procesa una consulta en lenguaje natural u opción rápida y retorna la respuesta inteligente de Stocky
  Future<StockyAssistantMessage> processQuery({
    required String prompt,
    required String businessId,
    String? userName,
  }) async {
    final cleanPrompt = normalizeQuery(prompt);
    final business = BusinessRepository.instance.currentActiveBusiness;
    final bizName = business?.name ?? 'tu negocio';

    switch (classifyIntent(cleanPrompt)) {
      case StockyIntent.farewell:
        return _buildFarewellResponse(bizName);
      case StockyIntent.gratitude:
        return _buildGratitudeResponse();
      case StockyIntent.praise:
        return _buildPraiseResponse();
      case StockyIntent.identity:
        return _buildIdentityResponse(bizName);
      case StockyIntent.casualCheckIn:
        return _buildCasualCheckInResponse(userName, bizName);
      case StockyIntent.greeting:
        return _buildGreetingResponse(userName, bizName);
      case StockyIntent.help:
        return _buildHelpResponse();
      case StockyIntent.businessHealth:
        return await _buildBusinessHealthResponse(businessId, bizName);
      case StockyIntent.inventoryValue:
        return await _buildInventoryValueResponse(businessId, bizName);
      case StockyIntent.productCount:
        return await _buildProductCountResponse(businessId, bizName);
      case StockyIntent.customerInfo:
        return await _buildCustomerInfoResponse(businessId, bizName);
      case StockyIntent.advice:
        return await _buildBusinessAdviceResponse(businessId, bizName, cleanPrompt);
      case StockyIntent.howTo:
        return _buildHowToResponse(cleanPrompt);
      case StockyIntent.sales:
        final period = salesPeriodFor(cleanPrompt);
        if (period == null) return await _buildSalesTodayResponse(businessId, bizName);
        return await _buildSalesPeriodResponse(businessId, bizName, period);
      case StockyIntent.profit:
        return await _buildProfitResponse(businessId, bizName);
      case StockyIntent.productStock:
        // "¿Cuánto stock hay de arroz?": primero el producto; si no se encuentra, el resumen de stock
        return await _tryFindProductInQuery(cleanPrompt, businessId) ?? await _buildLowStockResponse(businessId);
      case StockyIntent.lowStock:
        return await _buildLowStockResponse(businessId);
      case StockyIntent.debts:
        return await _buildDebtsResponse(businessId, bizName);
      case StockyIntent.topProducts:
        return await _buildTopProductsResponse(businessId);
      case StockyIntent.stagnantProducts:
        return await _buildStagnantProductsResponse(businessId);
      case StockyIntent.unknown:
        return await _tryFindProductInQuery(cleanPrompt, businessId) ?? _buildFallbackResponse(prompt, bizName);
    }
  }

  // ==========================================
  // CLASIFICADORES DE INTENCIÓN (NLP RULES)
  // ==========================================

  /// Decide qué quiso preguntar el usuario. [text] ya viene normalizado.
  /// El orden importa: las preguntas sobre datos del negocio van antes que los tutoriales.
  @visibleForTesting
  StockyIntent classifyIntent(String text) {
    if (_isFarewell(text)) return StockyIntent.farewell;
    if (_isGratitude(text)) return StockyIntent.gratitude;
    if (_isPraise(text)) return StockyIntent.praise;
    if (_isIdentity(text)) return StockyIntent.identity;
    if (_isCasualCheckIn(text)) return StockyIntent.casualCheckIn;
    if (_isGreeting(text)) return StockyIntent.greeting;
    if (_isHelp(text)) return StockyIntent.help;
    if (_isBusinessHealth(text)) return StockyIntent.businessHealth;
    if (_isInventoryValue(text)) return StockyIntent.inventoryValue;
    if (_isProductCount(text)) return StockyIntent.productCount;
    if (_isCustomerInfo(text)) return StockyIntent.customerInfo;
    // Conceptos y consejos ("¿qué es la regla 80/20?", "¿cómo vender más?") antes que los tutoriales
    if (_isAdvice(text)) return StockyIntent.advice;
    if (_isSales(text)) return StockyIntent.sales;
    if (_isProfit(text)) return StockyIntent.profit;
    if (_isHowTo(text)) return StockyIntent.howTo;
    if (_isProductStock(text)) return StockyIntent.productStock;
    if (_isLowStock(text)) return StockyIntent.lowStock;
    if (_isDebts(text)) return StockyIntent.debts;
    if (_isTopProducts(text)) return StockyIntent.topProducts;
    if (_isStagnantProducts(text)) return StockyIntent.stagnantProducts;
    return StockyIntent.unknown;
  }

  /// Periodo de ventas pedido en la pregunta; null significa "hoy"
  @visibleForTesting
  SalesPeriod? salesPeriodFor(String text, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final tomorrow = today.add(const Duration(days: 1));
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final firstOfMonth = DateTime(today.year, today.month);

    if (_hasAny(text, ['antier', 'anteayer'])) {
      final day = today.subtract(const Duration(days: 2));
      return SalesPeriod('antier', day, day.add(const Duration(days: 1)));
    }
    if (_hasWord(text, 'ayer')) {
      return SalesPeriod('ayer', today.subtract(const Duration(days: 1)), today);
    }
    if (_hasAny(text, ['semana pasada', 'ultima semana'])) {
      return SalesPeriod('la semana pasada', monday.subtract(const Duration(days: 7)), monday);
    }
    if (_hasWord(text, 'semana')) {
      return SalesPeriod('esta semana', monday, tomorrow);
    }
    if (_hasAny(text, ['mes pasado', 'ultimo mes'])) {
      return SalesPeriod('el mes pasado', DateTime(today.year, today.month - 1), firstOfMonth);
    }
    if (_hasWord(text, 'mes')) {
      return SalesPeriod('este mes', firstOfMonth, tomorrow);
    }
    return null;
  }

  /// La palabra (o el inicio de palabra) aparece en el texto: "venta" encuentra "ventas",
  /// pero "tip" no encuentra "multiplicar" ni "top" encuentra "laptop"
  static bool _hasWord(String text, String key) => RegExp('(^|\\s)${RegExp.escape(key)}').hasMatch(text);

  static bool _hasAny(String text, List<String> keys) => keys.any((k) => _hasWord(text, k));

  bool _isFarewell(String text) {
    final regex = RegExp(r'\b(chao|adios|hasta luego|hasta manana|nos vemos|bye|hasta pronto|me voy|buenas noches)\b');
    return regex.hasMatch(text);
  }

  bool _isGratitude(String text) {
    final regex = RegExp(r'\b(gracias|muchas gracias|mil gracias|vale gracias|ok gracias|listo gracias|buena esa|excelente|genial|perfecto|muy bien|crack|de acuerdo|entendido|ok)\b');
    return regex.hasMatch(text) && text.split(' ').length <= 4;
  }

  bool _isPraise(String text) {
    final regex = RegExp(r'\b(eres genial|buen trabajo|te quiero|eres el mejor|sos un crack|eres una ia|eres un bot|buen asistente|muy util|te amo)\b');
    return regex.hasMatch(text);
  }

  bool _isIdentity(String text) => _hasAny(text, [
        'quien eres',
        'como te llamas',
        'que eres',
        'presentate',
        'que funcion tienes',
        'para que sirves',
        'cual es tu nombre',
      ]);

  bool _isCasualCheckIn(String text) {
    final regex = RegExp(r'\b(como estas|como te va|como vas|como andas|que tal|que haces|que onda|que mas|que hubo|que hay|todo bien|que cuentas|como te encuentras)\b');
    return regex.hasMatch(text);
  }

  bool _isGreeting(String text) {
    final regex = RegExp(r'\b(hola|buen(os|as)?\s*(dias|tardes|noches)?|hey|saludos|stocky)\b');
    return regex.hasMatch(text) && text.split(' ').length <= 4;
  }

  bool _isHelp(String text) =>
      _hasAny(text, ['que puedes hacer', 'como funcionas', 'ayuda', 'ayudame', 'comandos', 'opciones']);

  bool _isBusinessHealth(String text) => _hasAny(text, [
        'como va el negocio',
        'como va mi negocio',
        'como vamos',
        'como va todo',
        'como esta el negocio',
        'como esta mi negocio',
        'estado del negocio',
        'resumen general',
        'termometro',
        'balance del negocio',
      ]);

  bool _isInventoryValue(String text) => _hasAny(text, [
        'cuanto vale mi inventario',
        'cuanto vale el inventario',
        'valor del inventario',
        'valor comercial',
        'dinero en stock',
        'capital en mercancia',
        'cuanto tengo en mercancia',
        'cuanto dinero tengo en productos',
        'valor de los productos',
        'plata en inventario',
      ]);

  bool _isProductCount(String text) => _hasAny(text, [
        'cuantos productos',
        'total de productos',
        'cuantos articulos',
        'cantidad de productos',
        'total de items',
        'total catalogo',
      ]);

  bool _isCustomerInfo(String text) => _hasAny(text, [
        'cuantos clientes',
        'mis clientes',
        'lista de clientes',
        'total clientes',
        'directorio de clientes',
        'base de clientes',
      ]);

  /// Tutoriales ("¿cómo registro una venta?"), pero no preguntas sobre cómo va el negocio
  bool _isHowTo(String text) {
    final asksHow = text.startsWith('como ') || _hasAny(text, ['como puedo', 'como se', 'como hago']);
    final asksStatus = RegExp(r'^como (va|van|vamos|esta|estan|me fue|nos fue|me va)\b').hasMatch(text);
    return asksHow && !asksStatus;
  }

  bool _isSales(String text) {
    if (_hasAny(text, ['ventas de hoy', 'como van las ventas', 'cuanto vendi', 'cuanto vendimos', 'cuanto se vendio'])) {
      return true;
    }
    final mentionsSales = _hasAny(text, ['venta', 'vend', 'factur', 'ingreso']);
    final asksAmount = _hasAny(text, ['hoy', 'dia', 'cuanto', 'como van', 'como fue', 'como me fue', 'resumen', 'total']);
    return mentionsSales && (asksAmount || salesPeriodFor(text) != null);
  }

  bool _isProfit(String text) =>
      _hasAny(text, ['ganancia', 'gane', 'ganamos', 'margen', 'utilidad', 'beneficio', 'rentabilidad']);

  /// Pregunta por el stock de algo concreto ("¿cuánto hay de arroz?")
  bool _isProductStock(String text) => _hasAny(text, [
        'cuanto stock',
        'cuantas unidades',
        'cuantos quedan',
        'cuantas quedan',
        'cuanto queda',
        'cuanto hay de',
        'tengo de',
        'stock de',
      ]);

  bool _isLowStock(String text) => _hasAny(text, [
        'stock',
        'agotad',
        'se acab',
        'acabando',
        'falta',
        'critico',
        'reponer',
        'reposicion',
        'surtir',
        'proveedor',
        'mercancia baja',
        'inventario bajo',
      ]);

  bool _isDebts(String text) => _hasAny(text, [
        'fiado',
        'deuda',
        'deben',
        'cobrar',
        'cartera',
        'quien me debe',
        'cuentas por cobrar',
      ]);

  bool _isTopProducts(String text) => _hasAny(text, [
        'mas vendido',
        'mas se vende',
        'lo que mas',
        'top',
        'estrella',
        'populares',
        'mas salida',
        'mejores productos',
      ]);

  bool _isStagnantProducts(String text) => _hasAny(text, [
        'estancad',
        'no se vende',
        'no se mueve',
        'sin vender',
        'lento',
        'muert',
        'sin movimiento',
        'quedado',
      ]);

  bool _isAdvice(String text) => _hasAny(text, [
        'consejo',
        'tip',
        'sugerencia',
        'recomendacion',
        'recomiendas',
        'como vender mas',
        'vender mas',
        'estrategia',
        'que hago',
        'ideas',
        '8020',
        '80 20',
        'pareto',
      ]);

  /// Minúsculas, sin tildes ni signos: "¿Qué es la regla 80/20?" → "que es la regla 8020"
  @visibleForTesting
  String normalizeQuery(String input) => _normalize(input);

  String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ==========================================
  // GENERADORES DE RESPUESTAS CON CONTEXTO REAL
  // ==========================================

  StockyAssistantMessage _buildFarewellResponse(String bizName) {
    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: '¡Hasta luego! 👋 Que descanses y que la próxima jornada esté llena de ventas y prosperidad en **$bizName**.\n\n¡Aquí estaré listo cuando vuelvas! 🚀',
      timestamp: DateTime.now(),
      type: StockyMessageType.text,
    );
  }

  StockyAssistantMessage _buildGratitudeResponse() {
    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: '¡Con todo el gusto! 🌟 ¡Para eso estoy aquí!\n\nSiempre que necesites consultar cualquier número, producto o deuda de tu negocio, estaré a solo un toque de distancia.\n\n¡A seguir vendiendo con toda! 💪',
      timestamp: DateTime.now(),
      type: StockyMessageType.text,
      actions: const [
        StockyAction(label: '+ Registrar Venta', actionType: 'quick_sale'),
        StockyAction(label: 'Ver Inventario', actionType: 'navigate_inventory'),
      ],
    );
  }

  StockyAssistantMessage _buildPraiseResponse() {
    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: '¡Muchas gracias por la buena energía! 💚🤖\n\nMe encanta hacer equipo contigo. Mi misión es que tu negocio crezca todos los días, que nunca te quedes sin stock y que tus cuentas estén 100% claras.\n\n¿Qué miramos ahora?',
      timestamp: DateTime.now(),
      type: StockyMessageType.text,
      actions: const [
        StockyAction(label: '📊 Ventas hoy', actionType: 'query_sales'),
        StockyAction(label: '💡 Consejo del día', actionType: 'query_advice'),
      ],
    );
  }

  StockyAssistantMessage _buildIdentityResponse(String bizName) {
    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: '¡Mucho gusto! Soy **Stocky** 🤖, el asistente comercial inteligente de **Stockealo** creado para ser tu mano derecha en **$bizName**.\n\n'
          '🔒 **100% Offline & Seguro:** Vivo directamente en tu teléfono, por lo que nunca dependes de internet ni pagas mensualidades por consultarme.\n\n'
          '⚡ **¿Qué puedo hacer por ti?**\n'
          '• **Ventas y Utilidades:** Decirte cuánto has vendido y tu ganancia real al instante.\n'
          '• **Control de Stock:** Alertarte sobre productos agotados antes de que pierdas ventas.\n'
          '• **Fiados y Cobros:** Recordarte quién te debe y ayudarte a cobrar por WhatsApp en 1 tap.\n'
          '• **Diagnóstico de Negocio:** Analizar tu inventario comercial y darte consejos para vender más.\n\n'
          '¡Pregúntame lo que necesites como si habláramos por chat!',
      timestamp: DateTime.now(),
      type: StockyMessageType.text,
      actions: const [
        StockyAction(label: '📊 Ventas de hoy', actionType: 'query_sales'),
        StockyAction(label: '⚠️ Stock crítico', actionType: 'query_stock'),
        StockyAction(label: '👥 Fiados pendientes', actionType: 'query_debts'),
      ],
    );
  }

  StockyAssistantMessage _buildCasualCheckInResponse(String? userName, String bizName) {
    final nameStr = userName != null && userName.isNotEmpty ? ' $userName' : '';
    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: '¡Excelente y con toda la energía$nameStr! 🤖⚡\n\n'
          'Estoy al 100% monitoreando las operaciones de **$bizName**. Tenemos todo listo para vender, revisar stock y cuidar tus cuentas.\n\n'
          '¿Cómo va la jornada? ¿Quieres que revisemos cómo van las ventas de hoy o el inventario?',
      timestamp: DateTime.now(),
      type: StockyMessageType.text,
      actions: const [
        StockyAction(label: '📊 Ventas de hoy', actionType: 'query_sales'),
        StockyAction(label: '⚠️ Stock crítico', actionType: 'query_stock'),
        StockyAction(label: '👥 Fiados pendientes', actionType: 'query_debts'),
        StockyAction(label: '💡 Consejo del día', actionType: 'query_advice'),
      ],
    );
  }

  Future<StockyAssistantMessage> _buildBusinessHealthResponse(String businessId, String bizName) async {
    final dbSummary = await DashboardRepository.instance.getDashboardSummary(businessId, period: 'today');
    final todayTotal = (dbSummary['periodTotal'] as num?)?.toDouble() ?? 0.0;
    final todayCount = (dbSummary['periodCount'] as num?)?.toInt() ?? 0;
    final todayProfit = (dbSummary['periodProfit'] as num?)?.toDouble() ?? 0.0;
    final outOfStock = (dbSummary['outOfStock'] as num?)?.toInt() ?? 0;
    final lowStock = (dbSummary['lowStock'] as num?)?.toInt() ?? 0;
    final totalProducts = (dbSummary['totalProducts'] as num?)?.toInt() ?? 0;
    final totalDebt = (dbSummary['totalDebt'] as num?)?.toDouble() ?? 0.0;

    final buffer = StringBuffer();
    buffer.writeln('📈 **Termómetro Operativo de $bizName:**\n');

    if (todayCount > 0) {
      buffer.writeln('• **Ventas de hoy:** ${CurrencyFormatter.formatCOP(todayTotal)} ($todayCount transacciones, +${CurrencyFormatter.formatCOP(todayProfit)} ganancia neta).');
    } else {
      buffer.writeln('• **Ventas de hoy:** Aún sin ventas registradas hoy.');
    }

    if (outOfStock > 0 || lowStock > 0) {
      buffer.writeln('• **Inventario:** ⚠️ Tienes **$outOfStock agotados** y **$lowStock con stock bajo** (de un total de $totalProducts productos).');
    } else {
      buffer.writeln('• **Inventario:** 🟢 Todo el stock está saludable ($totalProducts productos activos).');
    }

    if (totalDebt > 0) {
      buffer.writeln('• **Fiados por cobrar:** ⏳ **${CurrencyFormatter.formatCOP(totalDebt)}** pendientes en cartera de clientes.');
    } else {
      buffer.writeln('• **Cartera:** 🥳 No tienes deudas pendientes por cobrar. ¡Cuentas al día!');
    }

    buffer.writeln('\n¿Deseas profundizar en alguna de estas áreas?');

    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: buffer.toString(),
      timestamp: DateTime.now(),
      type: StockyMessageType.text,
      actions: [
        if (outOfStock > 0 || lowStock > 0)
          const StockyAction(label: '⚠️ Ver Stock Crítico', actionType: 'query_stock'),
        if (totalDebt > 0)
          const StockyAction(label: '👥 Cobrar Fiados', actionType: 'query_debts'),
        const StockyAction(label: '+ Registrar Venta', actionType: 'quick_sale'),
        const StockyAction(label: 'Ver Historial', actionType: 'navigate_sales'),
      ],
    );
  }

  Future<StockyAssistantMessage> _buildInventoryValueResponse(String businessId, String bizName) async {
    final db = await AppDatabase.instance.database;
    final res = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_prods,
        COALESCE(SUM(stock * sale_price), 0.0) as total_commercial,
        COALESCE(SUM(stock * purchase_price), 0.0) as total_cost,
        COALESCE(SUM(stock), 0) as total_units
      FROM products
      WHERE business_id = ? AND is_active = 1
    ''', [businessId]);

    final row = res.first;
    final totalProds = (row['total_prods'] as num?)?.toInt() ?? 0;
    final commercialVal = (row['total_commercial'] as num?)?.toDouble() ?? 0.0;
    final costVal = (row['total_cost'] as num?)?.toDouble() ?? 0.0;
    final totalUnits = (row['total_units'] as num?)?.toInt() ?? 0;
    final potentialProfit = commercialVal - costVal;

    final text = '💰 **Valorización de Inventario de $bizName:**\n\n'
        '• **Valor Comercial en Venta:** **${CurrencyFormatter.formatCOP(commercialVal)}**\n'
        '• **Inversión / Costo de Compra:** ${CurrencyFormatter.formatCOP(costVal)}\n'
        '• **Ganancia Proyectada al Vender Todo:** **+${CurrencyFormatter.formatCOP(potentialProfit)}**\n'
        '• **Unidades Físicas Almacenadas:** $totalUnits unidades ($totalProds productos distintos)\n\n'
        '💡 Este es el capital comercial que tienes activo en tus estantes listo para monetizar.';

    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: text,
      timestamp: DateTime.now(),
      type: StockyMessageType.text,
      actions: const [
        StockyAction(label: 'Ver Inventario', actionType: 'navigate_inventory'),
        StockyAction(label: 'Stock Crítico', actionType: 'query_stock'),
      ],
    );
  }

  Future<StockyAssistantMessage> _buildProductCountResponse(String businessId, String bizName) async {
    final db = await AppDatabase.instance.database;
    final res = await db.rawQuery('''
      SELECT 
        COUNT(*) as total,
        COALESCE(SUM(CASE WHEN stock <= 0 THEN 1 ELSE 0 END), 0) as out_of_stock,
        COALESCE(SUM(CASE WHEN stock > 0 AND stock <= min_stock THEN 1 ELSE 0 END), 0) as low_stock,
        COALESCE(SUM(CASE WHEN stock > min_stock THEN 1 ELSE 0 END), 0) as healthy_stock,
        COALESCE(SUM(stock), 0) as total_units
      FROM products
      WHERE business_id = ? AND is_active = 1
    ''', [businessId]);

    final row = res.first;
    final total = (row['total'] as num?)?.toInt() ?? 0;
    final outOfStock = (row['out_of_stock'] as num?)?.toInt() ?? 0;
    final lowStock = (row['low_stock'] as num?)?.toInt() ?? 0;
    final healthy = (row['healthy_stock'] as num?)?.toInt() ?? 0;
    final totalUnits = (row['total_units'] as num?)?.toInt() ?? 0;

    final text = '📦 **Detalle del Catálogo de $bizName:**\n\n'
        'Tienes registrados **$total productos activos** ($totalUnits unidades en total):\n\n'
        '• 🟢 **En stock normal:** $healthy productos\n'
        '• 🟠 **Con stock bajo:** $lowStock productos\n'
        '• 🔴 **Agotados (0 unidades):** $outOfStock productos\n\n'
        '¿Deseas revisar los que necesitan reposición?';

    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: text,
      timestamp: DateTime.now(),
      type: StockyMessageType.text,
      actions: [
        if (outOfStock > 0 || lowStock > 0)
          const StockyAction(label: '⚠️ Ver Stock Crítico', actionType: 'query_stock'),
        const StockyAction(label: 'Ver Todo el Inventario', actionType: 'navigate_inventory'),
      ],
    );
  }

  Future<StockyAssistantMessage> _buildCustomerInfoResponse(String businessId, String bizName) async {
    final db = await AppDatabase.instance.database;
    final res = await db.rawQuery('''
      SELECT 
        COUNT(*) as total,
        COALESCE(SUM(CASE WHEN debt_balance > 0 THEN 1 ELSE 0 END), 0) as debtors_count,
        COALESCE(SUM(debt_balance), 0.0) as total_debt
      FROM customers
      WHERE business_id = ?
    ''', [businessId]);

    final row = res.first;
    final total = (row['total'] as num?)?.toInt() ?? 0;
    final debtorsCount = (row['debtors_count'] as num?)?.toInt() ?? 0;
    final totalDebt = (row['total_debt'] as num?)?.toDouble() ?? 0.0;

    String text;
    if (total == 0) {
      text = 'Aún no tienes clientes registrados en tu libreta de **$bizName**.\n\n'
          '💡 Al registrar una venta a crédito (fiado), el cliente se crea automáticamente para que lleves su saldo y puedas cobrarle por WhatsApp.';
    } else {
      text = '👥 **Base de Clientes de $bizName:**\n\n'
          '• **Total de Clientes:** $total personas registradas\n'
          '• **Con saldo pendiente (fiado):** $debtorsCount clientes (${CurrencyFormatter.formatCOP(totalDebt)})\n'
          '• **Al día:** ${total - debtorsCount} clientes';
    }

    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: text,
      timestamp: DateTime.now(),
      type: StockyMessageType.text,
      actions: const [
        StockyAction(label: 'Ver Clientes', actionType: 'navigate_customers'),
        StockyAction(label: 'Fiados Pendientes', actionType: 'query_debts'),
      ],
    );
  }

  /// Apps de pago del país del negocio activo ("Nequi o Daviplata", "Yape o Plin"...)
  String get _localPaymentApps =>
      countryByCode(BusinessRepository.instance.currentActiveBusiness?.country).paymentApps;

  StockyAssistantMessage _buildHowToResponse(String query) {
    if (query.contains('venta') || query.contains('vender') || query.contains('factur') || query.contains('cobrar en caja')) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: '🛍️ **Cómo registrar una venta en Stockealo:**\n\n'
            '1. Toca el botón **+ Venta Rápida** o ve al módulo de **Ventas**.\n'
            '2. Selecciona los productos de la lista o escanea su código de barras con la cámara.\n'
            '3. Elige el medio de pago:\n'
            '   • **Efectivo** (calcula cambio automático)\n'
            '   • **Transferencia** ($_localPaymentApps, etc.)\n'
            '   • **Fiado** (asócialo a un cliente para cobrar luego)\n'
            '4. Toca **Confirmar Venta**. El stock se descontará al instante y podrás compartir el ticket digital.',
        timestamp: DateTime.now(),
        type: StockyMessageType.text,
        actions: const [
          StockyAction(label: '+ Registrar Venta Ahora', actionType: 'quick_sale'),
          StockyAction(label: 'Ver Historial de Ventas', actionType: 'navigate_sales'),
        ],
      );
    }

    if (query.contains('producto') || query.contains('articulo') || query.contains('inventario') || query.contains('mercaderia') || query.contains('agregar') || query.contains('crear')) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: '📦 **Cómo agregar un nuevo producto:**\n\n'
            '1. Ve a la pestaña **Inventario** en la barra inferior.\n'
            '2. Pulsa el botón flotante verde con el signo **(+)**.\n'
            '3. Escribe el nombre, precio de compra (tu costo) y precio de venta al público.\n'
            '4. Ingresa el stock actual y el stock mínimo para recibir alertas.\n'
            '5. Puedes tomarle una foto o asignarle código de barras.\n'
            '6. Guarda y ¡listo para vender!',
        timestamp: DateTime.now(),
        type: StockyMessageType.text,
        actions: const [
          StockyAction(label: 'Ir a Inventario', actionType: 'navigate_inventory'),
        ],
      );
    }

    if (query.contains('fiado') || query.contains('cobrar') || query.contains('deuda') || query.contains('whatsapp')) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: '👥 **Cómo cobrar y gestionar fiados:**\n\n'
            '1. Ve a **Ventas** -> Botón **Clientes / Fiados** (o pregúntame * "¿Quién me debe dinero?" *).\n'
            '2. Verás la lista de personas con saldo pendiente.\n'
            '3. Toca **"Recordar por WhatsApp"** para enviar un mensaje cordial prediseñado con el monto exacto.\n'
            '4. Cuando te abonen o paguen, toca **Abonar / Liquidar** para actualizar su saldo a cero.',
        timestamp: DateTime.now(),
        type: StockyMessageType.text,
        actions: const [
          StockyAction(label: 'Ver Fiados Pendientes', actionType: 'query_debts'),
          StockyAction(label: 'Ir a Clientes', actionType: 'navigate_customers'),
        ],
      );
    }

    if (query.contains('excel') || query.contains('export') || query.contains('reporte') || query.contains('informe') || query.contains('descargar')) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: '📊 **Cómo exportar tus reportes a Excel:**\n\n'
            '1. Entra al módulo de **Historial de Ventas**.\n'
            '2. En los botones superiores, toca **Excel (.xlsx)**.\n'
            '3. Selecciona el periodo (hoy, este mes, rango personalizado).\n'
            '4. Se generará una planilla completa con fecha, cliente, medio de pago, totales y margen de ganancia lista para compartir o abrir en Excel.',
        timestamp: DateTime.now(),
        type: StockyMessageType.text,
        actions: const [
          StockyAction(label: 'Ir a Historial de Ventas', actionType: 'navigate_sales'),
        ],
      );
    }

    return _buildHelpResponse();
  }

  StockyAssistantMessage _buildGreetingResponse(String? userName, String bizName) {
    final nameStr = userName != null && userName.isNotEmpty ? ' $userName' : '';
    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: '¡Hola$nameStr! 👋 Soy **Stocky**, tu asistente comercial para **$bizName**.\n\nEstoy aquí para darte respuestas al instante sobre tus ventas, alertas de stock, cuentas por cobrar y consejos de negocio en tiempo real.\n\n¿Qué te gustaría revisar hoy?',
      timestamp: DateTime.now(),
      type: StockyMessageType.text,
      actions: const [
        StockyAction(label: '📊 Ventas de hoy', actionType: 'query_sales'),
        StockyAction(label: '⚠️ Stock crítico', actionType: 'query_stock'),
        StockyAction(label: '👥 Fiados pendientes', actionType: 'query_debts'),
        StockyAction(label: '💡 Consejo comercial', actionType: 'query_advice'),
      ],
    );
  }

  StockyAssistantMessage _buildHelpResponse() {
    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: '🤖 **Esto es todo lo que puedo hacer por ti al instante:**\n\n'
          '• **📊 Ventas y Caja:** "¿Cuánto vendimos hoy?", "¿Cuál es mi ganancia?"\n'
          '• **⚠️ Control de Stock:** "¿Qué productos se están agotando?", "¿Qué debo reponer?"\n'
          '• **👥 Fiados y Cobros:** "¿Quién me debe dinero?", "Ver fiados pendientes"\n'
          '• **🏆 Productos Estrella:** "¿Cuáles son mis productos más vendidos?"\n'
          '• **📦 Inventario Inactivo:** "¿Qué mercadería no se ha movido?"\n'
          '• **🔍 Consulta Directa:** "Precio de Coca Cola", "Stock de Arroz"\n'
          '• **💡 Consejos:** "¿Qué me recomiendas para vender más hoy?"\n\n'
          'Estas respuestas salen de tus datos, sin internet. Lo que no sepa responder se lo puedo preguntar a la IA (botón **IA** arriba).',
      timestamp: DateTime.now(),
      type: StockyMessageType.help,
      actions: const [
        StockyAction(label: 'Ventas de hoy', actionType: 'query_sales'),
        StockyAction(label: 'Stock crítico', actionType: 'query_stock'),
        StockyAction(label: 'Fiados', actionType: 'query_debts'),
        StockyAction(label: 'Top ventas', actionType: 'query_top'),
      ],
    );
  }

  Future<StockyAssistantMessage> _buildSalesTodayResponse(String businessId, String bizName) async {
    final summary = await SalesRepository.instance.getTodaySummary(businessId);
    final count = summary['count'] as int? ?? 0;
    final total = (summary['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final profit = (summary['netProfit'] as num?)?.toDouble() ?? 0.0;
    final units = summary['totalUnits'] as int? ?? 0;
    final efectivo = (summary['byEfectivo'] as num?)?.toDouble() ?? 0.0;
    final transfer = (summary['byTransferencia'] as num?)?.toDouble() ?? 0.0;
    final fiado = (summary['byFiado'] as num?)?.toDouble() ?? 0.0;

    final margin = total > 0 ? ((profit / total) * 100).toStringAsFixed(1) : '0';

    if (count == 0) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: 'Aún no has registrado ventas hoy en **$bizName**.\n\n'
            '💡 **Tip para activar el día:** Comparte tus productos en tus estados de WhatsApp o registra tu primera venta rápida con el botón de abajo.',
        timestamp: DateTime.now(),
        type: StockyMessageType.salesSummary,
        actions: const [
          StockyAction(label: 'Registrar Venta Rápida', actionType: 'quick_sale'),
          StockyAction(label: 'Ver Historial de Ventas', actionType: 'navigate_sales'),
        ],
        data: {'total': 0.0, 'count': 0, 'profit': 0.0},
      );
    }

    final text = '📊 **Resumen de Ventas de Hoy en $bizName:**\n\n'
        '• **Total Facturado:** ${CurrencyFormatter.formatCOP(total)}\n'
        '• **Ganancia Neta:** ${CurrencyFormatter.formatCOP(profit)} *(Margen: $margin%)*\n'
        '• **Transacciones:** $count ventas ($units unidades vendidas)\n\n'
        '💳 **Medios de Pago:**\n'
        '• Efectivo: ${CurrencyFormatter.formatCOP(efectivo)}\n'
        '• Transferencia: ${CurrencyFormatter.formatCOP(transfer)}\n'
        '• Fiados de hoy: ${CurrencyFormatter.formatCOP(fiado)}';

    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: text,
      timestamp: DateTime.now(),
      type: StockyMessageType.salesSummary,
      actions: const [
        StockyAction(label: 'Ver Historial de Ventas', actionType: 'navigate_sales'),
        StockyAction(label: '+ Nueva Venta', actionType: 'quick_sale'),
      ],
      data: {
        'total': total,
        'profit': profit,
        'count': count,
        'units': units,
        'margin': margin,
        'efectivo': efectivo,
        'transfer': transfer,
        'fiado': fiado,
      },
    );
  }

  /// Ventas de un periodo distinto a hoy: ayer, esta semana, el mes pasado...
  Future<StockyAssistantMessage> _buildSalesPeriodResponse(
    String businessId,
    String bizName,
    SalesPeriod period,
  ) async {
    final summary = await SalesRepository.instance.getSalesSummary(businessId, from: period.from, to: period.to);
    final count = summary['count'] as int? ?? 0;
    final total = (summary['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final profit = (summary['netProfit'] as num?)?.toDouble() ?? 0.0;
    final units = summary['totalUnits'] as int? ?? 0;
    final efectivo = (summary['byEfectivo'] as num?)?.toDouble() ?? 0.0;
    final transfer = (summary['byTransferencia'] as num?)?.toDouble() ?? 0.0;
    final fiado = (summary['byFiado'] as num?)?.toDouble() ?? 0.0;
    final margin = total > 0 ? ((profit / total) * 100).toStringAsFixed(1) : '0';

    final text = count == 0
        ? 'No hay ventas registradas ${_periodPhrase(period)} en **$bizName**.'
        : '📊 **Ventas de ${period.label} en $bizName:**\n\n'
            '• **Total Facturado:** ${CurrencyFormatter.formatCOP(total)}\n'
            '• **Ganancia Neta:** ${CurrencyFormatter.formatCOP(profit)} *(Margen: $margin%)*\n'
            '• **Transacciones:** $count ventas ($units unidades vendidas)\n\n'
            '💳 **Medios de Pago:**\n'
            '• Efectivo: ${CurrencyFormatter.formatCOP(efectivo)}\n'
            '• Transferencia: ${CurrencyFormatter.formatCOP(transfer)}\n'
            '• Fiado: ${CurrencyFormatter.formatCOP(fiado)}';

    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: text,
      timestamp: DateTime.now(),
      type: StockyMessageType.salesSummary,
      actions: const [
        StockyAction(label: 'Ver Historial de Ventas', actionType: 'navigate_sales'),
      ],
      data: {'total': total, 'profit': profit, 'count': count, 'units': units, 'margin': margin},
    );
  }

  /// "ayer" → "ayer"; "esta semana" → "en esta semana"
  static String _periodPhrase(SalesPeriod period) =>
      period.label == 'ayer' || period.label == 'antier' ? period.label : 'en ${period.label}';

  Future<StockyAssistantMessage> _buildProfitResponse(String businessId, String bizName) async {
    final summary = await SalesRepository.instance.getTodaySummary(businessId);
    final total = (summary['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final profit = (summary['netProfit'] as num?)?.toDouble() ?? 0.0;
    final margin = total > 0 ? ((profit / total) * 100).toStringAsFixed(1) : '0';

    if (total == 0) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: 'Aún no registras ventas hoy, por lo que la ganancia de hoy es **${CurrencyFormatter.formatCOP(0)}**.\n\n'
            'En cuanto comiences a facturar, calcularé en tiempo real la utilidad descontando el costo de compra de cada artículo.',
        timestamp: DateTime.now(),
        type: StockyMessageType.text,
        actions: const [
          StockyAction(label: '+ Registrar Venta', actionType: 'quick_sale'),
        ],
      );
    }

    final text = '💰 **Análisis de Rentabilidad de Hoy:**\n\n'
        '• **Ingresos Brutos:** ${CurrencyFormatter.formatCOP(total)}\n'
        '• **Ganancia Neta Real:** ${CurrencyFormatter.formatCOP(profit)}\n'
        '• **Margen de Ganancia:** **$margin%** sobre venta\n\n'
        '${double.parse(margin) >= 30 ? "🚀 ¡Excelente margen comercial! Tu negocio opera con muy buena rentabilidad." : "💡 Tip: Para elevar tu margen, intenta negociar mejores precios por volumen con proveedores en tus productos de alta rotación."}';

    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: text,
      timestamp: DateTime.now(),
      type: StockyMessageType.salesSummary,
      actions: const [
        StockyAction(label: 'Ver Historial de Ventas', actionType: 'navigate_sales'),
      ],
    );
  }

  Future<StockyAssistantMessage> _buildLowStockResponse(String businessId) async {
    final products = await ProductRepository.instance.getAllProducts(businessId);
    final outOfStock = products.where((p) => p.stock <= 0).toList();
    final lowStock = products.where((p) => p.stock > 0 && p.stock <= p.minStock).toList();
    final totalCritical = outOfStock.length + lowStock.length;

    if (totalCritical == 0) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: '🎉 **¡Excelente noticia!**\n\nTodos tus **${products.length} productos** cuentan con stock suficiente por encima de su mínimo de seguridad. No tienes faltantes urgentes.',
        timestamp: DateTime.now(),
        type: StockyMessageType.lowStockAlert,
        actions: const [
          StockyAction(label: 'Ver Inventario', actionType: 'navigate_inventory'),
        ],
      );
    }

    final buffer = StringBuffer();
    buffer.writeln('⚠️ **Diagnóstico de Inventario Crítico:**\n');
    buffer.writeln(totalCritical == 1
        ? 'Tienes **1 producto** que requiere reposición inmediata para no perder ventas:\n'
        : 'Tienes **$totalCritical productos** que requieren reposición inmediata para no perder ventas:\n');

    if (outOfStock.isNotEmpty) {
      buffer.writeln('🔴 **Agotados (${outOfStock.length}):**');
      for (final p in outOfStock.take(4)) {
        buffer.writeln('• **${p.name}** (0 un. disponibles)');
      }
      if (outOfStock.length > 4) {
        buffer.writeln('  *y ${outOfStock.length - 4} más...*');
      }
      buffer.writeln('');
    }

    if (lowStock.isNotEmpty) {
      buffer.writeln('🟠 **Por agotarse (${lowStock.length}):**');
      for (final p in lowStock.take(4)) {
        buffer.writeln('• **${p.name}** (${p.stock} un. | Mín: ${p.minStock})');
      }
      if (lowStock.length > 4) {
        buffer.writeln('  *y ${lowStock.length - 4} más...*');
      }
    }

    buffer.writeln('\n¿Deseas generar el pedido a tus proveedores de una vez?');

    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: buffer.toString(),
      timestamp: DateTime.now(),
      type: StockyMessageType.lowStockAlert,
      actions: const [
        StockyAction(label: '📦 Pedido al Proveedor', actionType: 'restock_modal'),
        StockyAction(label: 'Ver Inventario', actionType: 'navigate_inventory'),
      ],
      data: {
        'outOfStockCount': outOfStock.length,
        'lowStockCount': lowStock.length,
        'totalCritical': totalCritical,
      },
    );
  }

  Future<StockyAssistantMessage> _buildDebtsResponse(String businessId, String bizName) async {
    final customers = await CustomerRepository.instance.getCustomers(businessId);
    final debtors = customers.where((c) => c.debtBalance > 0).toList();
    debtors.sort((a, b) => b.debtBalance.compareTo(a.debtBalance));

    final totalDebt = debtors.fold<double>(0.0, (acc, c) => acc + c.debtBalance);

    if (debtors.isEmpty) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: '🥳 **¡Cuentas al día!**\n\nNo tienes saldos pendientes por cobrar en fiados. Todos tus clientes están 100% al día.',
        timestamp: DateTime.now(),
        type: StockyMessageType.debtList,
        actions: const [
          StockyAction(label: 'Ver Clientes', actionType: 'navigate_customers'),
        ],
      );
    }

    final buffer = StringBuffer();
    buffer.writeln('👥 **Cuentas por Cobrar (Fiados):**\n');
    buffer.writeln('Tienes un total de **${CurrencyFormatter.formatCOP(totalDebt)}** pendiente por recaudar entre **${debtors.length} clientes**:\n');

    for (final c in debtors.take(5)) {
      final phone = c.phone != null && c.phone!.isNotEmpty ? ' 📞 ${c.phone}' : '';
      buffer.writeln('• **${c.name}**: ${CurrencyFormatter.formatCOP(c.debtBalance)}$phone');
    }

    if (debtors.length > 5) {
      buffer.writeln('\n*y ${debtors.length - 5} clientes más con saldo pendiente.*');
    }

    buffer.writeln('\n💡 **Tip Pro:** Toca "Cobrar por WhatsApp" para enviarles un recordatorio cordial ya redactado.');

    final actions = <StockyAction>[];
    if (debtors.isNotEmpty) {
      final topDebtor = debtors.first;
      actions.add(
        StockyAction(
          label: '💬 Cobrar a ${topDebtor.name.split(' ').first}',
          actionType: 'whatsapp_debtor',
          payload: {
            'customerName': topDebtor.name,
            'debtAmount': topDebtor.debtBalance,
            'bizName': bizName,
            'phone': topDebtor.phone,
          },
        ),
      );
    }
    actions.add(const StockyAction(label: 'Ver Todos los Clientes', actionType: 'navigate_customers'));

    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: buffer.toString(),
      timestamp: DateTime.now(),
      type: StockyMessageType.debtList,
      actions: actions,
      data: {
        'totalDebt': totalDebt,
        'debtorsCount': debtors.length,
      },
    );
  }

  Future<StockyAssistantMessage> _buildTopProductsResponse(String businessId) async {
    final db = await AppDatabase.instance.database;
    final res = await db.rawQuery('''
      SELECT 
        s.product_name, 
        SUM(s.quantity) as qty, 
        SUM(s.total) as revenue 
      FROM sales s
      WHERE s.business_id = ?
      GROUP BY s.product_name 
      ORDER BY qty DESC 
      LIMIT 5
    ''', [businessId]);

    if (res.isEmpty) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: 'Aún no hay suficientes ventas registradas para generar el ranking de productos estrella.\n\nEn cuanto realices ventas, aquí verás tus productos más rentables y solicitados.',
        timestamp: DateTime.now(),
        type: StockyMessageType.topProducts,
        actions: const [
          StockyAction(label: '+ Registrar Venta', actionType: 'quick_sale'),
        ],
      );
    }

    final buffer = StringBuffer();
    buffer.writeln('🏆 **Tus 5 Productos Más Vendidos:**\n');

    final medals = ['🥇', '🥈', '🥉', '4️⃣', '5️⃣'];
    for (int i = 0; i < res.length; i++) {
      final row = res[i];
      final name = row['product_name'] as String;
      final qty = (row['qty'] as num).toInt();
      final revenue = (row['revenue'] as num).toDouble();
      buffer.writeln('${medals[i]} **$name**');
      buffer.writeln('    $qty unidades vendidas • ${CurrencyFormatter.formatCOP(revenue)}\n');
    }

    buffer.writeln('💡 **Estrategia:** Asegúrate de mantener siempre stock de estos productos, ya que son el motor principal de tus ingresos.');

    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: buffer.toString(),
      timestamp: DateTime.now(),
      type: StockyMessageType.topProducts,
      actions: const [
        StockyAction(label: 'Ver Catálogo', actionType: 'navigate_inventory'),
        StockyAction(label: 'Ver Ventas', actionType: 'navigate_sales'),
      ],
    );
  }

  Future<StockyAssistantMessage> _buildStagnantProductsResponse(String businessId) async {
    final db = await AppDatabase.instance.database;
    final fourteenDaysAgo = DateTime.now().subtract(const Duration(days: 14)).toIso8601String();

    final res = await db.rawQuery('''
      SELECT p.id, p.name, p.stock, p.sale_price, p.purchase_price
      FROM products p
      WHERE p.business_id = ? AND p.is_active = 1 AND p.stock > 0
        AND p.id NOT IN (
          SELECT DISTINCT product_id FROM sales 
          WHERE business_id = ? AND date >= ? AND product_id IS NOT NULL
        )
      LIMIT 5
    ''', [businessId, businessId, fourteenDaysAgo]);

    if (res.isEmpty) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: '✨ **¡Excelente rotación de catálogo!**\n\nNo tienes mercadería estancada con más de 14 días sin ventas. Todo tu inventario activo se está moviendo con normalidad.',
        timestamp: DateTime.now(),
        type: StockyMessageType.stagnantProducts,
        actions: const [
          StockyAction(label: 'Ver Inventario', actionType: 'navigate_inventory'),
        ],
      );
    }

    final buffer = StringBuffer();
    buffer.writeln('📦 **Mercadería sin movimiento reciente (+14 días):**\n');
    buffer.writeln('He detectado que estos productos tienen stock detenido sin registrar ventas en las últimas 2 semanas:\n');

    for (final row in res) {
      final name = row['name'] as String;
      final stock = (row['stock'] as num).toInt();
      final price = (row['sale_price'] as num).toDouble();
      buffer.writeln('• **$name**: $stock un. disponibles (${CurrencyFormatter.formatCOP(price)} c/u)');
    }

    buffer.writeln('\n💡 **3 Ideas para liquidar stock y liberar dinero:**\n'
        '1. **Arma un Combo 2x1:** Júntalo con tu producto más vendido.\n'
        '2. **Estado de WhatsApp:** Tómale una buena foto con precio de descuento temporal.\n'
        '3. **Ubicación visible:** Muévelo al mostrador o zona frontal de tu negocio.');

    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: buffer.toString(),
      timestamp: DateTime.now(),
      type: StockyMessageType.stagnantProducts,
      actions: const [
        StockyAction(label: 'Ver en Inventario', actionType: 'navigate_inventory'),
      ],
    );
  }

  Future<StockyAssistantMessage> _buildBusinessAdviceResponse(String businessId, String bizName, [String? prompt]) async {
    final cleanPrompt = prompt != null ? _normalize(prompt) : '';

    // Respuestas a temas específicos de asesoría empresarial
    if (cleanPrompt.contains('impulso') || cleanPrompt.contains('caja') || cleanPrompt.contains('mostrador')) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: '💡 **Venta por Impulso en Caja:**\n\n'
            'El mostrador y la caja registradora son los metros cuadrados más valiosos de tu negocio. El 30% de las decisiones de compra se toman mientras el cliente espera para pagar.\n\n'
            '👉 **Técnicas clave:**\n'
            '1. **Coloca productos de bajo costo:** Chicles, snacks, pilas, fósforos o accesorios pequeños que no requieran pensar.\n'
            '2. **La pregunta mágica:** Al cobrar, di siempre: *"¿Llevas el paquete de fósforos/dulce por solo \$1.000 más?"*\n'
            '3. **Carteles de antojo:** Un producto visible en caja con precio redondo se vende 4 veces más rápido.',
        timestamp: DateTime.now(),
        type: StockyMessageType.businessAdvice,
        actions: const [
          StockyAction(label: '+ Registrar Venta', actionType: 'quick_sale'),
          StockyAction(label: 'Ver Inventario', actionType: 'navigate_inventory'),
        ],
      );
    }

    if (cleanPrompt.contains('estancad') || cleanPrompt.contains('liquidar') || cleanPrompt.contains('combo') || cleanPrompt.contains('lento')) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: '💡 **Estrategia para Mercadería Detenida:**\n\n'
            'Tener productos quietos es tener dinero congelado que pierde valor con el tiempo y ocupa espacio valioso en tus estantes.\n\n'
            '👉 **3 Maneras de liquidar sin perder:**\n'
            '1. **Arma Combos Ganadores:** Combina un producto estancado con uno de tus más vendidos con un descuento del 10% en el combo.\n'
            '2. **Llévalos al frente:** Muchos productos no se venden simplemente porque el cliente no sabe que los tienes. Cambia su exhibición.\n'
            '3. **Oferta Flash por WhatsApp:** Publica una historia con *"Solo por hoy: últimas 5 unidades a precio especial"*.',
        timestamp: DateTime.now(),
        type: StockyMessageType.businessAdvice,
        actions: const [
          StockyAction(label: 'Ver Inventario', actionType: 'navigate_inventory'),
          StockyAction(label: '+ Registrar Venta', actionType: 'quick_sale'),
        ],
      );
    }

    if (cleanPrompt.contains('recuperar') || cleanPrompt.contains('fiado') || cleanPrompt.contains('cobrar') || cleanPrompt.contains('cartera')) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: '💡 **Estrategia de Cobranza Asertiva:**\n\n'
            'Cobrar fiados da pena a muchos comerciantes, pero el dinero es el sustento de tu negocio y familia. La clave es la constancia y la cordialidad.\n\n'
            '👉 **Reglas de oro de cobranza:**\n'
            '1. **Cobra temprano:** Entre 8:00 AM y 10:00 AM las personas suelen tener mayor disposición mental y liquidez en sus cuentas.\n'
            '2. **Usa mensajes cordiales:** Nunca acuses; saluda, desea bendiciones y comparte el saldo con gentileza.\n'
            '3. **Facilita medios de pago:** Ofrece pagar por $_localPaymentApps o pasar a recogerlo.',
        timestamp: DateTime.now(),
        type: StockyMessageType.businessAdvice,
        actions: const [
          StockyAction(label: '👥 Cobrar Fiados', actionType: 'navigate_customers'),
        ],
      );
    }

    if (cleanPrompt.contains('8020') || cleanPrompt.contains('80 20') || cleanPrompt.contains('pareto')) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: '💡 **La Ley de Pareto (80/20) en tu Negocio:**\n\n'
            'En el 90% de los comercios, el **80% de las ventas proviene de solo el 20% de tus productos** (tus "productos estrella").\n\n'
            '👉 **Cómo aplicarlo:**\n'
            '• Identifica cuáles son esos 5 o 10 productos más vendidos y **NUNCA** permitas que se te agoten.\n'
            '• Negocia mejores precios por volumen con tus proveedores para esos productos clave.\n'
            '• Si tienes poco capital para invertir, dedícalo prioritariamente a este 20% ganador.',
        timestamp: DateTime.now(),
        type: StockyMessageType.businessAdvice,
        actions: const [
          StockyAction(label: '⭐ Productos Más Vendidos', actionType: 'query_top_products'),
          StockyAction(label: 'Ver Inventario', actionType: 'navigate_inventory'),
        ],
      );
    }

    if (cleanPrompt.contains('fideliz') || cleanPrompt.contains('retener') || cleanPrompt.contains('clientes')) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: '💡 **Fidelización de Clientes:**\n\n'
            'Conseguir un cliente nuevo cuesta 5 veces más caro que retener a uno que ya te compró.\n\n'
            '👉 **Acciones de alto impacto:**\n'
            '1. **Aprende sus nombres:** Llamar a alguien por su nombre activa una conexión de confianza inmediata.\n'
            '2. **Recuerda sus gustos:** *"¿Lo de siempre, don Carlos?"* hace que el cliente sienta que el negocio es suyo.\n'
            '3. **Guarda sus contactos:** Registra a tus clientes frecuentes en Stockealo para tener su WhatsApp listo y avisarles cuando lleguen novedades.',
        timestamp: DateTime.now(),
        type: StockyMessageType.businessAdvice,
        actions: const [
          StockyAction(label: '👥 Directorio de Clientes', actionType: 'navigate_customers'),
          StockyAction(label: '+ Registrar Venta', actionType: 'quick_sale'),
        ],
      );
    }

    if (cleanPrompt.contains('precio') || cleanPrompt.contains('psicolog') || cleanPrompt.contains('margen')) {
      return StockyAssistantMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        text: '💡 **Psicología de Precios y Márgenes:**\n\n'
            'El precio no solo indica costo, también comunica valor y calidad a tus clientes.\n\n'
            '👉 **Consejos prácticos:**\n'
            '1. **Precios en .900:** \$9.900 se percibe subconscientemente más cercano a \$9.000 que a \$10.000.\n'
            '2. **Regla del 30%:** Como regla general en comercio al detal, busca márgenes brutos iguales o superiores al 30%.\n'
            '3. **No compitas solo por precio bajo:** Compite por atención rápida, amabilidad y tener siempre el producto que el cliente busca.',
        timestamp: DateTime.now(),
        type: StockyMessageType.businessAdvice,
        actions: const [
          StockyAction(label: 'Ver Inventario', actionType: 'navigate_inventory'),
          StockyAction(label: '+ Registrar Venta', actionType: 'quick_sale'),
        ],
      );
    }

    // Análisis dinámico del estado real del negocio si no es un tema puntual
    final dbSummary = await DashboardRepository.instance.getDashboardSummary(businessId, period: 'today');
    final outOfStock = dbSummary['outOfStock'] as int? ?? 0;
    final lowStock = dbSummary['lowStock'] as int? ?? 0;
    final totalDebt = dbSummary['totalDebt'] as double? ?? 0.0;
    final todayCount = dbSummary['periodCount'] as int? ?? 0;

    String advice;
    List<StockyAction> actions = [];

    if (outOfStock > 0 || lowStock > 0) {
      advice = '💡 **Consejo de Stock para $bizName:**\n\n'
          'Tienes **${outOfStock + lowStock} productos en estado crítico**. Cada día que un cliente pide un producto agotado y no lo encuentra, existe un 60% de probabilidad de que lo compre en otro negocio.\n\n'
          '👉 **Acción recomendada hoy:** Usa la herramienta de "Pedido al Proveedor" de Stockealo para consolidar la lista y enviarla directamente por WhatsApp a tus distribuidores.';
      actions = const [
        StockyAction(label: '📦 Pedido al Proveedor', actionType: 'restock_modal'),
        StockyAction(label: 'Ver Inventario', actionType: 'navigate_inventory'),
      ];
    } else if (totalDebt > 100000) {
      advice = '💡 **Consejo de Finanzas y Cobranza:**\n\n'
          'Tienes **${CurrencyFormatter.formatCOP(totalDebt)}** detenidos en fiados. Ese dinero es tu propio capital de trabajo necesario para pagar proveedores.\n\n'
          '👉 **Acción recomendada:** Dedica 10 minutos por la mañana a enviar recordatorios por WhatsApp. Los clientes aprecian los mensajes cordiales y recuperarás liquidez de inmediato.';
      actions = const [
        StockyAction(label: '👥 Cobrar Fiados', actionType: 'navigate_customers'),
      ];
    } else if (todayCount > 0) {
      advice = '💡 **Consejo para Aumentar tu Ticket Promedio:**\n\n'
          '¡Llevas buen ritmo hoy! Una técnica probada en comercios es la **venta cruzada**: cuando un cliente compre un producto, sugiérele de inmediato un accesorio o complemento diciendo "¿Llevas también el paquete de acompañamiento por solo \$2.000 más?". Aumentarás tu venta total hasta un 25% sin gastar más.';
      actions = const [
        StockyAction(label: '+ Registrar Venta', actionType: 'quick_sale'),
        StockyAction(label: 'Ver Historial', actionType: 'navigate_sales'),
      ];
    } else {
      advice = '💡 **Consejo para Activar Ventas Hoy:**\n\n'
          'Los días con ventas lentas son ideales para activar tus canales digitales:\n'
          '1. Toma 3 fotos claras a productos atractivos.\n'
          '2. Súbelas a tu Estado de WhatsApp con el precio visible y la frase *"¡Llegaron hoy! Pide el tuyo con entrega inmediata"*\n'
          '3. Saluda a 5 clientes frecuentes preguntándoles si necesitan reposición de lo habitual.';
      actions = const [
        StockyAction(label: '+ Registrar Venta', actionType: 'quick_sale'),
      ];
    }

    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: advice,
      timestamp: DateTime.now(),
      type: StockyMessageType.businessAdvice,
      actions: actions,
    );
  }

  Future<StockyAssistantMessage?> _tryFindProductInQuery(String query, String businessId) async {
    // Si la consulta contiene palabras de búsqueda
    final searchTerms = query
        .replaceAll('cuanto vale', '')
        .replaceAll('precio de', '')
        .replaceAll('tengo', '')
        .replaceAll('queda', '')
        .replaceAll('stock de', '')
        .replaceAll('hay', '')
        .replaceAll('buscar', '')
        .trim();

    if (searchTerms.length < 3) return null;

    final products = await ProductRepository.instance.getAllProducts(businessId);
    final matches = products.where((p) {
      final name = _normalize(p.name);
      final code = p.code.toLowerCase();
      return name.contains(searchTerms) || code == searchTerms;
    }).toList();

    if (matches.isEmpty) return null;

    final p = matches.first;
    final status = p.stock <= 0
        ? '🔴 **AGOTADO (0 unidades)**'
        : (p.stock <= p.minStock ? '🟠 **STOCK BAJO (${p.stock} un. restantes)**' : '🟢 **EN STOCK (${p.stock} un. disponibles)**');

    final margin = p.salePrice > 0
        ? (((p.salePrice - p.purchasePrice) / p.salePrice) * 100).toStringAsFixed(0)
        : '0';

    final text = '📦 **Ficha Rápida de Producto:**\n\n'
        '• **Nombre:** ${p.name}\n'
        '• **Categoría:** ${p.category}\n'
        '• **Estado de Stock:** $status\n'
        '• **Precio de Venta:** **${CurrencyFormatter.formatCOP(p.salePrice)}**\n'
        '• **Costo de Compra:** ${CurrencyFormatter.formatCOP(p.purchasePrice)} *(Ganancia: +$margin%)*\n'
        '• **Mínimo configurado:** ${p.minStock} unidades';

    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: text,
      timestamp: DateTime.now(),
      type: StockyMessageType.productLookup,
      actions: const [
        StockyAction(label: 'Ver en Inventario', actionType: 'navigate_inventory'),
        StockyAction(label: '+ Vender este Producto', actionType: 'quick_sale'),
      ],
      data: {'product': p},
    );
  }

  StockyAssistantMessage _buildFallbackResponse(String prompt, String bizName) {
    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: 'Entendí tu mensaje: *"$prompt"*, pero aún no tengo una respuesta programada para esa consulta. 🤖\n\n'
          'Recuerda que puedo darte información en vivo sobre **$bizName** si me preguntas:\n'
          '• **"¿Cómo va el negocio?"** o **"¿Cómo estamos hoy?"**\n'
          '• **"¿Cuánto vendimos hoy?"** o **"¿Cuál es mi ganancia?"**\n'
          '• **"¿Cuánto vale mi inventario?"** o **"¿Cuántos productos tengo?"**\n'
          '• **"¿Qué productos tienen poco stock?"** o **"¿Quién me debe?"**\n'
          '• **"¿Cómo hago una venta?"** o **"¿Cómo agrego un producto?"**\n\n'
          'O toca una de estas opciones rápidas:',
      timestamp: DateTime.now(),
      type: StockyMessageType.fallback,
      data: {'prompt': prompt},
      actions: const [
        StockyAction(label: '📈 Termómetro general', actionType: 'query_health'),
        StockyAction(label: '📊 Ventas hoy', actionType: 'query_sales'),
        StockyAction(label: '⚠️ Stock crítico', actionType: 'query_stock'),
        StockyAction(label: '💰 Valor inventario', actionType: 'query_value'),
      ],
    );
  }

  /// Método de utilidad para enviar un recordatorio cordial de WhatsApp con un toque
}
