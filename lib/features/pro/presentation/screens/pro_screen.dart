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

/// Lo que suma Pro (también lo muestra la ventana de Pro). Todo lo demás sigue gratis.
/// Correo de soporte (el mismo de los Términos y la Política de privacidad)
const proSupportEmail = 'byjosealbert@gmail.com';

const proBenefits = [
  (Icons.storefront_outlined, 'Tienda en línea', 'Tu catálogo con carrito; los pedidos te llegan por WhatsApp.'),
  (Icons.notifications_active_outlined, 'Cobro automático de fiados', 'Recordatorios programados y estado de cuenta en PDF.'),
  (Icons.auto_awesome_mosaic_outlined, 'Catálogos personalizados', 'Más plantillas y colores, sin el pie "Hecho con Stockealo".'),
  (Icons.auto_awesome_outlined, 'Más preguntas a Stocky', '50 preguntas a la IA al día en vez de 10.'),
];

/// Lo que suma Pro Servicios además de todo Pro
const proServicesBenefits = [
  (Icons.view_kanban_outlined, 'Módulo Servicios', 'Tablero de trabajos, cola por orden de llegada y asistencia del equipo.'),
  (Icons.payments_outlined, 'Comisiones y liquidaciones', 'Lo que gana cada empleado por servicio, para pagar por día, semana o mes.'),
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
  String _kind = 'business';
  String? _selectedPlanId;
  bool _redeeming = false;

  /// Pago en línea con Wompi en curso / mostrar el pago manual por Nequi
  bool _paying = false;
  bool _showManual = false;

  /// Cuenta administradora: puede probar Wompi con la llave de pruebas
  bool _isAdmin = false;
  String? _codeError;

  Future<(List<ProPlan>, Map<String, String>)> _load() async {
    final pro = ProService.instance;
    ProAdminService.instance.isAdmin().then((v) {
      if (mounted && v != _isAdmin) setState(() => _isAdmin = v);
    });
    pro.refresh(widget.business.id);
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
  Future<void> _askForPro(ProPlan? plan, String? whatsapp) async {
    final email = AuthRepository.instance.currentUser?.email ?? '';
    final wanted = plan == null
        ? 'Stockealo Pro'
        : 'Stockealo ${plan.kindLabel} ${plan.periodLabel.toLowerCase()} (${_money(plan.price)})';
    final message = 'Hola, quiero activar $wanted para el negocio "${widget.business.name}". '
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
          return ContentWidth(
            child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xxl),
            children: [
              _statusCard(c),
              const SizedBox(height: AppSpace.xl),
              _section(c, 'Lo que suma Pro'),
              _card(c, Column(children: [for (final b in proBenefits) _benefit(c, b.$1, b.$2, b.$3)])),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.sm, AppSpace.xs, 0),
                child: Text(
                  'Todo lo demás sigue gratis: inventario, ventas, fiados, reportes, equipo y respaldo.',
                  style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted),
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              _section(c, 'Pro Servicios'),
              _card(
                c,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Para lavaderos, barberías, talleres y otros negocios de servicios: todo lo de Pro y además:',
                      style: TextStyle(fontSize: AppText.sizeSmall, height: 1.35, color: c.inkMuted),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    for (final b in proServicesBenefits) _benefit(c, b.$1, b.$2, b.$3),
                  ],
                ),
              ),
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
              else ...[
                _section(c, 'Planes'),
                _plans(c, plans),
                const SizedBox(height: AppSpace.xl),
                _payment(c, plans, settings),
              ],
              const SizedBox(height: AppSpace.xl),
              _section(c, '¿Ya tienes un código?'),
              _card(c, _redeemForm(c)),
              if (settings['legal_notice'] != null && plans.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.lg, AppSpace.xs, 0),
                  child: Text(settings['legal_notice']!, style: TextStyle(fontSize: AppText.sizeCaption, height: 1.4, color: c.inkFaint)),
                ),
            ],
          ),
          );
        },
      ),
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
        final until = status.endsAt;
        final text = !status.active
            ? 'Este negocio usa Stockealo gratis.'
            : status.lifetime
                ? '${status.kindLabel} permanente. ¡Gracias por apoyar a Stockealo!'
                : '${status.kindLabel} activo hasta el ${until!.day}/${until.month}/${until.year}.';
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
                    Text(status.active ? 'Tienes Pro' : 'Stockealo Pro',
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

  Widget _benefit(StockealoColors c, IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: c.accent),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: AppText.sizeBodyLarge, fontWeight: FontWeight.w700, color: c.ink)),
                  Text(body, style: TextStyle(fontSize: AppText.sizeSmall, height: 1.35, color: c.inkMuted)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _plans(StockealoColors c, List<ProPlan> all) {
    // Pro Servicios aparece solo si su plan está encendido para esta moneda
    final kinds = [for (final k in const ['business', 'global', 'services']) if (all.any((p) => p.kind == k)) k];
    if (!kinds.contains(_kind) && kinds.isNotEmpty) _kind = kinds.first;
    final plans = all.where((p) => p.kind == _kind).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: [
            for (final k in kinds) ButtonSegment(value: k, label: Text(proKindLabel(k))),
          ],
          selected: {_kind},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() {
            _kind = v.first;
            _selectedPlanId = null;
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.sm, AppSpace.xs, AppSpace.md),
          child: Text(
            switch (_kind) {
              'global' => 'Para todos los negocios donde eres dueño, también los que crees después.',
              'services' => 'Para "${widget.business.name}": todo Pro más el módulo Servicios, con soporte.',
              _ => 'Para "${widget.business.name}" y todo su equipo.',
            },
            style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted),
          ),
        ),
        for (final p in plans) _planTile(c, p),
      ],
    );
  }

  Widget _planTile(StockealoColors c, ProPlan p) {
    final selected = _selectedPlanId == p.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        color: selected ? c.accent.withValues(alpha: 0.08) : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: selected ? c.accent : c.line, width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => setState(() => _selectedPlanId = p.id),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Row(
              children: [
                Icon(selected ? Icons.radio_button_checked_outlined : Icons.radio_button_off_outlined,
                    color: selected ? c.accent : c.inkFaint),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Row(
                    children: [
                      Text(p.periodLabel, style: TextStyle(fontSize: AppText.sizeBodyLarge, fontWeight: FontWeight.w700, color: c.ink)),
                      if (p.label != null) ...[
                        const SizedBox(width: AppSpace.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: c.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadius.pill)),
                          child: Text(p.label!, style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w700, color: c.warning)),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (p.regularPrice != null)
                      Text(_money(p.regularPrice!),
                          style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint, decoration: TextDecoration.lineThrough)),
                    Text(_money(p.price), style: AppText.amount(context, size: 17, weight: FontWeight.w800)),
                    Text(p.perLabel, style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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
          FilledButton.icon(
            onPressed: plan == null || _paying ? null : () => _payOnline(plan),
            icon: _paying
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.lock_outline, size: 20),
            label: Text(plan == null ? 'Elige un plan' : 'Pagar ${_money(plan.price)} con Wompi'),
          ),
        ],
      );

  /// Abre el pago de Wompi y espera la confirmación del servidor
  Future<void> _payOnline(ProPlan plan) async {
    setState(() => _paying = true);
    try {
      final checkout = await ProService.instance.startCheckout(widget.business.id, plan.id);
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
        if (mounted) AppToast.showSuccess(context, 'Listo: ya tienes ${plan.kind == 'business' ? 'Pro' : plan.kindLabel}.');
      }
    } on ProCheckoutException catch (e) {
      if (mounted) AppToast.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
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
