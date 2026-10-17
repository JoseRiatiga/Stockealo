import 'package:share_plus/share_plus.dart';
import '../../features/business/data/business_repository.dart';
import '../../features/customers/data/customer_repository.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../features/products/data/product_repository.dart';
import '../../features/sales/data/sales_repository.dart';
import '../../core/utils/currency_formatter.dart';
import '../database/app_database.dart';

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

  /// Procesa una consulta en lenguaje natural u opción rápida y retorna la respuesta inteligente de Stocky
  Future<StockyAssistantMessage> processQuery({
    required String prompt,
    required String businessId,
    String? userName,
  }) async {
    final cleanPrompt = _normalize(prompt);
    final business = BusinessRepository.instance.currentActiveBusiness;
    final bizName = business?.name ?? 'tu negocio';

    // 1. Saludos y bienvenida
    if (_isGreeting(cleanPrompt)) {
      return _buildGreetingResponse(userName, bizName);
    }

    // 2. Ayuda general
    if (_isHelp(cleanPrompt)) {
      return _buildHelpResponse();
    }

    // 3. Ventas de hoy
    if (_isSalesToday(cleanPrompt)) {
      return await _buildSalesTodayResponse(businessId, bizName);
    }

    // 4. Ganancias / Rentabilidad
    if (_isProfit(cleanPrompt)) {
      return await _buildProfitResponse(businessId, bizName);
    }

    // 5. Stock Crítico / Agotados / Inventario
    if (_isLowStock(cleanPrompt)) {
      return await _buildLowStockResponse(businessId);
    }

    // 6. Fiados / Cuentas por Cobrar / Deudas
    if (_isDebts(cleanPrompt)) {
      return await _buildDebtsResponse(businessId, bizName);
    }

    // 7. Productos más vendidos (Top)
    if (_isTopProducts(cleanPrompt)) {
      return await _buildTopProductsResponse(businessId);
    }

    // 8. Mercadería estancada / Sin movimiento
    if (_isStagnantProducts(cleanPrompt)) {
      return await _buildStagnantProductsResponse(businessId);
    }

    // 9. Consejos de negocio
    if (_isAdvice(cleanPrompt)) {
      return await _buildBusinessAdviceResponse(businessId, bizName);
    }

    // 10. Búsqueda específica de un producto en inventario
    final productLookup = await _tryFindProductInQuery(cleanPrompt, businessId);
    if (productLookup != null) {
      return productLookup;
    }

    // 11. Fallback contextual amable
    return _buildFallbackResponse(prompt);
  }

  // ==========================================
  // CLASIFICADORES DE INTENCIÓN (NLP RULES)
  // ==========================================

  bool _isGreeting(String text) {
    final regex = RegExp(r'\b(hola|buen(os|as)?\s*(dias|tardes|noches)?|hey|saludos|que tal|quien eres|stocky)\b');
    return regex.hasMatch(text) && text.split(' ').length <= 4;
  }

  bool _isHelp(String text) {
    return text.contains('que puedes hacer') ||
        text.contains('como funcionas') ||
        text.contains('ayuda') ||
        text.contains('comandos') ||
        text.contains('opciones');
  }

  bool _isSalesToday(String text) {
    if (text.contains('venta') || text.contains('vendi') || text.contains('factur') || text.contains('caja') || text.contains('ingreso')) {
      return text.contains('hoy') || text.contains('dia') || text.contains('cuanto') || text.contains('como van') || text.contains('resumen');
    }
    return text.contains('ventas de hoy') || text.contains('como van las ventas') || text.contains('cuanto vendimos');
  }

  bool _isProfit(String text) {
    return text.contains('ganancia') ||
        text.contains('margen') ||
        text.contains('utilidad') ||
        text.contains('beneficio') ||
        text.contains('rentabilidad');
  }

  bool _isLowStock(String text) {
    return text.contains('stock') ||
        text.contains('agotado') ||
        text.contains('acabando') ||
        text.contains('falta') ||
        text.contains('critico') ||
        text.contains('reponer') ||
        text.contains('proveedor') ||
        text.contains('mercancia baja') ||
        text.contains('inventario bajo');
  }

  bool _isDebts(String text) {
    return text.contains('fiado') ||
        text.contains('deuda') ||
        text.contains('deben') ||
        text.contains('cobrar') ||
        text.contains('cartera') ||
        text.contains('quien me debe') ||
        text.contains('cuentas por cobrar');
  }

  bool _isTopProducts(String text) {
    return text.contains('mas vendido') ||
        text.contains('top') ||
        text.contains('estrella') ||
        text.contains('populares') ||
        text.contains('mas salida') ||
        text.contains('mejores productos');
  }

  bool _isStagnantProducts(String text) {
    return text.contains('estancad') ||
        text.contains('no se vende') ||
        text.contains('no se mueve') ||
        text.contains('lento') ||
        text.contains('muert') ||
        text.contains('sin movimiento') ||
        text.contains('quedado');
  }

  bool _isAdvice(String text) {
    return text.contains('consejo') ||
        text.contains('tip') ||
        text.contains('sugerencia') ||
        text.contains('recomendacion') ||
        text.contains('como vender mas') ||
        text.contains('estrategia') ||
        text.contains('que hago');
  }

  String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .trim();
  }

  // ==========================================
  // GENERADORES DE RESPUESTAS CON CONTEXTO REAL
  // ==========================================

  StockyAssistantMessage _buildGreetingResponse(String? userName, String bizName) {
    final nameStr = userName != null && userName.isNotEmpty ? ' $userName' : '';
    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: '¡Hola$nameStr! 👋 Soy **Stocky**, tu copiloto comercial para **$bizName**.\n\nEstoy aquí para darte respuestas al instante sobre tus ventas, alertas de stock, cuentas por cobrar y consejos de negocio en tiempo real.\n\n¿Qué te gustaría revisar hoy?',
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
          'Todo funciona **100% offline**, sin costos de internet ni demoras.',
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
    buffer.writeln('Tienes **$totalCritical productos** que requieren reposición inmediata para no perder ventas:\n');

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

  Future<StockyAssistantMessage> _buildBusinessAdviceResponse(String businessId, String bizName) async {
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

  StockyAssistantMessage _buildFallbackResponse(String prompt) {
    return StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: 'Entendí tu mensaje: *"$prompt"*, pero aún estoy aprendiendo patrones específicos sobre eso. 🤖\n\n'
          'Puedes preguntarme con naturalidad sobre:\n'
          '• **"¿Cuánto vendimos hoy?"**\n'
          '• **"¿Qué productos tienen poco stock?"**\n'
          '• **"¿Quién me debe dinero?"**\n'
          '• **"¿Cuáles son los más vendidos?"**\n'
          '• **"¿Qué mercadería está estancada?"**\n'
          '• O toca uno de los accesos directos:',
      timestamp: DateTime.now(),
      type: StockyMessageType.text,
      actions: const [
        StockyAction(label: '📊 Ventas hoy', actionType: 'query_sales'),
        StockyAction(label: '⚠️ Stock crítico', actionType: 'query_stock'),
        StockyAction(label: '👥 Fiados', actionType: 'query_debts'),
        StockyAction(label: '💡 Consejo del día', actionType: 'query_advice'),
      ],
    );
  }

  /// Método de utilidad para enviar un recordatorio cordial de WhatsApp con un toque
  static void sendWhatsAppReminder({
    required String customerName,
    required double debtAmount,
    required String bizName,
  }) {
    final text = 'Hola $customerName 👋 Te saluda $bizName. Esperamos que te encuentres muy bien. Te compartimos un recordatorio cordial de tu saldo pendiente de ${CurrencyFormatter.formatCOP(debtAmount)} con nosotros. ¡Muchas gracias por tu preferencia y confianza!';
    Share.share(text, subject: 'Recordatorio cordial - $bizName');
  }
}
