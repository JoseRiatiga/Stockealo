import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/design/pro_crown.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/models/business.dart';
import '../../data/pro_admin_service.dart';
import '../../data/pro_service.dart';
import '../widgets/plan_finder.dart';

/// Lo que suma Pro (también lo muestra la ventana de Pro). Todo lo demás sigue gratis.
/// Correo de soporte (el mismo de los Términos y la Política de privacidad)
const proSupportEmail = 'byjosealbert@gmail.com';

const proBenefits = [
  (Icons.storefront_outlined, 'Tienda en línea', 'Tu catálogo con carrito; los pedidos te llegan por WhatsApp.'),
  (Icons.notifications_active_outlined, 'Cobro automático de fiados', 'Recordatorios programados y estado de cuenta en PDF.'),
  (Icons.auto_awesome_mosaic_outlined, 'Catálogos sin marca de agua', 'Más plantillas y colores, sin la marca de agua de Stockealo.'),
  (Icons.auto_awesome_outlined, 'Más preguntas a Stocky', '50 preguntas a la IA al día en vez de 10.'),
  // El quinto va con ProBenefit.staff (el orden importa: la ventana de Pro resalta por posición)
  (Icons.admin_panel_settings_outlined, 'Roles y límites del equipo', 'Roles sin límite y topes por rol: descuento, anular, fiar.'),
  (Icons.sell_outlined, 'Precio por mayor', 'Desde cierta cantidad, un precio más bajo; Vender y la tienda lo aplican solos.'),
  (Icons.flag_outlined, 'Metas por persona', 'Metas de ventas de cada persona del equipo, con su historial.'),
  (Icons.local_offer_outlined, 'Cupones de la tienda', 'Varios cupones activos a la vez para tus clientes.'),
];

/// Lo que ya trae el plan gratis (0.17.0: comparación de los tres planes)
const freeBenefits = [
  'Inventario, Vender y Caja',
  'Fiados y abonos',
  'Reportes y Excel',
  'Contar inventario',
  'Pedido sugerido',
  'Equipo, 1 rol propio',
  'Catálogo con marca de agua de Stockealo',
  'Stocky: 10 preguntas al día',
];

/// Lo que suma Pro Servicios además de todo Pro
const proServicesBenefits = [
  (Icons.view_kanban_outlined, 'Módulo Servicios', 'Tablero de trabajos, cola por orden de llegada y asistencia del equipo.'),
  (Icons.groups_outlined, 'Empleados sin límite', 'Gratis y con Pro son hasta 3.'),
  // 0.18.7: lo de las sedes también va en Pro Servicios
  (Icons.storefront_outlined, 'Principal + 2 sedes incluidas', 'Cada sede con su stock y su caja; puedes sumar más sedes.'),
  (Icons.swap_horiz_outlined, 'Traslados entre sedes', 'Envía mercancía de una sede a otra y recíbela contando lo que llegó.'),
  (Icons.payments_outlined, 'Comisiones y liquidaciones', 'Lo que gana cada empleado por servicio, para pagar por día, semana o mes.'),
  (Icons.event_available_outlined, 'Agenda y reservas en línea', 'Tus clientes reservan desde tu tienda con la hora de tu negocio.'),
  (Icons.schedule_outlined, 'Horario de acceso', 'Cada persona entra a la app solo en sus días y horas.'),
  (Icons.support_agent_outlined, 'Soporte incluido', 'Te ayudamos a configurarlo para tu negocio.'),
];

/// Stockealo Pro: estado del negocio, planes, pago por Nequi y canje de códigos
class ProScreen extends StatefulWidget {
  final Business business;

  /// Abre bajando hasta el canje de código (para "Ya tengo un código")
  final bool focusCode;

  const ProScreen({super.key, required this.business, this.focusCode = false});

  static Future<void> open(BuildContext context, Business business, {bool focusCode = false}) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => ProScreen(business: business, focusCode: focusCode)));

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();
  final _scroll = ScrollController();
  late final Future<(List<ProPlan>, Map<String, String>)> _data = _load();
  String? _selectedPlanId;

  /// Selector Mensual / Anual de la comparación (0.17.1)
  bool _annual = false;
  bool _redeeming = false;

  /// Pago en línea con Wompi en curso / mostrar el pago manual por Nequi
  bool _paying = false;
  bool _showManual = false;

  /// Cupón de descuento al pagar con Wompi (0.16.0): el código y el precio para el plan elegido
  final _couponController = TextEditingController();
  bool _showCoupon = false;
  bool _checkingCoupon = false;
  String? _couponError;
  ({String code, double price, double regular, String planId})? _coupon;

  /// Sedes extra (0.18.3): cuántas van con el plan elegido y su precio, que calcula la
  /// nube. [_addSlots] / [_addQuote]: comprar solo sedes con el plan vigente.
  int _slots = 0;
  BranchSlotQuote? _slotQuote;
  String? _slotQuotePlan;
  bool _quotingSlots = false;
  int _quoteSeq = 0;
  int _addSlots = 1;
  BranchSlotQuote? _addQuote;
  bool _quotingAdd = false;
  int _addSeq = 0;

  /// Subir a Pro Servicios (0.18.3): descuento por lo que le queda de Pro pagado,
  /// calculado en la nube para el plan [_upgradePlan]
  UpgradeQuote? _upgrade;
  String? _upgradePlan;
  bool _quotingUpgrade = false;
  int _upgradeSeq = 0;

  /// Cuenta administradora: puede probar Wompi con la llave de pruebas
  bool _isAdmin = false;
  String? _codeError;

  /// Precio de las sedes extra por plan (0.18.7), para la comparación
  Map<String, SlotPrice> _slotPrices = const {};

  Future<(List<ProPlan>, Map<String, String>)> _load() async {
    final pro = ProService.instance;
    ProAdminService.instance.isAdmin().then((v) {
      if (mounted && v != _isAdmin) setState(() => _isAdmin = v);
    });
    pro.refresh(widget.business.id);
    _quoteAdd();
    pro.slotPrices().then((v) {
      if (mounted && v.isNotEmpty) setState(() => _slotPrices = v);
    });
    final results = await Future.wait([pro.plans(widget.business.currency), pro.settings()]);
    return (results[0] as List<ProPlan>, results[1] as Map<String, String>);
  }

  @override
  void initState() {
    super.initState();
    if (widget.focusCode) _data.whenComplete(_goToCode);
  }

  /// El canje está al final: baja hasta allá y deja el cursor en el código
  void _goToCode() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scroll.hasClients) return;
      await _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
      if (mounted) _codeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _codeFocus.dispose();
    _scroll.dispose();
    _codeController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  String _money(num v) => CurrencyFormatter.formatIn(v, widget.business.currency);

  Future<void> _redeem() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _redeeming = true;
      _codeError = null;
    });
    final result = await ProService.instance.redeem(_codeController.text, widget.business.id);
    if (!mounted) return;
    setState(() {
      _redeeming = false;
      _codeError = result.ok ? null : result.message;
    });
    if (result.ok) {
      _codeController.clear();
      AppToast.showSuccess(context, result.message);
    }
  }

  Future<void> _sendReceipt(ProPlan plan, String whatsapp) async {
    final email = AuthRepository.instance.currentUser?.email ?? '';
    final kind = plan.kindLabel;
    final message = 'Hola, pagué Stockealo $kind ${plan.periodLabel.toLowerCase()} '
        '(${_money(plan.price)}) para el negocio "${widget.business.name}". '
        'Mi cuenta es $email. Te adjunto el comprobante.';
    final digits = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(message)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      AppToast.showError(context, 'No se pudo abrir WhatsApp.');
    }
  }

  /// Sin Nequi (otro país o datos sin configurar): pedir Pro por WhatsApp o por correo
  Future<void> _askForPro(ProPlan? plan, String? whatsapp, {String? kind, Set<ProNeed> needs = const {}}) async {
    final email = AuthRepository.instance.currentUser?.email ?? '';
    final wanted = plan == null
        ? 'Stockealo ${kind == null ? 'Pro' : proKindLabel(kind)}'
        : 'Stockealo ${plan.kindLabel} ${plan.periodLabel.toLowerCase()} (${_money(plan.price)})';
    // Lo que marcó en «¿Qué necesitas?», para responderle con la oferta (0.15.0)
    final what = needs.isEmpty ? '' : ' Necesito: ${needs.map((n) => n.label.toLowerCase()).join(', ')}.';
    final message = 'Hola, quiero activar $wanted para el negocio "${widget.business.name}".$what '
        'Mi cuenta es $email. ¿Cómo puedo pagar?';
    final digits = whatsapp?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    final uri = digits.isNotEmpty
        ? Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(message)}')
        : Uri(scheme: 'mailto', path: proSupportEmail, query: 'subject=${Uri.encodeComponent('Quiero Stockealo Pro')}&body=${Uri.encodeComponent(message)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      AppToast.showError(context, digits.isNotEmpty ? 'No se pudo abrir WhatsApp.' : 'Escríbenos a $proSupportEmail');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(backgroundColor: c.paper, surfaceTintColor: Colors.transparent, title: const Text('Stockealo Pro')),
      body: FutureBuilder<(List<ProPlan>, Map<String, String>)>(
        future: _data,
        builder: (context, snapshot) {
          final settings = snapshot.data?.$2 ?? const <String, String>{};
          // Con «Mostrar precios y compra» apagado en el panel no se ven planes ni pagos
          final showPricing = ProService.pricingVisible(settings);
          final plans = showPricing ? (snapshot.data?.$1 ?? const <ProPlan>[]) : const <ProPlan>[];
          final loading = snapshot.connectionState != ConnectionState.done;
          return ContentListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xxl),
            children: [
              _statusCard(c),
              const SizedBox(height: AppSpace.xl),
              // Elegir el plan por lo que se necesita (0.15.0, punto 9)
              _section(c, '¿Qué necesitas para tu negocio?'),
              _card(
                c,
                PlanFinder(
                  pricingVisible: showPricing && plans.isNotEmpty,
                  onChoose: (kind, needs) => _choose(kind, needs, showPricing: showPricing, plans: plans, settings: settings),
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              // Los tres planes lado a lado (0.17.0, boceto aprobado)
              _section(c, 'Compara los planes'),
              _comparePlans(c, showPricing: showPricing, plans: plans, settings: settings),
              const SizedBox(height: AppSpace.xl),
              if (loading)
                const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Center(child: CircularProgressIndicator()))
              else if (!showPricing)
                _card(
                  c,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Por ahora los planes se activan con un código. Escríbenos y te contamos cómo tener Pro o Pro Servicios en tu negocio.',
                        style: TextStyle(fontSize: AppText.sizeBody, height: 1.4, color: c.inkMuted),
                      ),
                      const SizedBox(height: AppSpace.md),
                      OutlinedButton.icon(
                        onPressed: () => _askForPro(null, settings['whatsapp']),
                        icon: const Icon(Icons.chat_outlined, size: 18),
                        label: Text(settings['whatsapp'] != null ? 'Escribir por WhatsApp' : 'Escribir por correo'),
                      ),
                    ],
                  ),
                )
              else if (plans.isEmpty)
                _card(
                  c,
                  Text(
                    'Pro aún no está disponible en tu país. Si te dieron un código, puedes canjearlo abajo.',
                    style: TextStyle(fontSize: AppText.sizeBody, height: 1.4, color: c.inkMuted),
                  ),
                )
              else
                _payment(c, plans, settings),
              const SizedBox(height: AppSpace.xl),
              _section(c, '¿Ya tienes un código?'),
              _card(c, _redeemForm(c)),
              if (settings['legal_notice'] != null && plans.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.lg, AppSpace.xs, 0),
                  child: Text(settings['legal_notice']!, style: TextStyle(fontSize: AppText.sizeCaption, height: 1.4, color: c.inkFaint)),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Elegir un plan: con precios a la vista baja a los planes; si no, escribe por WhatsApp
  void _choose(String kind, Set<ProNeed> needs,
      {required bool showPricing, required List<ProPlan> plans, required Map<String, String> settings}) {
    final plan = showPricing ? _planFor(kind, plans) : null;
    if (plan != null) {
      _pick(plan);
    } else {
      _askForPro(null, settings['whatsapp'], kind: kind, needs: needs);
    }
  }

  /// El plan de [kind] para el periodo del selector (mensual o anual). Sin ese periodo,
  /// null: nunca se cambia a otro periodo sin que se vea (hallazgo de la revisión)
  ProPlan? _planFor(String kind, List<ProPlan> plans) =>
      plans.where((p) => p.kind == kind && p.period == (_annual ? 'year' : 'month')).firstOrNull;

  void _pick(ProPlan plan) {
    if (plan.kind == 'business' && ProService.instance.status.value.services) {
      AppToast.show(context, message: 'Tu Pro Servicios ya incluye todo lo de Pro.', type: ToastType.info);
      return;
    }
    setState(() => _selectedPlanId = plan.id);
    if (_slotsFor(plan)) _quoteSlots(plan.id, preload: true);
    if (plan.kind == 'services') _quoteUpgrade(plan.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
      }
    });
  }

  /// Precio de la tarjeta: con Anual, lo que sale por mes y debajo el total y el ahorro
  Widget _priceBlock(StockealoColors c, ProPlan plan, List<ProPlan> plans) {
    final monthly = plans.where((p) => p.kind == plan.kind && p.period == 'month').firstOrNull;
    final yearly = plan.period == 'year';
    final perMonth = yearly ? (plan.price / 12 / 10).round() * 10 : plan.price;
    final saving = yearly && monthly != null ? monthly.price * 12 - plan.price : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(_money(perMonth), style: AppText.amount(context, size: 24, weight: FontWeight.w800)),
            const SizedBox(width: 4),
            Text('/mes', style: AppText.small(context, color: c.inkMuted)),
          ],
        ),
        Text(
          yearly
              ? '${_money(plan.price)} al año${saving > 0 ? ' · ahorras ${_money(saving)}' : ''}'
              : 'Se renueva cada mes',
          style: AppText.caption(context, color: c.inkMuted),
        ),
        // 0.18.7: lo que cuesta cada sede extra con este plan
        if (_slotPrices[plan.kind] case final slot? when slot.price(yearly: yearly) > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Sede extra: ${_money(slot.price(yearly: yearly))} ${yearly ? 'al año' : 'al mes'}'
            '${slot.bulkFrom > 1 && slot.bulk(yearly: yearly) > 0 ? ' · desde ${slot.bulkFrom}, ${_money(slot.bulk(yearly: yearly))} cada una' : ''}',
            style: AppText.caption(context, color: c.inkMuted),
          ),
        ],
      ],
    );
  }

  /// Una tarjeta de la comparación de planes
  Widget _planCard(
    StockealoColors c, {
    required bool current,
    required String title,
    required String lead,
    required List<(IconData, String)> items,
    required Color tint,
    String? note,
    String? badge,
    String? button,
    VoidCallback? onChoose,
    Widget? price,
    bool included = false,
  }) {
    final featured = badge != null;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: featured ? c.accent : c.line, width: featured ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppText.title(context))),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(badge, style: AppText.caption(context, weight: FontWeight.w700, color: c.accent)),
                ),
            ],
          ),
          if (price != null) ...[
            const SizedBox(height: AppSpace.sm),
            price,
          ],
          const SizedBox(height: AppSpace.xs),
          Text(lead, style: AppText.small(context, color: c.inkMuted)),
          const SizedBox(height: AppSpace.sm),
          for (final (icon, text) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: tint),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(text, style: AppText.body(context))),
                ],
              ),
            ),
          if (note != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(note, style: AppText.small(context, color: c.inkMuted)),
          ],
          const Spacer(),
          const SizedBox(height: AppSpace.md),
          // Pro Servicios trae todo Pro: la tarjeta Pro no se compra encima (24 nov)
          if (included)
            Text('Incluido en tu plan', textAlign: TextAlign.center, style: AppText.small(context, color: c.inkFaint))
          else if (current) ...[
            Text('Tu plan actual', textAlign: TextAlign.center, style: AppText.small(context, color: c.inkFaint)),
            // Con precios a la vista, quien ya lo tiene lo puede renovar (se suma a lo que le queda)
            if (price != null && onChoose != null) ...[
              const SizedBox(height: AppSpace.xs),
              OutlinedButton(onPressed: onChoose, child: const Text('Renovar')),
            ],
          ]
          else if (button != null && featured)
            FilledButton(onPressed: onChoose, child: Text(button))
          else if (button != null)
            OutlinedButton(onPressed: onChoose, child: Text(button)),
        ],
      ),
    );
  }

  /// Gratis, Pro (resaltado, «Recomendado») y Pro Servicios. En el celular, una debajo de otra.
  Widget _comparePlans(StockealoColors c,
      {required bool showPricing, required List<ProPlan> plans, required Map<String, String> settings}) {
    return ValueListenableBuilder<ProStatus>(
      valueListenable: ProService.instance.status,
      builder: (context, status, _) {
        final current = !status.active ? 'free' : (status.services ? 'services' : 'business');
        // Con «Mostrar precios y compra» encendido: precio en cada tarjeta y se elige ahí
        final priced = showPricing && plans.isNotEmpty;
        final pro = priced ? _planFor('business', plans) : null;
        final services = priced ? _planFor('services', plans) : null;
        void choose(String kind) {
          final plan = kind == 'business' ? pro : services;
          if (plan != null) {
            _pick(plan);
          } else {
            _choose(kind, const {}, showPricing: showPricing, plans: plans, settings: settings);
          }
        }

        final cards = [
          _planCard(
            c,
            current: current == 'free',
            title: 'Gratis',
            lead: 'Lo que ya tienes',
            tint: c.success,
            price: priced
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_money(0), style: AppText.amount(context, size: 24, weight: FontWeight.w800)),
                    Text('Para siempre', style: AppText.caption(context, color: c.inkMuted)),
                  ])
                : null,
            items: [for (final t in freeBenefits) (Icons.check_outlined, t)],
          ),
          _planCard(
            c,
            current: current == 'business',
            included: current == 'services',
            title: 'Pro',
            lead: 'Todo lo gratis, más:',
            tint: c.accent,
            badge: 'Recomendado',
            button: 'Elegir',
            onChoose: () => choose('business'),
            price: pro == null ? null : _priceBlock(c, pro, plans),
            items: [for (final b in proBenefits) (b.$1, b.$2)],
          ),
          _planCard(
            c,
            current: current == 'services',
            title: 'Pro Servicios',
            lead: 'Todo Pro, más:',
            tint: c.accent,
            note: 'Para lavaderos, barberías, talleres y otros servicios',
            button: 'Elegir',
            onChoose: () => choose('services'),
            price: services == null ? null : _priceBlock(c, services, plans),
            items: [for (final b in proServicesBenefits) (b.$1, b.$2)],
          ),
        ];
        final hasYear = plans.any((p) => p.period == 'year');
        final grid = LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 720) {
            return Column(children: [
              for (final card in cards)
                Padding(padding: const EdgeInsets.only(bottom: AppSpace.md), child: IntrinsicHeight(child: card)),
            ]);
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpace.md),
                  Expanded(child: cards[i]),
                ],
              ],
            ),
          );
        });
        if (!priced) return grid;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasYear) ...[
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Mensual')),
                      ButtonSegment(value: true, label: Text('Anual')),
                    ],
                    selected: {_annual},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() {
                      _annual = v.first;
                      _selectedPlanId = null;
                    }),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
                    decoration: BoxDecoration(color: c.successSoft, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text('Anual: 2 meses gratis', style: AppText.caption(context, weight: FontWeight.w700, color: c.success)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
            ],
            grid,
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xs, 0, AppSpace.xs, 0),
              child: Text('Precios en pesos colombianos (COP). Puedes cancelar cuando quieras.',
                  style: AppText.caption(context, color: c.inkFaint)),
            ),
          ],
        );
      },
    );
  }

  Widget _section(StockealoColors c, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.xs, 0, 0, AppSpace.sm),
        child: Text(label.toUpperCase(),
            style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.inkFaint)),
      );

  Widget _card(StockealoColors c, Widget child) => Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.line),
        ),
        child: child,
      );

  Widget _statusCard(StockealoColors c) {
    return ValueListenableBuilder<ProStatus>(
      valueListenable: ProService.instance.status,
      builder: (context, status, _) {
        final text = !status.active
            ? 'Este negocio usa Stockealo gratis.'
            : status.lifetime && !status.services
                ? '${status.kindLabel} permanente. ¡Gracias por apoyar a Stockealo!'
                : '${proUntilText(status)}.';
        return Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: status.active ? c.accent : c.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: status.active ? c.accent : c.line),
          ),
          child: Row(
            children: [
              const ProCrown(size: 36),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(status.active ? 'Tienes ${status.kindLabel}' : 'Stockealo Pro',
                        style: TextStyle(fontSize: AppText.sizeHeading, fontWeight: FontWeight.w800, color: status.active ? c.onAccent : c.ink)),
                    const SizedBox(height: 2),
                    Text(text, style: TextStyle(fontSize: AppText.sizeBody, color: status.active ? c.onAccent.withValues(alpha: 0.9) : c.inkMuted)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _payment(StockealoColors c, List<ProPlan> plans, Map<String, String> settings) {
    final nequi = settings['nequi_number'];
    final whatsapp = settings['whatsapp'];
    final plan = plans.where((p) => p.id == _selectedPlanId).firstOrNull;
    // Nequi solo para pesos colombianos
    final nequiAvailable = widget.business.currency == 'COP' && nequi != null && whatsapp != null;
    // Si el Nequi y el WhatsApp son el mismo número, se muestra una sola vez
    final nequiDigits = nequi?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    final sameNumber = nequiDigits.isNotEmpty && (whatsapp?.replaceAll(RegExp(r'[^0-9]'), '') ?? '').endsWith(nequiDigits);
    // Wompi cobra en pesos colombianos y Pro se activa solo. Con la llave de pruebas
    // solo lo ven los administradores (si no, cualquiera tendría Pro sin pagar)
    final wompiKey = settings['wompi_public_key'] ?? '';
    final wompiAvailable = widget.business.currency == 'COP' &&
        (wompiKey.startsWith('pub_prod_') || (wompiKey.startsWith('pub_test_') && _isAdmin));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(c, 'Cómo pagar'),
        if (wompiAvailable) ...[
          _card(c, _wompiBox(c, plan, testMode: wompiKey.startsWith('pub_test_'))),
          // Con plan vigente: sedes extra por los días que le faltan (0.18.3)
          if (_addQuote != null && (_addQuote!.ok || _addQuote!.error == 'renew_with_plan')) ...[
            const SizedBox(height: AppSpace.md),
            _card(c, _addSlotsBox(c)),
          ],
          Center(
            child: TextButton(
              onPressed: () => setState(() => _showManual = !_showManual),
              child: Text(
                _showManual ? 'Ocultar el pago por Nequi directo' : '¿Prefieres pagar por Nequi y enviar el comprobante?',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
        if (!wompiAvailable || _showManual)
        _card(
          c,
          !nequiAvailable
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      whatsapp != null
                          ? 'Escríbenos al WhatsApp y te decimos cómo pagar. Te enviamos un código para activar Pro aquí abajo.'
                          : 'Escríbenos a $proSupportEmail y te decimos cómo pagar. Te enviamos un código para activar Pro aquí abajo.',
                      style: TextStyle(fontSize: AppText.sizeBody, height: 1.4, color: c.inkMuted),
                    ),
                    if (whatsapp != null) _copyRow(c, whatsapp, 'WhatsApp de Stockealo', 'Número de WhatsApp copiado'),
                    const SizedBox(height: AppSpace.md),
                    FilledButton.icon(
                      onPressed: () => _askForPro(plan, whatsapp),
                      icon: Icon(whatsapp != null ? Icons.chat_outlined : Icons.mail_outline_outlined, size: 20),
                      label: Text(whatsapp != null ? 'Escríbenos al WhatsApp' : 'Escribir un correo'),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _step(c, '1',
                        plan == null ? 'Elige un plan arriba y envía su valor por Nequi a:' : 'Envía ${_money(plan.price)} por Nequi a:'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, AppSpace.xs, 0, AppSpace.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(nequi, style: AppText.amount(context, size: 18, weight: FontWeight.w800)),
                                Text(
                                    [
                                      sameNumber ? 'Nequi y WhatsApp de Stockealo' : 'Nequi',
                                      if (settings['nequi_name'] != null) settings['nequi_name']!,
                                    ].join(' · '),
                                    style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: nequi));
                              AppToast.showSuccess(context, 'Número de Nequi copiado');
                            },
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            label: const Text('Copiar'),
                          ),
                        ],
                      ),
                    ),
                    // El botón ya abre nuestro chat: no hace falta repetir el número
                    _step(c, '2', 'Toca el botón para enviarnos el comprobante por WhatsApp.'),
                    _step(c, '3', 'Te respondemos con un código para canjear aquí abajo.'),
                    const SizedBox(height: AppSpace.md),
                    FilledButton.icon(
                      onPressed: plan == null ? null : () => _sendReceipt(plan, whatsapp),
                      icon: const Icon(Icons.chat_outlined, size: 20),
                      label: Text(plan == null ? 'Elige un plan' : 'Enviar comprobante por WhatsApp'),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _wompiBox(StockealoColors c, ProPlan? plan, {required bool testMode}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: c.accent),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text('Pago en línea seguro', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
              ),
              if (testMode)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
                  decoration: BoxDecoration(color: c.warningSoft, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text('Modo de pruebas',
                      style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w600, color: c.warning)),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Paga con Nequi, PSE, tarjeta o Bancolombia a través de Wompi. Pro se activa solo cuando se aprueba el pago.',
            style: TextStyle(fontSize: AppText.sizeBody, height: 1.4, color: c.inkMuted),
          ),
          const SizedBox(height: AppSpace.md),
          if (plan != null && _slotsFor(plan)) _slotsBox(c, plan),
          if (plan != null && plan.kind == 'services') _upgradeBox(c, plan),
          if (plan != null && (_upgradeFor(plan)?.credit ?? 0) == 0) _couponBox(c, plan),
          Builder(builder: (context) {
            final total = plan == null ? null : _totalFor(plan);
            final label = plan == null
                ? 'Elige un plan'
                : total == null
                    ? 'Calculando…'
                    : 'Pagar ${_money(total)} con Wompi';
            return FilledButton.icon(
              onPressed: plan == null || total == null || _paying
                  ? null
                  : () => _payOnline(plan.id,
                      coupon: _hasCredit(plan) ? null : _couponFor(plan)?.code,
                      slots: _slotsFor(plan) ? _slots : 0,
                      upgrade: _hasCredit(plan),
                      done: 'Listo: ya tienes ${plan.kind == 'business' ? 'Pro' : plan.kindLabel}.'),
              icon: _paying
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_outline, size: 20),
              label: Text(label),
            );
          }),
        ],
      );

  /// El cupón aplicado, si es para este plan (al cambiar de plan hay que volver a aplicarlo)
  ({String code, double price, double regular, String planId})? _couponFor(ProPlan plan) =>
      _coupon?.planId == plan.id ? _coupon : null;

  Future<void> _applyCoupon(ProPlan plan) async {
    final text = _couponController.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _checkingCoupon = true;
      _couponError = null;
    });
    try {
      final q = await ProService.instance.quoteCoupon(text, plan.id);
      if (mounted) setState(() => _coupon = (code: q.code, price: q.price, regular: q.regular, planId: plan.id));
    } on ProCheckoutException catch (e) {
      if (mounted) setState(() => _couponError = e.message);
    } finally {
      if (mounted) setState(() => _checkingCoupon = false);
    }
  }

  /// «¿Tienes un cupón?»: se escribe, se aplica y se ve el precio tachado y el nuevo
  Widget _couponBox(StockealoColors c, ProPlan plan) {
    final applied = _couponFor(plan);
    if (applied != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: Row(
          children: [
            Icon(Icons.local_offer_outlined, size: 18, color: c.success),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${applied.code} · ', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                  TextSpan(
                    text: _money(applied.regular),
                    style: TextStyle(color: c.inkFaint, decoration: TextDecoration.lineThrough),
                  ),
                  TextSpan(text: '  ${_money(applied.price)}', style: TextStyle(fontWeight: FontWeight.w800, color: c.success)),
                ]),
                style: const TextStyle(fontSize: AppText.sizeBody),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _coupon = null;
                _couponController.clear();
              }),
              child: const Text('Quitar'),
            ),
          ],
        ),
      );
    }
    if (!_showCoupon) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _showCoupon = true),
          icon: const Icon(Icons.local_offer_outlined, size: 18),
          label: const Text('¿Tienes un cupón?'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _couponController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: 'Cupón', isDense: true, errorText: _couponError, errorMaxLines: 3),
              onSubmitted: (_) => _applyCoupon(plan),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          OutlinedButton(
            onPressed: _checkingCoupon ? null : () => _applyCoupon(plan),
            child: Text(_checkingCoupon ? 'Revisando…' : 'Aplicar'),
          ),
        ],
      ),
    );
  }

  /// Abre el pago de Wompi y espera la confirmación del servidor. [planId] es un plan o
  /// [branchSlotsPlanId] (solo sedes extra); [done] es el aviso al aprobarse.
  Future<void> _payOnline(String planId,
      {String? coupon, int slots = 0, bool upgrade = false, required String done}) async {
    setState(() => _paying = true);
    try {
      final checkout =
          await ProService.instance.startCheckout(widget.business.id, planId,
          coupon: coupon, branchSlots: slots, upgrade: upgrade);
      final opened = await launchUrl(Uri.parse(checkout.url), mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!opened) {
        AppToast.showError(context, 'No se pudo abrir el pago. Inténtalo de nuevo.');
        return;
      }
      final approved = await PaymentWaitSheet.show(context, reference: checkout.reference);
      if (!mounted) return;
      if (approved == true) {
        await ProService.instance.refresh(widget.business.id);
        _quoteAdd();
        if (mounted) AppToast.showSuccess(context, done);
      }
    } on ProCheckoutException catch (e) {
      if (mounted) AppToast.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// Las sedes extra van con Pro o Pro Servicios, mensual o anual
  bool _slotsFor(ProPlan plan) =>
      (plan.kind == 'business' || plan.kind == 'services') && (plan.period == 'month' || plan.period == 'year');

  /// Cotiza en la nube las sedes extra del plan elegido. Con [preload] trae marcadas las
  /// que tiene hoy, para que al renovar no se le venzan sin darse cuenta.
  Future<void> _quoteSlots(String planId, {bool preload = false}) async {
    final seq = ++_quoteSeq;
    setState(() => _quotingSlots = true);
    var q = await ProService.instance.quoteSlots(widget.business.id, planId, preload ? 0 : _slots);
    if (preload && seq == _quoteSeq) {
      _slots = q != null && q.ok ? q.held : 0;
      if (_slots > 0) q = await ProService.instance.quoteSlots(widget.business.id, planId, _slots);
    }
    if (!mounted || seq != _quoteSeq) return;
    setState(() {
      _slotQuote = q;
      _slotQuotePlan = planId;
      _quotingSlots = false;
    });
  }

  void _setSlots(ProPlan plan, int n) {
    setState(() => _slots = n.clamp(0, 50));
    _quoteSlots(plan.id);
  }

  /// Solo sedes extra con el plan vigente: días que faltan del plan
  Future<void> _quoteAdd() async {
    final seq = ++_addSeq;
    if (mounted) setState(() => _quotingAdd = true);
    final q = await ProService.instance.quoteSlots(widget.business.id, branchSlotsPlanId, _addSlots);
    if (mounted && seq == _addSeq) {
      setState(() {
        _addQuote = q;
        _quotingAdd = false;
      });
    }
  }

  String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

  /// «[ − ] 2 [ + ]»
  Widget _stepper(StockealoColors c, int value, ValueChanged<int> onChanged, {int min = 0}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Quitar una',
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 28,
            child: Text('$value', textAlign: TextAlign.center, style: AppText.amount(context, size: 18, weight: FontWeight.w800)),
          ),
          IconButton(
            tooltip: 'Agregar una',
            onPressed: value < 50 ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      );

  /// «Sedes extra − n +» debajo del plan elegido, con su precio (punto 3 del plan 0.18.3)
  Widget _slotsBox(StockealoColors c, ProPlan plan) {
    final q = _slotQuotePlan == plan.id ? _slotQuote : null;
    final included = plan.kind == 'services' ? 'Incluye la Principal y 2 sedes' : 'Incluye solo la Principal';
    final per = plan.period == 'year' ? 'al año' : 'al mes';
    String detail() {
      final parts = ['$_slots × ${_money(q!.unit)} $per'];
      if (q.gap > 0) {
        final who = q.gap == 1 ? 'una sede' : '${q.gap} sedes';
        parts.add('y $who desde hoy hasta que empiece el plan nuevo (${q.days} días, ${_money(q.gapAmount)})');
      }
      return parts.join(' ');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sedes extra', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                    Text(included, style: AppText.caption(context, color: c.inkMuted)),
                  ],
                ),
              ),
              _stepper(c, _slots, (n) => _setSlots(plan, n)),
            ],
          ),
          if (_slots > 0 && q != null && q.ok)
            Text(detail(), style: AppText.caption(context, color: c.inkMuted))
          else if (_slots > 0 && q != null && !q.ok)
            Text(ProService.slotErrorMessage(q.error!) ?? 'No se pueden agregar sedes a este plan.',
                style: AppText.caption(context, color: c.danger)),
        ],
      ),
    );
  }

  /// Total a pagar del plan elegido: el plan (con cupón) más sus sedes extra; null si
  /// las sedes aún se están cotizando o no se pueden comprar
  double? _totalFor(ProPlan plan) {
    if (plan.kind == 'services') {
      final u = _upgradeFor(plan);
      if (_quotingUpgrade || (u != null && !u.ok)) return null;
    }
    final base = _hasCredit(plan) ? _upgradeFor(plan)!.amount : _couponFor(plan)?.price ?? plan.price;
    if (_slots == 0 || !_slotsFor(plan)) return base;
    final q = _slotQuotePlan == plan.id ? _slotQuote : null;
    if (_quotingSlots || q == null || !q.ok) return null;
    return base + q.amount;
  }

  UpgradeQuote? _upgradeFor(ProPlan plan) => _upgradePlan == plan.id ? _upgrade : null;

  /// Pro Servicios con descuento por su Pro: no lleva cupón y ese Pro termina hoy
  bool _hasCredit(ProPlan plan) {
    final u = _upgradeFor(plan);
    return u != null && u.ok && u.credit > 0;
  }

  Future<void> _quoteUpgrade(String planId) async {
    final seq = ++_upgradeSeq;
    setState(() => _quotingUpgrade = true);
    final q = await ProService.instance.quoteUpgrade(widget.business.id, planId);
    if (!mounted || seq != _upgradeSeq) return;
    setState(() {
      _upgrade = q;
      _upgradePlan = planId;
      _quotingUpgrade = false;
    });
  }

  /// «Descuento por tu Pro: −$X» al pasar de Pro a Pro Servicios (punto 4 del plan 0.18.3)
  Widget _upgradeBox(StockealoColors c, ProPlan plan) {
    final u = _upgradeFor(plan);
    if (u == null || (u.ok && u.credit == 0)) return const SizedBox.shrink();
    if (!u.ok) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: Text(ProService.upgradeErrorMessage(u.error!) ?? 'No se pudo calcular el descuento por tu Pro.',
            style: AppText.caption(context, color: c.danger)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.local_offer_outlined, size: 18, color: c.success),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'Descuento por lo que te queda de Pro: −${_money(u.credit)}. '
              'Al aprobarse el pago tu Pro termina hoy y sigues con Pro Servicios, que trae todo lo de Pro.',
              style: TextStyle(fontSize: AppText.sizeBody, height: 1.4, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }

  /// «Agregar sedes a tu plan»: solo sedes, pagando los días que le faltan al plan
  Widget _addSlotsBox(StockealoColors c) {
    final q = _addQuote;
    final renew = q?.error == 'renew_with_plan';
    final until = q?.endsAt != null ? ' (hasta el ${_date(q!.endsAt!)})' : '';
    final howMany = _addSlots == 1 ? 'una sede extra' : '$_addSlots sedes extra';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.storefront_outlined, color: c.accent),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text('Agregar sedes a tu plan', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink))),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          renew
              ? ProService.slotErrorMessage(q!.error!)!
              : 'Pagas solo los días que le faltan a tu plan$until. Las sedes vencen con el plan y se renuevan juntas.',
          style: TextStyle(fontSize: AppText.sizeBody, height: 1.4, color: c.inkMuted),
        ),
        if (!renew) ...[
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              Expanded(child: Text('Sedes extra', style: TextStyle(fontWeight: FontWeight.w600, color: c.ink))),
              _stepper(c, _addSlots, (n) {
                setState(() => _addSlots = n);
                _quoteAdd();
              }, min: 1),
            ],
          ),
          if (q != null && q.ok) Text('${q.days} días de $howMany', style: AppText.caption(context, color: c.inkMuted)),
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            onPressed: _paying || _quotingAdd || q == null || !q.ok
                ? null
                : () => _payOnline(branchSlotsPlanId, slots: _addSlots, done: 'Listo: ya tienes $howMany.'),
            icon: const Icon(Icons.lock_outline, size: 20),
            label: Text(q != null && q.ok && !_quotingAdd ? 'Pagar ${_money(q.amount)} con Wompi' : 'Calculando…'),
          ),
        ],
      ],
    );
  }

  /// Número a la vista con botón para copiarlo (WhatsApp de Stockealo)
  Widget _copyRow(StockealoColors c, String number, String caption, String copied, {double indent = 0}) => Padding(
        padding: EdgeInsets.fromLTRB(indent, AppSpace.sm, 0, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(number, style: AppText.amount(context, size: 18, weight: FontWeight.w800)),
                  Text(caption, style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: number));
                AppToast.showSuccess(context, copied);
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copiar'),
            ),
          ],
        ),
      );

  Widget _step(StockealoColors c, String n, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Text(n, style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w800, color: c.accent)),
            ),
            const SizedBox(width: AppSpace.sm + 2),
            Expanded(child: Text(text, style: TextStyle(fontSize: AppText.sizeBody, color: c.ink))),
          ],
        ),
      );

  Widget _redeemForm(StockealoColors c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _codeController,
            focusNode: _codeFocus,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _redeem(),
            style: const TextStyle(fontSize: AppText.sizeTitle, fontWeight: FontWeight.w700, letterSpacing: 1.5),
            decoration: InputDecoration(
              labelText: 'Código',
              hintText: 'STK-XXXX-XXXX',
              errorText: _codeError,
              errorMaxLines: 2,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          OutlinedButton(
            onPressed: _redeeming ? null : _redeem,
            child: Text(_redeeming ? 'Canjeando…' : 'Canjear código'),
          ),
        ],
      );
}

/// Espera a que Wompi confirme el pago (el servidor recibe el aviso y activa Pro).
/// Devuelve true si el pago quedó aprobado.
class PaymentWaitSheet extends StatefulWidget {
  final String reference;

  /// Cada cuánto se pregunta el estado
  final Duration interval;

  const PaymentWaitSheet({super.key, required this.reference, this.interval = const Duration(seconds: 4)});

  static Future<bool?> show(BuildContext context, {required String reference}) => showModalBottomSheet<bool>(
        context: context,
        isDismissible: false,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        builder: (_) => PaymentWaitSheet(reference: reference),
      );

  @override
  State<PaymentWaitSheet> createState() => _PaymentWaitSheetState();
}

class _PaymentWaitSheetState extends State<PaymentWaitSheet> with WidgetsBindingObserver {
  ProPaymentState _state = ProPaymentState.pending;
  bool _checking = false;
  int _tries = 0;

  /// Unos 5 minutos preguntando; después el cliente puede revisar a mano
  static const _maxTries = 75;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver de Wompi a la app se revisa de inmediato
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void _schedule() {
    Future.delayed(widget.interval, () async {
      if (!mounted || _state != ProPaymentState.pending || _tries >= _maxTries) return;
      _tries++;
      await _check();
      _schedule();
    });
  }

  Future<void> _check() async {
    if (_checking || _state != ProPaymentState.pending) return;
    setState(() => _checking = true);
    final state = await ProService.instance.paymentState(widget.reference);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (state != null) _state = state;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, color, title, body) = switch (_state) {
      ProPaymentState.approved => (Icons.check_circle_outlined, c.success, 'Listo: ya tienes Pro',
          'El pago fue aprobado y Pro ya está activo.'),
      ProPaymentState.declined => (Icons.cancel_outlined, c.danger, 'El pago no se aprobó',
          'Wompi rechazó o anuló el pago, así que no se te cobró. Puedes intentarlo de nuevo.'),
      ProPaymentState.error => (Icons.error_outline_outlined, c.warning, 'Revisamos tu pago',
          'Hubo una diferencia con el pago. Escríbenos por WhatsApp con la referencia y lo resolvemos.'),
      ProPaymentState.pending => (Icons.hourglass_top_outlined, c.accent, 'Esperando la confirmación',
          'Termina el pago en Wompi. Cuando se apruebe, Pro se activa solo; puede tardar unos segundos.'),
    };
    return Container(
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      padding: const EdgeInsets.all(AppSpace.xl),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: AppSpace.md),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.sizeHeading, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: AppSpace.sm),
            Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.sizeBody, height: 1.4, color: c.inkMuted)),
            const SizedBox(height: AppSpace.sm),
            Text('Referencia ${widget.reference}', textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint)),
            const SizedBox(height: AppSpace.lg),
            if (_state == ProPaymentState.pending) ...[
              if (_checking) const LinearProgressIndicator(),
              const SizedBox(height: AppSpace.sm),
              OutlinedButton(onPressed: _checking ? null : _check, child: const Text('Ya pagué, revisar')),
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cerrar')),
            ] else
              FilledButton(
                onPressed: () => Navigator.pop(context, _state == ProPaymentState.approved),
                child: Text(_state == ProPaymentState.approved ? 'Listo' : 'Cerrar'),
              ),
          ],
        ),
      ),
    );
  }
}
