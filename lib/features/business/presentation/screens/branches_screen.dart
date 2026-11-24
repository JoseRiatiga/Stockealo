import 'package:flutter/material.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../home/navigation/app_pane.dart';
import '../../../pro/presentation/screens/pro_screen.dart';
import '../../data/branch_repository.dart';
import '../../models/business.dart';

/// Ajustes › Tu negocio › Módulos › Sedes (0.18.0, docs/plan-sedes.md).
/// Solo el dueño abre, cierra y reabre sedes (cuestan un cupo). Cerrar nunca borra:
/// la sede cerrada conserva sus ventas, cajas y fiados para verlos y descargarlos.
class BranchesScreen extends StatefulWidget {
  final Business business;
  final bool isOwner;

  const BranchesScreen({super.key, required this.business, required this.isOwner});

  static Future<void> open(BuildContext context, {required Business business, required bool isOwner}) =>
      AppPane.push(context, MaterialPageRoute(builder: (_) => BranchesScreen(business: business, isOwner: isOwner)));

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  final _repo = BranchRepository.instance;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_changed);
    _refresh();
  }

  @override
  void dispose() {
    _repo.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    await _repo.refresh();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) AppToast.showSuccess(context, done);
    } catch (e) {
      if (mounted) AppToast.showError(context, BranchRepository.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Nombre, dirección y teléfono de una sede
  Future<({String name, String address, String phone})?> _askData({String title = 'Nueva sede', Branch? from, bool onlyName = false}) async {
    final name = TextEditingController(text: from?.name ?? '');
    final address = TextEditingController(text: from?.address ?? '');
    final phone = TextEditingController(text: from?.phone ?? '');
    final ok = await AppDialog.show<bool>(
      context: context,
      title: title,
      content: Builder(builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Norte, Centro, Plaza…')),
          if (!onlyName) ...[
            const SizedBox(height: AppSpace.sm),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'Dirección (opcional)')),
            const SizedBox(height: AppSpace.sm),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (opcional)')),
          ],
        ],
      )),
      actions: [
        Builder(builder: (ctx) => TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar'))),
        Builder(builder: (ctx) => FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar'))),
      ],
    );
    if (ok != true || name.text.trim().isEmpty) return null;
    return (name: name.text.trim(), address: address.text.trim(), phone: phone.text.trim());
  }

  Future<void> _create() async {
    if (_repo.freeSlots == 0) {
      final go = await AppDialog.confirm(
        context: context,
        title: 'Sin cupos libres',
        message: _repo.allowance == 0
            ? 'Las sedes vienen con Stockealo Pro. Pro Servicios trae 2 sedes; con Pro, cada sede se agrega aparte.'
            : 'Ya usas tus ${_repo.allowance} cupos de sede. Pide uno más para abrir otra.',
        confirmText: 'Ver Stockealo Pro',
      );
      if (go && mounted) ProScreen.open(context, widget.business);
      return;
    }
    if (_repo.openBranches.isEmpty) {
      final ok = await AppDialog.confirm(
        context: context,
        title: 'Antes de la primera sede',
        message: 'Pide a todo tu equipo que actualice Stockealo a la última versión. '
            'Un celular con la app vieja solo ve y vende en la sede Principal.',
        confirmText: 'Ya lo hicimos',
      );
      if (!ok) return;
    }
    final data = await _askData();
    if (data == null) return;
    await _run(() => _repo.create(name: data.name, address: data.address, phone: data.phone), 'Sede «${data.name}» abierta');
  }

  Future<void> _edit(Branch b) async {
    final data = await _askData(title: 'Editar sede', from: b);
    if (data == null) return;
    await _run(() => _repo.update(b, name: data.name, address: data.address, phone: data.phone), 'Sede guardada');
  }

  Future<void> _renameMain() async {
    final data = await _askData(
      title: 'Nombre de la sede Principal',
      from: Branch(id: '', businessId: widget.business.id, name: _repo.mainName, createdAt: DateTime.now()),
      onlyName: true,
    );
    if (data == null) return;
    await _run(() => _repo.renameMain(data.name), 'Nombre guardado');
  }

  /// Cerrar: el dueño elige a qué sede pasan la mercancía y las personas
  Future<void> _close(Branch b) async {
    final targets = <String?, String>{
      null: '${_repo.mainName} (Principal)',
      for (final o in _repo.openBranches.where((o) => o.id != b.id)) o.id: o.name,
    };
    String? target;
    final ok = await AppDialog.show<bool>(
      context: context,
      title: 'Cerrar ${b.name}',
      content: StatefulBuilder(
        builder: (ctx, set) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sus ventas, cajas y fiados no se borran: se ven y se descargan. El cupo queda libre hasta tu próxima renovación '
              'para abrir otra sede o reabrir esta. Antes de cerrar, cierra su caja.',
              style: AppText.small(ctx, color: ctx.colors.inkMuted),
            ),
            const SizedBox(height: AppSpace.md),
            Text('¿A dónde pasan su mercancía y sus personas?', style: AppText.body(ctx, weight: FontWeight.w700)),
            RadioGroup<String?>(
              groupValue: target,
              onChanged: (v) => set(() => target = v),
              child: Column(children: [
                for (final e in targets.entries) RadioListTile<String?>(value: e.key, title: Text(e.value), contentPadding: EdgeInsets.zero),
              ]),
            ),
          ],
        ),
      ),
      actions: [
        Builder(builder: (ctx) => TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar'))),
        Builder(builder: (ctx) => FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar sede'))),
      ],
    );
    if (ok != true) return;
    await _run(() => _repo.close(b, target: target), '${b.name} quedó cerrada');
  }

  Future<void> _reopen(Branch b) => _run(() => _repo.reopen(b), '${b.name} volvió a abrir');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final open = _repo.openBranches;
    final closed = _repo.branches.where((b) => b.isClosed).toList();
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(title: const Text('Sedes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ContentListView(
                padding: const EdgeInsets.all(AppSpace.lg),
                children: [
                  Text(
                    'Cada sede tiene su stock, sus ventas y su caja. El catálogo, los clientes y la tienda en línea son del negocio.',
                    style: AppText.small(context, color: c.inkMuted),
                  ),
                  const SizedBox(height: AppSpace.md),
                  AppCard(
                    child: Row(
                      children: [
                        Icon(Icons.confirmation_number_outlined, color: c.accent),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(
                            _repo.allowance == 0
                                ? 'Tu plan no trae sedes extra'
                                : 'Sedes extra: ${open.length} de ${_repo.allowance} cupos en uso',
                            style: AppText.body(context, weight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  AppCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.home_work_outlined, color: c.accent),
                      title: Text(_repo.mainName, style: AppText.body(context, weight: FontWeight.w700)),
                      subtitle: Text('Sede Principal · no se cierra', style: AppText.caption(context)),
                      trailing: widget.isOwner
                          ? IconButton(tooltip: 'Cambiar nombre', onPressed: _busy ? null : _renameMain, icon: const Icon(Icons.edit_outlined))
                          : null,
                    ),
                  ),
                  for (final b in open)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.sm),
                      child: AppCard(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.place_outlined, color: b.isInactive ? c.warning : c.accent),
                          title: Text(b.name, style: AppText.body(context, weight: FontWeight.w700)),
                          subtitle: Text(
                            [
                              if ((b.address ?? '').isNotEmpty) b.address!,
                              if (b.isInactive) 'Inactiva: sin cupo en tu plan. Se ve y se descarga, no se vende',
                            ].join(' · ').isEmpty
                                ? 'Abierta'
                                : [
                                    if ((b.address ?? '').isNotEmpty) b.address!,
                                    if (b.isInactive) 'Inactiva: sin cupo en tu plan. Se ve y se descarga, no se vende',
                                  ].join(' · '),
                            style: AppText.caption(context),
                          ),
                          trailing: widget.isOwner
                              ? PopupMenuButton<String>(
                                  enabled: !_busy,
                                  onSelected: (v) => v == 'edit' ? _edit(b) : _close(b),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                                    PopupMenuItem(value: 'close', child: Text('Cerrar sede')),
                                  ],
                                )
                              : null,
                        ),
                      ),
                    ),
                  if (widget.isOwner) ...[
                    const SizedBox(height: AppSpace.md),
                    FilledButton.icon(
                      onPressed: _busy ? null : _create,
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Abrir una sede'),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.md),
                      child: Text('Solo el dueño del negocio abre y cierra sedes.', style: AppText.small(context, color: c.inkMuted)),
                    ),
                  if (closed.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xl),
                    Text('Cerradas', style: AppText.title(context)),
                    const SizedBox(height: AppSpace.xs),
                    for (final b in closed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.location_off_outlined, color: c.inkFaint),
                        title: Text(b.name),
                        subtitle: Text('Su historial se ve y se descarga', style: AppText.caption(context)),
                        trailing: widget.isOwner
                            ? TextButton(onPressed: _busy ? null : () => _reopen(b), child: const Text('Reabrir'))
                            : null,
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
