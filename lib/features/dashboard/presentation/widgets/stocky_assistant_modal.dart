import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stocky_palette.dart';
import '../../../business/presentation/active_business_scope.dart';
import '../../../customers/data/debt_reminder.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../stocky/data/stocky_ai_service.dart';
import '../../../stocky/data/stocky_assistant_service.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/widgets/stocky_mascot.dart';
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
  String _thinkingLabel = 'Revisando tu negocio…';
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
    _loadAi();
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

  Future<void> _loadAi() async {
    final ai = StockyAiService.instance;
    await ai.load();
    if (ai.mode.value != StockyAiMode.off) ai.refreshStatus();
  }

  /// Texto del botón para gastar una pregunta, con las que quedan si se saben
  String _askAiLabel() {
    final left = StockyAiService.instance.remaining.value;
    return left == null ? 'Preguntarle a la IA' : 'Preguntarle a la IA · te quedan $left';
  }

  /// Respuesta de las reglas cuando no entendieron: según el modo de IA se deja igual,
  /// se le agrega el botón de la IA o se pregunta directamente
  StockyAssistantMessage _withAiOffer(StockyAssistantMessage response) {
    if (response.type != StockyMessageType.fallback) return response;
    final mode = StockyAiService.instance.mode.value;
    if (mode == StockyAiMode.off) return response;
    final prompt = response.data?['prompt'] as String? ?? '';
    return StockyAssistantMessage(
      id: response.id,
      isUser: false,
      text: 'Esa pregunta todavía no la sé responder con mis reglas. '
          'Puedo consultarla con la IA (usa 1 de tus preguntas de hoy) o puedes tocar una opción:',
      timestamp: response.timestamp,
      type: StockyMessageType.fallback,
      data: response.data,
      actions: [
        StockyAction(label: _askAiLabel(), actionType: 'ask_ai', payload: prompt),
        ...response.actions,
      ],
    );
  }

  Future<void> _askAi(String prompt) async {
    if (prompt.trim().isEmpty || _isThinking) return;
    setState(() {
      _isThinking = true;
      _thinkingLabel = 'Preguntándole a la IA…';
      _mascotState = StockyState.loading;
    });
    _scrollToBottom();

    final result = await StockyAiService.instance.ask(prompt, _effectiveBusinessId);
    if (!mounted) return;

    final message = StockyAssistantMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      isUser: false,
      text: result.ok ? result.answer! : result.errorMessage,
      timestamp: DateTime.now(),
      type: result.ok ? StockyMessageType.aiAnswer : StockyMessageType.text,
      data: result.ok ? {'remaining': result.remaining, 'cached': result.cached} : null,
    );
    StockyAssistantService.instance.addMessage(_effectiveBusinessId, message);
    setState(() {
      _messages.add(message);
      _isThinking = false;
      _thinkingLabel = 'Revisando tu negocio…';
      _mascotState = result.ok ? StockyState.success : StockyState.idle;
    });
    _scrollToBottom();
  }

  void _initSession() {
    final user = AuthRepository.instance.currentUser;
    if (user != null) {
      _userName = user.displayName.isNotEmpty ? user.displayName : user.email.split('@')[0];
    }
    final activeBiz = ActiveBusinessScope.read(context);
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
      final ruleResponse = await StockyAssistantService.instance.processQuery(
        prompt: query,
        businessId: _effectiveBusinessId,
        userName: _userName,
      );

      // Modo automático: lo que las reglas no entienden va directo a la IA
      if (ruleResponse.type == StockyMessageType.fallback &&
          StockyAiService.instance.mode.value == StockyAiMode.auto) {
        if (!mounted) return;
        setState(() => _isThinking = false);
        await _askAi(query);
        return;
      }
      final response = _withAiOffer(ruleResponse);

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
    final activeBiz = ActiveBusinessScope.read(context);

    switch (action.actionType) {
      case 'ask_ai':
        _askAi(action.payload as String? ?? '');
        break;

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
    final c = context.colors;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;

    // Altura óptima (60% de la pantalla) para no tapar todo el fondo
    final modalHeight = (mediaQuery.size.height * 0.60).clamp(400.0, 580.0);
    final radius = BorderRadius.circular(AppRadius.sheet);

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpace.sm + 2,
            right: AppSpace.sm + 2,
            bottom: bottomInset > 0 ? bottomInset + AppSpace.sm : AppSpace.md,
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              height: modalHeight,
              width: math.min(mediaQuery.size.width - 20, 500.0),
              decoration: BoxDecoration(
                color: c.paper,
                borderRadius: radius,
                border: Border.all(color: c.line),
                // Flota sobre la app: única sombra, suave
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 28, offset: const Offset(0, 8))],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Column(
                  children: [
                    _header(c),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                        itemCount: _messages.length + (_isThinking ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length && _isThinking) return _buildThinkingBubble(c);
                          return _buildMessageItem(_messages[index], c);
                        },
                      ),
                    ),
                    _suggestions(c),
                    _input(c),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(StockealoColors c, {required double size, StockyState state = StockyState.idle}) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: StockyPalette.halo),
        child: Center(child: StockyMascot(size: size * 0.82, state: state)),
      );

  Widget _header(StockealoColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.xs, AppSpace.sm),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          _avatar(c, size: 44, state: _mascotState),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('Stocky', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.ink)),
                    const SizedBox(width: AppSpace.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.surfaceMuted,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'BETA',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: c.inkMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: c.success, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('En línea', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                  ],
                ),
              ],
            ),
          ),
          _aiModeButton(c),
          IconButton(
            icon: Icon(Icons.refresh_rounded, size: 21, color: c.inkMuted),
            tooltip: 'Reiniciar conversación',
            onPressed: _resetChat,
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 22, color: c.inkMuted),
            tooltip: 'Cerrar',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _aiModeButton(StockealoColors c) {
    final ai = StockyAiService.instance;
    return ValueListenableBuilder<StockyAiMode>(
      valueListenable: ai.mode,
      builder: (context, mode, _) {
        final on = mode != StockyAiMode.off;
        return PopupMenuButton<StockyAiMode>(
          tooltip: 'IA de Stocky: ${mode.label}',
          initialValue: mode,
          position: PopupMenuPosition.under,
          onSelected: (value) {
            ai.setMode(value);
            if (value != StockyAiMode.off) ai.refreshStatus();
          },
          itemBuilder: (_) => [
            PopupMenuItem<StockyAiMode>(
              enabled: false,
              child: ValueListenableBuilder<int?>(
                valueListenable: ai.remaining,
                builder: (_, left, __) => Text(
                  left == null ? 'IA de Stocky' : 'IA de Stocky · te quedan $left hoy',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.inkMuted),
                ),
              ),
            ),
            for (final option in StockyAiMode.values)
              PopupMenuItem<StockyAiMode>(
                value: option,
                child: SizedBox(
                  width: 240,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          option == mode ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                          size: 18,
                          color: option == mode ? c.accent : c.inkFaint,
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm + 2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(option.label, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                            const SizedBox(height: 2),
                            Text(option.description, style: TextStyle(fontSize: 12.5, height: 1.3, color: c.inkMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          child: Container(
            margin: const EdgeInsets.only(right: AppSpace.xs),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm + 2, vertical: 6),
            decoration: BoxDecoration(
              color: on ? c.accent.withOpacity(0.12) : c.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 15, color: on ? c.accent : c.inkMuted),
                const SizedBox(width: 4),
                Text(
                  on ? 'IA' : 'IA no',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: on ? c.accent : c.inkMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _suggestions(StockealoColors c) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        itemCount: _quickChips.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (context, i) {
          final chip = _quickChips[i];
          return ActionChip(
            label: Text(chip['label']!),
            onPressed: () => _handleSendMessage(chip['prompt']!),
            backgroundColor: c.surface,
            side: BorderSide(color: c.line),
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
            shape: const StadiumBorder(),
          );
        },
      ),
    );
  }

  Widget _input(StockealoColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              style: TextStyle(fontSize: 15, color: c.ink),
              textInputAction: TextInputAction.send,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _handleSendMessage(),
              decoration: InputDecoration(
                hintText: 'Pregúntale algo a Stocky…',
                filled: true,
                fillColor: c.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  borderSide: BorderSide(color: c.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  borderSide: BorderSide(color: c.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  borderSide: BorderSide(color: c.accent, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Semantics(
            button: true,
            label: 'Enviar',
            child: Material(
              color: c.accent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _handleSendMessage(),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.arrow_upward_rounded, color: c.onAccent, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _stockyBubbleRadius = BorderRadius.only(
    topRight: Radius.circular(18),
    bottomLeft: Radius.circular(18),
    bottomRight: Radius.circular(18),
  );

  Widget _buildThinkingBubble(StockealoColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.sm + 2, top: 2),
            child: _avatar(c, size: 32, state: StockyState.loading),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: _stockyBubbleRadius,
              border: Border.all(color: c.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
                const SizedBox(width: AppSpace.sm + 2),
                Text(_thinkingLabel, style: TextStyle(fontSize: 13, color: c.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(StockyAssistantMessage msg, StockealoColors c) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpace.md, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 11),
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
            ),
          ),
          child: Text(msg.text, style: TextStyle(fontSize: 14.5, color: c.onAccent, height: 1.35)),
        ),
      );
    }

    // Mensaje de Stocky (con avatar a la izquierda)
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.sm + 2, top: 2),
            child: _avatar(c, size: 34),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: _stockyBubbleRadius,
                    border: Border.all(color: c.line),
                  ),
                  child: _buildFormattedText(msg.text, c),
                ),
                if (msg.type == StockyMessageType.aiAnswer) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 13, color: c.inkFaint),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _aiFooter(msg),
                          style: TextStyle(fontSize: 11.5, color: c.inkFaint),
                        ),
                      ),
                    ],
                  ),
                ],
                if (msg.actions.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: 6,
                    children: [for (final act in msg.actions) _buildActionPill(act, c)],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _aiFooter(StockyAssistantMessage msg) {
    final left = msg.data?['remaining'];
    const base = 'Respuesta con IA, puede tener errores';
    return left is int ? '$base · te quedan $left hoy' : base;
  }

  Widget _buildActionPill(StockyAction action, StockealoColors c) {
    final (IconData icon, Color color) = switch (action.actionType) {
      'navigate_sales' => (Icons.point_of_sale_rounded, c.info),
      'navigate_inventory' => (Icons.inventory_2_outlined, c.accent),
      'navigate_customers' => (Icons.people_outline_rounded, c.warning),
      'quick_sale' => (Icons.add_shopping_cart_rounded, c.accent),
      'restock_modal' => (Icons.local_shipping_outlined, c.danger),
      'whatsapp_debtor' => (Icons.chat_bubble_outline_rounded, c.success),
      'ask_ai' => (Icons.auto_awesome_rounded, c.accent),
      _ => (Icons.arrow_forward_rounded, c.accent),
    };
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => _handleActionTap(action),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(action.label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildFormattedText(String text, StockealoColors c) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.trim().isEmpty) return const SizedBox(height: 6);
        // Las viñetas "- " o "* " (comunes en respuestas de la IA) se muestran como "• "
        line = line.replaceFirst(RegExp(r'^\s*[-*]\s+'), '• ');
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 14, height: 1.42, color: c.ink),
              children: _parseMarkdownSpans(line, c.ink),
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
