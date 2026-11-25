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
import '../widgets/branch_form_dialog.dart';

/// Ajustes › Tu negocio › Módulos › Sedes (0.18.0, docs/plan-sedes.md).
/// Solo el dueño abre, cierra y reabre sedes (cuestan un cupo). Cerrar nunca borra:
/// la sede cerrada conserva sus ventas, cajas y fiados para verlos y descargarlos.
class BranchesScreen extends StatefulWidget {
  final Business business;
  final bool isOwner;

  const BranchesScreen({super.key, required this.business, required this.isOwner});

  /// Abrir una sede nueva (solo el dueño). Un solo lugar (24 nov): lo usan Módulos ›
  /// Sedes y «＋ Abrir una sede» del menú lateral. Sin cupo libre lleva a Stockealo Pro.
  static Future<void> createBranch(BuildContext context, Business business) async {
    final repo = BranchRepository.instance;
    if (repo.freeSlots == 0) {
      final go = await AppDialog.confirm(
        context: context,
        title: 'Sin cupos libres',
        message: repo.allowance == 0
            ? 'Las sedes vienen con Stockealo Pro. Pro Servicios trae 2 sedes; con Pro, cada sede se agrega aparte.'
            : 'Ya usas tus ${repo.allowance} cupos de sede. Agrega uno más para abrir otra.',
        confirmText: 'Ver Stockealo Pro',
      );
      if (go && context.mounted) ProScreen.open(context, business);
      return;
    }
    if (repo.openBranches.isEmpty) {
      final ok = await AppDialog.confirm(
        context: context,
        title: 'Antes de la primera sede',
        message: 'Pide a todo tu equipo que actualice Stockealo a la última versión. '
            'Un celular con la app vieja solo ve y vende en la sede Principal.',
        confirmText: 'Ya lo hicimos',
      );
      if (!ok || !context.mounted) return;
    }
    final used = repo.openBranches.length + 1;
    final data = await BranchFormDialog.show(
      context,
      title: 'Nueva sede',
      actionLabel: 'Abrir sede',
      taken: [repo.mainName, for (final b in repo.branches) b.name],
      country: business.country,
      slotsNote: 'Usarás $used de ${repo.allowance} cupos de sede.',
    );
    if (data == null) return;
    try {
      await repo.create(name: data.name, address: data.address, phone: data.phone);
      if (context.mounted) AppToast.showSuccess(context, 'Sede «${data.name}» abierta');
    } catch (e) {
      if (context.mounted) AppToast.showError(context, BranchRepository.friendlyError(e));
    }
  }

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

  /// Los nombres en uso (la Principal y las otras sedes), menos el de [except]
  List<String> _taken({String? except}) =>
      [if (except != '') _repo.mainName, for (final b in _repo.branches) if (b.id != except) b.name];

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      await BranchesScreen.createBranch(context, widget.business);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Branch b) async {
    final data = await BranchFormDialog.show(
      context,
      title: 'Editar sede',
      actionLabel: 'Guardar',
      taken: _taken(except: b.id),
      name: b.name,
      address: b.address,
      phone: b.phone,
      country: widget.business.country,
    );
    if (data == null) return;
    await _run(() => _repo.update(b, name: data.name, address: data.address, phone: data.phone), 'Sede guardada');
  }

  Future<void> _renameMain() async {
    final data = await BranchFormDialog.show(
      context,
      title: 'Nombre de la sede Principal',
      actionLabel: 'Guardar',
      taken: _taken(except: ''),
      name: _repo.mainName,
      onlyName: true,
    );
    if (data == null) return;
    await _run(() => _repo.renameMain(data.name), 'Nombre guardado');
  }

  /// Cerrar: el dueño elige a qué sede pasan la mercancía y las personas
  Future<void> _close(Branch b) async {
    final targets = <String?, String>{
      null: _repo.mainName == BranchRepository.mainDefaultName ? _repo.mainName : '${_repo.mainName} · Principal',
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
