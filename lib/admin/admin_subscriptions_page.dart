import 'dart:async';

import 'package:flutter/material.dart';

import '../core/design/primary_action_button.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/app_toast.dart';
import '../features/pro/data/pro_admin_service.dart';
import '../features/pro/data/pro_service.dart' show proKindLabel;
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
        // Dar y terminar Pro: solo el dueño del panel (el servidor también lo exige)
        if (ProAdminService.instance.isOwner)
        FilledButton.icon(
          onPressed: _grant,
          icon: const Icon(Icons.card_giftcard_outlined, size: 18),
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
                  if (s.active && ProAdminService.instance.isOwner)
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

  /// 'business' (Pro Negocio) o 'services' (Pro Servicios: Pro + módulo Servicios)
  String _kind = 'business';
  bool _searching = false;
  bool _searched = false;
  bool _saving = false;
  Timer? _debounce;
  int _searchId = 0;

  @override
  void initState() {
    super.initState();
    // Al abrir se ven los negocios más recientes, para elegir sin escribir
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Busca mientras se escribe (antes solo con Enter y, sin lista, "Dar Pro" no hacía nada)
  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final id = ++_searchId;
    setState(() => _searching = true);
    try {
      final r = await ProAdminService.instance.findBusinesses(q.trim());
      if (!mounted || id != _searchId) return; // llegó una búsqueda más nueva
      setState(() {
        _results = r;
        _searched = true;
        // Un solo resultado al buscar algo concreto: queda elegido
        if (q.trim().isNotEmpty && r.length == 1) {
          _selected = r.first;
        } else if (_selected != null && !r.any((b) => b.id == _selected!.id)) {
          _selected = null;
        }
      });
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    } finally {
      if (mounted && id == _searchId) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    final b = _selected;
    if (b == null) return;
    setState(() => _saving = true);
    try {
      await ProAdminService.instance.grantPro(b.id, _days, kind: _kind);
      if (!mounted) return;
      AppToast.show(context, message: '${b.name} ahora tiene ${proKindLabel(_kind)}', type: ToastType.success);
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
      title: const Text('Dar Pro'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Para compensar un fallo, una cortesía o un pago recibido. Los días se suman a lo que ya tenga de ese plan.',
                style: TextStyle(fontSize: 13, color: c.inkMuted)),
            const SizedBox(height: AppSpace.md),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'business', label: Text('Pro Negocio')),
                ButtonSegment(value: 'services', label: Text('Pro Servicios')),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
            if (_kind == 'services')
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Text('Todo Pro más el módulo Servicios (lavaderos, barberías, talleres), con soporte.',
                    style: TextStyle(fontSize: 12, color: c.inkMuted)),
              ),
            const SizedBox(height: AppSpace.md),
            TextField(
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              onSubmitted: _search,
              decoration: const InputDecoration(
                hintText: 'Nombre del negocio o correo del dueño',
                prefixIcon: Icon(Icons.search_outlined),
              ),
            ),
            SizedBox(height: 3, child: _searching ? const LinearProgressIndicator() : null),
            if (_searched && !_searching && _results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                child: Text(
                  'No encontramos ese negocio. Revisa el nombre o el correo del dueño '
                  '(el negocio tiene que estar en la nube).',
                  style: TextStyle(fontSize: 13, color: c.inkMuted),
                ),
              ),
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
                      trailing: _selected?.id == b.id ? Icon(Icons.check_circle_outlined, color: c.accent) : null,
                      title: Text(b.name),
                      subtitle: Text([b.ownerEmail ?? 'sin dueño', if (b.pro) 'ya tiene Pro'].join(' · ')),
                      onTap: () => setState(() => _selected = b),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              _selected == null ? 'Elige el negocio en la lista.' : 'Le darás ${proKindLabel(_kind)} a ${_selected!.name}.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _selected == null ? c.warning : c.ink),
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
            icon: Icons.card_giftcard_outlined,
            onPressed: _selected == null || _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}
