import 'package:flutter/material.dart';

import '../core/design/primary_action_button.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/currency_formatter.dart';
import '../core/widgets/app_toast.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_widgets.dart';

/// Datos de pago (Nequi, WhatsApp), oferta Fundador y precios de los planes
class AdminConfigPage extends StatefulWidget {
  const AdminConfigPage({super.key});

  @override
  State<AdminConfigPage> createState() => _AdminConfigPageState();
}

/// Ajustes editables: clave en pro_settings → etiqueta y ayuda
const _fields = <String, (String, String)>{
  'nequi_number': ('Número de Nequi', 'Al que los clientes envían el pago'),
  'nequi_name': ('Nombre en Nequi', 'Para que confirmen a quién le pagan'),
  'whatsapp': ('WhatsApp de ventas', 'Con prefijo, ej.: +57 300 123 4567'),
  'founder_slots': ('Cupos de la oferta Fundador', 'Número'),
  'founder_until': ('Oferta Fundador hasta', 'Fecha AAAA-MM-DD'),
  'legal_notice': ('Aviso de precios', 'Se muestra debajo de los planes'),
  'wompi_public_key': ('Llave pública de Wompi', 'pub_test_… solo la ven los administradores; pub_prod_… cobra de verdad'),
};

class _AdminConfigPageState extends State<AdminConfigPage> {
  final _controllers = {for (final k in _fields.keys) k: TextEditingController()};
  AdminConfig? _config;
  bool _loading = true;
  bool _saving = false;
  bool _savingPricing = false;
  String? _error;

  /// «Mostrar precios y compra en la app» (pro_settings.show_pricing = 'on' / 'off')
  bool get _showPricing => _config?.settings['show_pricing'] == 'on';

  Future<void> _setShowPricing(bool on) async {
    setState(() => _savingPricing = true);
    try {
      await ProAdminService.instance.setSetting('show_pricing', on ? 'on' : 'off');
      if (mounted) {
        AppToast.show(
          context,
          message: on ? 'Los precios y la compra ya se ven en la app.' : 'Precios y compra ocultos en la app.',
          type: ToastType.success,
        );
      }
      await _load();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _savingPricing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await ProAdminService.instance.config();
      if (!mounted) return;
      for (final e in _controllers.entries) {
        e.value.text = config.settings[e.key] ?? '';
      }
      setState(() => _config = config);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      for (final e in _controllers.entries) {
        final old = _config?.settings[e.key] ?? '';
        if (e.value.text.trim() != old.trim()) {
          await ProAdminService.instance.setSetting(e.key, e.value.text);
        }
      }
      if (mounted) AppToast.show(context, message: 'Datos guardados', type: ToastType.success);
      _load();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editPlan(AdminPlan plan) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _PlanDialog(plan: plan));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AdminLoadState(loading: _loading, error: _error, empty: _config == null, emptyText: '', onRetry: _load);
    return AdminPage(
      title: 'Configuración',
      subtitle: 'Lo que ven los clientes en Ajustes › Stockealo Pro',
      onRefresh: _load,
      children: state.blocking
          ? [state]
          : [
              AdminCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _showPricing,
                  onChanged: _savingPricing ? null : _setShowPricing,
                  title: Text('Mostrar precios y compra en la app',
                      style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                  subtitle: Text(
                    _showPricing
                        ? 'Los clientes ven los planes encendidos con su precio y pueden pagar.'
                        : 'Apagado: la app muestra lo que incluye cada plan y el canje de códigos, sin precios ni pagos. '
                            'Los planes se dan con «Dar Pro» o con códigos.',
                    style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Pago y contacto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
                    const SizedBox(height: AppSpace.md),
                    for (final e in _fields.entries) ...[
                      TextField(
                        controller: _controllers[e.key],
                        maxLines: e.key == 'legal_notice' ? 3 : 1,
                        minLines: 1,
                        decoration: InputDecoration(labelText: e.value.$1, helperText: e.value.$2),
                      ),
                      const SizedBox(height: AppSpace.md),
                    ],
                    PrimaryActionButton(
                      label: _saving ? 'Guardando…' : 'Guardar',
                      icon: Icons.save_outlined,
                      onPressed: _saving ? null : _saveSettings,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Text('Planes y precios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: AppSpace.sm),
              for (final p in _config!.plans)
                AdminCard(
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.xs, AppSpace.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(child: Text(p.name, style: TextStyle(fontWeight: FontWeight.w600, color: c.ink))),
                                if (p.label != null) ...[const SizedBox(width: AppSpace.sm), AdminBadge(p.label!)],
                                if (!p.active) ...[
                                  const SizedBox(width: AppSpace.sm),
                                  const AdminBadge('Oculto', tone: AdminTone.bad),
                                ],
                              ],
                            ),
                            Text(
                              [
                                CurrencyFormatter.formatIn(p.price, p.currency),
                                if (p.regularPrice != null) 'antes ${CurrencyFormatter.formatIn(p.regularPrice!, p.currency)}',
                                p.currency,
                              ].join(' · '),
                              style: TextStyle(fontSize: 13, color: c.inkMuted),
                            ),
                          ],
                        ),
                      ),
                      TextButton(onPressed: () => _editPlan(p), child: const Text('Editar')),
                    ],
                  ),
                ),
            ],
    );
  }
}

class _PlanDialog extends StatefulWidget {
  final AdminPlan plan;

  const _PlanDialog({required this.plan});

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  late final _price = TextEditingController(text: widget.plan.price.toStringAsFixed(0));
  late final _regular = TextEditingController(text: widget.plan.regularPrice?.toStringAsFixed(0) ?? '');
  late final _label = TextEditingController(text: widget.plan.label ?? '');
  late bool _active = widget.plan.active;
  bool _saving = false;

  @override
  void dispose() {
    _price.dispose();
    _regular.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.trim());
    final regular = _regular.text.trim().isEmpty ? null : double.tryParse(_regular.text.trim());
    if (price == null || (_regular.text.trim().isNotEmpty && regular == null)) {
      AppToast.show(context, message: 'Escribe los precios solo con números.', type: ToastType.warning);
      return;
    }
    setState(() => _saving = true);
    try {
      await ProAdminService.instance.setPlan(widget.plan, price: price, regularPrice: regular, label: _label.text, active: _active);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.plan.name),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Precio (${widget.plan.currency})'),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _regular,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Precio normal tachado (opcional)', helperText: 'Para ofertas'),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(controller: _label, decoration: const InputDecoration(labelText: 'Etiqueta (opcional)', hintText: 'Fundador')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Visible para los clientes'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar')),
      ],
    );
  }
}
