import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/models/business.dart';
import '../../data/pro_service.dart';

/// Lo que suma Pro (también lo muestra la ventana de Pro). Todo lo demás sigue gratis.
const proBenefits = [
  (Icons.storefront_outlined, 'Tienda en línea', 'Tu catálogo con carrito; los pedidos te llegan por WhatsApp.'),
  (Icons.notifications_active_outlined, 'Cobro automático de fiados', 'Recordatorios programados y estado de cuenta en PDF.'),
  (Icons.auto_awesome_mosaic_outlined, 'Catálogos personalizados', 'Más plantillas y colores, sin el pie "Hecho con Stockealo".'),
  (Icons.auto_awesome_rounded, 'Más preguntas a Stocky', '50 preguntas a la IA al día en vez de 10.'),
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
  String? _codeError;

  Future<(List<ProPlan>, Map<String, String>)> _load() async {
    final pro = ProService.instance;
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
    final kind = plan.kind == 'global' ? 'Pro Global' : 'Pro Negocio';
    final message = 'Hola, pagué Stockealo $kind ${plan.periodLabel.toLowerCase()} '
        '(${_money(plan.price)}) para el negocio "${widget.business.name}". '
        'Mi cuenta es $email. Te adjunto el comprobante.';
    final digits = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(message)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      AppToast.showError(context, 'No se pudo abrir WhatsApp.');
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
          final plans = snapshot.data?.$1 ?? const <ProPlan>[];
          final settings = snapshot.data?.$2 ?? const <String, String>{};
          final loading = snapshot.connectionState != ConnectionState.done;
          return ListView(
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
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              if (loading)
                const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Center(child: CircularProgressIndicator()))
              else if (plans.isEmpty)
                _card(
                  c,
                  Text(
                    'Pro aún no está disponible en tu país. Si te dieron un código, puedes canjearlo abajo.',
                    style: TextStyle(fontSize: 14, height: 1.4, color: c.inkMuted),
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
                  child: Text(settings['legal_notice']!, style: TextStyle(fontSize: 11.5, height: 1.4, color: c.inkFaint)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(StockealoColors c, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.xs, 0, 0, AppSpace.sm),
        child: Text(label.toUpperCase(),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.inkFaint)),
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
              Icon(status.active ? Icons.workspace_premium_rounded : Icons.workspace_premium_outlined,
                  size: 32, color: status.active ? c.onAccent : c.accent),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(status.active ? 'Tienes Pro' : 'Stockealo Pro',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: status.active ? c.onAccent : c.ink)),
                    const SizedBox(height: 2),
                    Text(text, style: TextStyle(fontSize: 13.5, color: status.active ? c.onAccent.withOpacity(0.9) : c.inkMuted)),
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
                  Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.ink)),
                  Text(body, style: TextStyle(fontSize: 13, height: 1.35, color: c.inkMuted)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _plans(StockealoColors c, List<ProPlan> all) {
    final plans = all.where((p) => p.kind == _kind).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'business', label: Text('Pro Negocio')),
            ButtonSegment(value: 'global', label: Text('Pro Global')),
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
            _kind == 'business'
                ? 'Para "${widget.business.name}" y todo su equipo.'
                : 'Para todos los negocios donde eres dueño, también los que crees después.',
            style: TextStyle(fontSize: 13, color: c.inkMuted),
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
        color: selected ? c.accent.withOpacity(0.08) : c.surface,
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
                Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: selected ? c.accent : c.inkFaint),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Row(
                    children: [
                      Text(p.periodLabel, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
                      if (p.label != null) ...[
                        const SizedBox(width: AppSpace.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: c.warning.withOpacity(0.15), borderRadius: BorderRadius.circular(AppRadius.pill)),
                          child: Text(p.label!, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.warning)),
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
                          style: TextStyle(fontSize: 12, color: c.inkFaint, decoration: TextDecoration.lineThrough)),
                    Text(_money(p.price), style: AppText.amount(context, size: 17, weight: FontWeight.w800)),
                    Text(p.perLabel, style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(c, 'Cómo pagar'),
        _card(
          c,
          !nequiAvailable
              ? Text(
                  'Pronto podrás pagar desde la app. Mientras tanto, escríbenos para activar Pro con un código.',
                  style: TextStyle(fontSize: 14, height: 1.4, color: c.inkMuted),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _step(c, '1', plan == null ? 'Elige un plan arriba.' : 'Envía ${_money(plan.price)} por Nequi a:'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, AppSpace.xs, 0, AppSpace.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(nequi, style: AppText.amount(context, size: 18, weight: FontWeight.w800)),
                                if (settings['nequi_name'] != null)
                                  Text(settings['nequi_name']!, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: nequi));
                              AppToast.showSuccess(context, 'Número de Nequi copiado');
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('Copiar'),
                          ),
                        ],
                      ),
                    ),
                    _step(c, '2', 'Envíanos el comprobante por WhatsApp.'),
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

  Widget _step(StockealoColors c, String n, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.accent.withOpacity(0.12), shape: BoxShape.circle),
              child: Text(n, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.accent)),
            ),
            const SizedBox(width: AppSpace.sm + 2),
            Expanded(child: Text(text, style: TextStyle(fontSize: 14, color: c.ink))),
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
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 1.5),
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
