import 'package:flutter/material.dart';

import '../core/design/primary_action_button.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/app_toast.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_widgets.dart';

/// Negocios con Pro: quién, qué plan y hasta cuándo. Permite dar Pro a mano y terminarlo.
class AdminSubscriptionsPage extends StatefulWidget {
  const AdminSubscriptionsPage({super.key});

  @override
  State<AdminSubscriptionsPage> createState() => _AdminSubscriptionsPageState();
}

class _AdminSubscriptionsPageState extends State<AdminSubscriptionsPage> {
  List<AdminSubscription> _subs = const [];
  bool _onlyActive = true;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final subs = await ProAdminService.instance.listSubscriptions(onlyActive: _onlyActive);
      if (mounted) setState(() => _subs = subs);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _end(AdminSubscription s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Terminar esta suscripción?'),
        content: Text('${s.businessName ?? s.ownerEmail} pierde ${s.kindLabel} desde ya. No se puede deshacer, '
            'pero puedes volver a darle Pro.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Terminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ProAdminService.instance.endSubscription(s.id);
      if (mounted) AppToast.show(context, message: 'Suscripción terminada', type: ToastType.success);
      _load();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    }
  }

  Future<void> _grant() async {
    final granted = await showDialog<bool>(context: context, builder: (_) => const _GrantDialog());
    if (granted == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AdminLoadState(
      loading: _loading,
      error: _error,
      empty: _subs.isEmpty,
      emptyText: _onlyActive ? 'Ningún negocio tiene Pro activo.' : 'Todavía no hay suscripciones.',
      onRetry: _load,
    );
    return AdminPage(
      title: 'Suscripciones',
      subtitle: _loading ? null : '${_subs.length} ${_onlyActive ? 'activas' : 'en total'}',
      onRefresh: _load,
      actions: [
        FilledButton.icon(
          onPressed: _grant,
          icon: const Icon(Icons.card_giftcard_rounded, size: 18),
          label: const Text('Dar Pro'),
        ),
        const SizedBox(width: AppSpace.sm),
      ],
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Activas')),
              ButtonSegment(value: false, label: Text('Todas')),
            ],
            selected: {_onlyActive},
            onSelectionChanged: (v) {
              _onlyActive = v.first;
              _load();
            },
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (state.blocking)
          state
        else
          for (final s in _subs)
            AdminCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(s.businessName ?? 'Todos los negocios de ${s.ownerEmail}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                            ),
                            const SizedBox(width: AppSpace.sm),
                            AdminBadge(
                              !s.active ? 'Terminada' : (s.endingSoon() ? 'Vence pronto' : 'Activa'),
                              tone: !s.active ? AdminTone.neutral : (s.endingSoon() ? AdminTone.warn : AdminTone.good),
                            ),
                          ],
                        ),
                        Text('${s.kindLabel} · ${s.sourceLabel} · ${s.ownerEmail}',
                            overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.inkMuted)),
                        Text(
                          'Desde ${adminDate(s.startsAt)} · ${s.endsAt == null ? 'Permanente' : 'Hasta ${adminDate(s.endsAt)}'}',
                          style: TextStyle(fontSize: 12, color: c.inkFaint),
                        ),
                      ],
                    ),
                  ),
                  if (s.active)
                    TextButton(
                      onPressed: () => _end(s),
                      style: TextButton.styleFrom(foregroundColor: c.danger),
                      child: const Text('Terminar'),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}

/// Buscar un negocio y darle Pro Negocio por unos días o permanente
class _GrantDialog extends StatefulWidget {
  const _GrantDialog();

  @override
  State<_GrantDialog> createState() => _GrantDialogState();
}

class _GrantDialogState extends State<_GrantDialog> {
  List<AdminBusiness> _results = const [];
  AdminBusiness? _selected;
  int? _days = 30;
  bool _searching = false;
  bool _saving = false;

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final r = await ProAdminService.instance.findBusinesses(q);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    final b = _selected;
    if (b == null) return;
    setState(() => _saving = true);
    try {
      await ProAdminService.instance.grantPro(b.id, _days);
      if (!mounted) return;
      AppToast.show(context, message: '${b.name} ahora tiene Pro', type: ToastType.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: const Text('Dar Pro Negocio'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Para compensar un fallo, una cortesía o un pago recibido. Los días se suman al Pro que ya tenga.',
                style: TextStyle(fontSize: 13, color: c.inkMuted)),
            const SizedBox(height: AppSpace.md),
            TextField(
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: const InputDecoration(
                hintText: 'Nombre del negocio o correo del dueño',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            if (_searching) const LinearProgressIndicator(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final b in _results)
                    ListTile(
                      dense: true,
                      selected: _selected?.id == b.id,
                      selectedTileColor: c.successSoft,
                      title: Text(b.name),
                      subtitle: Text([b.ownerEmail ?? 'sin dueño', if (b.pro) 'ya tiene Pro'].join(' · ')),
                      onTap: () => setState(() => _selected = b),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final d in const <int?>[7, 30, 90, 365, null])
                  ChoiceChip(
                    label: Text(switch (d) {
                      null => 'Permanente',
                      7 => '1 semana',
                      30 => '1 mes',
                      90 => '3 meses',
                      _ => '1 año',
                    }),
                    selected: _days == d,
                    onSelected: (_) => setState(() => _days = d),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        SizedBox(
          width: 180,
          child: PrimaryActionButton(
            label: _saving ? 'Guardando…' : 'Dar Pro',
            icon: Icons.card_giftcard_rounded,
            onPressed: _selected == null || _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}
