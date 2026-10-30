import '../../../customers/data/debt_reminder.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../stocky/data/stocky_assistant_service.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/widgets/stocky_mascot.dart';
import '../../../business/data/business_repository.dart';
import '../../../customers/presentation/screens/customers_screen.dart';
import '../../../products/presentation/widgets/restock_order_modal.dart';
import '../../../sales/presentation/widgets/quick_sale_dialog.dart';

class StockyAssistantModal extends StatefulWidget {
  final String? businessId;
  final ValueChanged<int>? onNavigateToTab;
  final String? initialPrompt;

  const StockyAssistantModal({
    super.key,
    this.businessId,
    this.onNavigateToTab,
    this.initialPrompt,
  });

  static Future<void> show(
    BuildContext context, {
    String? businessId,
    ValueChanged<int>? onNavigateToTab,
    String? initialPrompt,
  }) {
    HapticFeedback.lightImpact();
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar asistente',
      barrierColor: Colors.black.withOpacity(0.40),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim, secondaryAnim) {
        return StockyAssistantModal(
          businessId: businessId,
          onNavigateToTab: onNavigateToTab,
          initialPrompt: initialPrompt,
        );
      },
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curve = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return Transform.scale(
          scale: Tween<double>(begin: 0.78, end: 1.0).evaluate(curve),
          alignment: const Alignment(0.85, 0.90), // Nace orgánicamente desde la esquina de Stocky
          child: FadeTransition(
            opacity: curve,
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<StockyAssistantModal> createState() => _StockyAssistantModalState();
}

class _StockyAssistantModalState extends State<StockyAssistantModal> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<StockyAssistantMessage> _messages = [];

  bool _isThinking = false;
  StockyState _mascotState = StockyState.idle;
  String _effectiveBusinessId = '';
  String _userName = 'Comerciante';

  // Sugerencias rápidas tipo chip para consulta inmediata con 1 tap
  static const List<Map<String, String>> _quickChips = [
    {'label': '📈 Termómetro negocio', 'prompt': 'como va el negocio'},
    {'label': '📊 Ventas de hoy', 'prompt': 'ventas de hoy'},
    {'label': '⚠️ Stock crítico', 'prompt': 'stock critico y agotados'},
    {'label': '💰 Valor inventario', 'prompt': 'cuanto vale mi inventario'},
    {'label': '👥 Fiados pendientes', 'prompt': 'quien me debe dinero'},
    {'label': '🏆 Más vendidos', 'prompt': 'cuales son los productos mas vendidos'},
    {'label': '💡 Consejo de hoy', 'prompt': 'dame un consejo para vender mas'},
    {'label': '💰 Ganancia de hoy', 'prompt': 'cual es mi ganancia de hoy'},
    {'label': '📦 Mercadería estancada', 'prompt': 'que mercaderia esta estancada'},
  ];

  @override
  void initState() {
    super.initState();
    _initSession();
    if (widget.initialPrompt != null && widget.initialPrompt!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleSendMessage(widget.initialPrompt!);
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initSession() {
    final user = AuthRepository.instance.currentUser;
    if (user != null) {
      _userName = user.displayName.isNotEmpty ? user.displayName : user.email.split('@')[0];
    }
    final activeBiz = BusinessRepository.instance.currentActiveBusiness;
    _effectiveBusinessId = widget.businessId ?? activeBiz?.id ?? '';

    // Si no hay historial previo para este negocio en la sesión activa, inicializamos con el mensaje de bienvenida
    if (!StockyAssistantService.instance.hasConversation(_effectiveBusinessId)) {
      final bizName = activeBiz?.name ?? 'tu negocio';
      final welcome = StockyAssistantMessage(
        id: 'welcome_msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: '¡Hola $_userName! 👋 Soy **Stocky**, tu asistente de negocio para **$bizName**.\n\n'
            '¿Qué te gustaría saber hoy? Puedo analizar tus ventas, avisarte qué stock debes reponer, recordarte tus fiados pendientes o darte consejos de venta.',
        timestamp: DateTime.now(),
        type: StockyMessageType.text,
      );
      StockyAssistantService.instance.addMessage(_effectiveBusinessId, welcome);
    }

    _messages.clear();
    _messages.addAll(StockyAssistantService.instance.getConversation(_effectiveBusinessId));

    _scrollToBottom(animate: false);
  }

  Future<void> _handleSendMessage([String? overrideText]) async {
    final query = (overrideText ?? _textController.text).trim();
    if (query.isEmpty) return;

    if (overrideText == null) {
      _textController.clear();
    }

    HapticFeedback.lightImpact();

    // Guardar y mostrar mensaje del usuario
    final userMsg = StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: true,
      text: query,
      timestamp: DateTime.now(),
    );
    StockyAssistantService.instance.addMessage(_effectiveBusinessId, userMsg);

    setState(() {
      _messages.add(userMsg);
      _isThinking = true;
      _mascotState = StockyState.loading;
    });

    _scrollToBottom();

    // Pequeño retardo natural de procesamiento (350ms) para sensación de asistencia fluida
    await Future.delayed(const Duration(milliseconds: 350));

    if (!mounted) return;

    try {
      final response = await StockyAssistantService.instance.processQuery(
        prompt: query,
        businessId: _effectiveBusinessId,
        userName: _userName,
      );

      StockyAssistantService.instance.addMessage(_effectiveBusinessId, response);

      if (mounted) {
        setState(() {
          _messages.add(response);
          _isThinking = false;
          _mascotState = StockyState.success;
        });
        _scrollToBottom();

        // Volver a estado idle tras celebrar
        Future.delayed(const Duration(milliseconds: 1800), () {
          if (mounted && _mascotState == StockyState.success) {
            setState(() => _mascotState = StockyState.idle);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = StockyAssistantMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          isUser: false,
          text: 'Ups, ocurrió un detalle al consultar los datos locales. Intenta preguntarme de nuevo.',
          timestamp: DateTime.now(),
        );
        StockyAssistantService.instance.addMessage(_effectiveBusinessId, errorMsg);

        setState(() {
          _messages.add(errorMsg);
          _isThinking = false;
          _mascotState = StockyState.idle;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (animate) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 80,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  void _resetChat() {
    HapticFeedback.mediumImpact();
    StockyAssistantService.instance.clearConversation(_effectiveBusinessId);
    setState(() {
      _messages.clear();
      _isThinking = false;
      _mascotState = StockyState.idle;
      _initSession();
    });
  }

  void _handleActionTap(StockyAction action) async {
    HapticFeedback.selectionClick();
    final activeBiz = BusinessRepository.instance.currentActiveBusiness;

    switch (action.actionType) {
      case 'query_sales':
      case 'query_stock':
      case 'query_debts':
      case 'query_advice':
      case 'query_top':
      case 'query_health':
      case 'query_value':
        final prompt = action.label.replaceAll(RegExp(r'[^\w\s]'), '').trim();
        _handleSendMessage(prompt);
        break;

      case 'navigate_sales':
        Navigator.pop(context);
        if (widget.onNavigateToTab != null) {
          widget.onNavigateToTab!(2);
        }
        break;

      case 'navigate_inventory':
        Navigator.pop(context);
        if (widget.onNavigateToTab != null) {
          widget.onNavigateToTab!(1);
        }
        break;

      case 'navigate_customers':
        if (activeBiz != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CustomersScreen(businessId: activeBiz.id),
            ),
          );
        }
        break;

      case 'quick_sale':
        Navigator.pop(context);
        QuickSaleDialog.show(context);
        break;

      case 'restock_modal':
        if (activeBiz != null) {
          Navigator.pop(context);
          RestockOrderModal.show(context, business: activeBiz, userName: _userName);
        }
        break;

      case 'whatsapp_debtor':
        if (action.payload is Map<String, dynamic>) {
          final payload = action.payload as Map<String, dynamic>;
          final cName = payload['customerName'] as String? ?? 'Cliente';
          final dAmount = (payload['debtAmount'] as num?)?.toDouble() ?? 0.0;
          final bName = payload['bizName'] as String? ?? 'Mi Negocio';
          DebtReminder.send(
            customerName: cName,
            debtAmount: dAmount,
            businessName: bName,
            phone: payload['phone'] as String?,
          );
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;

    // Altura óptima (60% de la pantalla) para no tapar todo el fondo
    final modalHeight = (screenHeight * 0.60).clamp(400.0, 580.0);

    // Paleta Obsidian Violet Bento
    final sheetBg = isDark ? const Color(0xFF0F0E1E) : Colors.white;
    final headerBg = isDark ? const Color(0xFF16142B) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF27214E) : const Color(0xFFE2E8F0);
    final textMain = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
            left: 10,
            right: 10,
            bottom: bottomInset > 0 ? bottomInset + 8 : 12,
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              height: modalHeight,
              width: math.min(screenWidth - 20, 500.0),
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: borderColor, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 30,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Column(
                  children: [

          // Header de Stocky Asistente
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(bottom: BorderSide(color: borderColor, width: 1)),
            ),
            child: Row(
              children: [
                // Mascota Animada Stocky
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF1E1A3C) : const Color(0xFFECFDF5),
                    border: Border.all(
                      color: const Color(0xFF10B981).withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: StockyMascot(
                      size: 38,
                      state: _mascotState,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Título y Estado En Línea
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Stocky',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: textMain,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withOpacity(0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'BETA',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF8B5CF6),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6.5,
                            height: 6.5,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'En línea',
                            style: TextStyle(
                              fontSize: 11,
                              color: textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Botón Reiniciar Chat
                IconButton(
                  icon: Icon(Icons.refresh_rounded, size: 20, color: textMuted),
                  tooltip: 'Reiniciar conversación',
                  onPressed: _resetChat,
                  splashRadius: 20,
                ),

                // Botón Cerrar
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 22, color: textMuted),
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  splashRadius: 20,
                ),
              ],
            ),
          ),

          // Lista de Mensajes del Chat
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              itemCount: _messages.length + (_isThinking ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isThinking) {
                  return _buildThinkingBubble(isDark);
                }
                final msg = _messages[index];
                return _buildMessageItem(msg, isDark);
              },
            ),
          ),

          // Carrusel de Sugerencias Rápidas
          Container(
            height: 38,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _quickChips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final chip = _quickChips[i];
                return InkWell(
                  onTap: () => _handleSendMessage(chip['prompt']!),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1A3C) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark ? const Color(0xFF342B63) : const Color(0xFFCBD5E1),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      chip['label']!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Campo de Entrada de Texto con Botón Enviar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF181530) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark ? const Color(0xFF30285C) : const Color(0xFFCBD5E1),
                        width: 1.2,
                      ),
                    ),
                    child: TextField(
                      controller: _textController,
                      style: TextStyle(fontSize: 14, color: textMain),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Pregúntale algo a Stocky...',
                        hintStyle: TextStyle(fontSize: 13.5, color: textMuted),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _handleSendMessage(),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF8B5CF6), Color(0xFF059669)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
),
),
),
);
  }

  Widget _buildThinkingBubble(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0xFF221C46) : const Color(0xFFECFDF5),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
            ),
            child: const Center(
              child: StockyMascot(size: 26, state: StockyState.loading),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF181530) : const Color(0xFFF1F5F9),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(
                color: isDark ? const Color(0xFF2C2456) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF8B5CF6)),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Stocky está consultando tu negocio...',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(StockyAssistantMessage msg, bool isDark) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            msg.text,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
      );
    }

    // Mensaje de Stocky (con avatar a la izquierda)
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0xFF221C46) : const Color(0xFFECFDF5),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35)),
            ),
            child: const Center(
              child: StockyMascot(size: 28, state: StockyState.idle),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF181530) : const Color(0xFFF8FAFC),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(
                      color: isDark ? const Color(0xFF2C2456) : const Color(0xFFE2E8F0),
                      width: 1.1,
                    ),
                  ),
                  child: _buildFormattedText(msg.text, isDark),
                ),

                // Botones de acción embebidos
                if (msg.actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: msg.actions.map((act) {
                      return _buildActionPill(act, isDark);
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionPill(StockyAction action, bool isDark) {
    IconData icon;
    Color color;

    switch (action.actionType) {
      case 'navigate_sales':
        icon = Icons.point_of_sale;
        color = const Color(0xFF2563EB);
        break;
      case 'navigate_inventory':
        icon = Icons.inventory_2_outlined;
        color = const Color(0xFF10B981);
        break;
      case 'navigate_customers':
        icon = Icons.people_outline;
        color = const Color(0xFFD97706);
        break;
      case 'quick_sale':
        icon = Icons.add_shopping_cart;
        color = const Color(0xFF059669);
        break;
      case 'restock_modal':
        icon = Icons.local_shipping_outlined;
        color = const Color(0xFFDC2626);
        break;
      case 'whatsapp_debtor':
        icon = Icons.chat_bubble_outline;
        color = const Color(0xFF16A34A);
        break;
      default:
        icon = Icons.arrow_forward_rounded;
        color = const Color(0xFF8B5CF6);
    }

    return InkWell(
      onTap: () => _handleActionTap(action),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              action.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormattedText(String text, bool isDark) {
    final textMain = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final lines = text.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.trim().isEmpty) {
          return const SizedBox(height: 6);
        }

        // Parsear spans para **negrita** e *itálica*
        final spans = _parseMarkdownSpans(line, textMain);

        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 13.5,
                height: 1.42,
                color: textMain,
              ),
              children: spans,
            ),
          ),
        );
      }).toList(),
    );
  }

  List<InlineSpan> _parseMarkdownSpans(String line, Color baseColor) {
    final List<InlineSpan> spans = [];
    final pattern = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*)');
    int lastMatchEnd = 0;

    for (final match in pattern.allMatches(line)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: line.substring(lastMatchEnd, match.start),
          style: TextStyle(color: baseColor),
        ));
      }

      final matchedText = match.group(0)!;
      if (matchedText.startsWith('**') && matchedText.endsWith('**')) {
        spans.add(TextSpan(
          text: matchedText.substring(2, matchedText.length - 2),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: baseColor,
          ),
        ));
      } else if (matchedText.startsWith('*') && matchedText.endsWith('*')) {
        spans.add(TextSpan(
          text: matchedText.substring(1, matchedText.length - 1),
          style: TextStyle(
            fontStyle: FontStyle.italic,
            color: baseColor.withOpacity(0.85),
          ),
        ));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < line.length) {
      spans.add(TextSpan(
        text: line.substring(lastMatchEnd),
        style: TextStyle(color: baseColor),
      ));
    }

    return spans;
  }
}
