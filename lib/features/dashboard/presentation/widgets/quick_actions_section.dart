import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/screens/modules_screen.dart';
import '../../../home/data/app_functions.dart';
import '../../../pro/data/pro_service.dart';
import '../../../pro/presentation/screens/pro_screen.dart';
import '../../../products/presentation/screens/product_form_screen.dart';
import '../../../products/presentation/widgets/catalog_generator_modal.dart';
import '../../../reports/presentation/screens/guided_import_screen.dart';
import '../../../reports/presentation/screens/profit_report_screen.dart';
import '../../../sales/presentation/widgets/quotations_list_modal.dart';
import '../../../team/presentation/screens/employees_screen.dart';
import '../../data/dashboard_repository.dart';
import '../../../sales/presentation/screens/promotions_screen.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../team/presentation/screens/roles_screen.dart';
import '../../../goals/presentation/goals_widgets.dart';
import '../../../home/navigation/app_pane.dart';

/// «Accesos rápidos» de Inicio (volvieron en la 0.12.1, a pedido del dueño):
/// llevan a una función en un toque. Salen de `kAppFunctions`, la misma lista
/// del buscador, así que cada función nueva que se registre ahí se puede fijar
/// aquí sin tocar este archivo. Cada acceso abre la pantalla única de la función.
class QuickActionsSection extends StatefulWidget {
  final Business business;
  final String role;
  final String? userName;
  final ValueChanged<int> onNavigateToTab;

  /// Para recargar Inicio al volver de una función (por ejemplo, tras vender)
  final VoidCallback onReturn;

  const QuickActionsSection({
    super.key,
    required this.business,
    required this.role,
    required this.userName,
    required this.onNavigateToTab,
    required this.onReturn,
  });

  @override
  State<QuickActionsSection> createState() => _QuickActionsSectionState();
}

class _QuickActionsSectionState extends State<QuickActionsSection> {
  final _repo = DashboardRepository.instance;
  List<String> _saved = const [];


  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await _repo.getQuickActions(widget.business.id);
    if (mounted) setState(() => _saved = saved);
  }

  List<AppFunction> _current(bool services) => resolveShortcuts(_saved, role: widget.role, services: services);

  Future<void> _customize(bool services) async {
    final picked = await QuickActionsCustomizer.show(
      context,
      current: _current(services).map((f) => f.id).toList(),
      available: findFunctions('', role: widget.role, services: services),
    );
    if (picked == null) return;
    await _repo.saveQuickActions(widget.business.id, picked);
    if (!mounted) return;
    setState(() => _saved = picked);
    AppToast.show(context, message: 'Accesos rápidos guardados', type: ToastType.success);
  }

  Future<void> _open(AppFunction f) async {
    final biz = widget.business;
    switch (f.id) {
      case 'quotes':
        await QuotationsListModal.show(context, businessId: biz.id);
      case 'new_product':
        await AppPane.open(context, (_) => ProductFormScreen(businessId: biz.id, userRole: widget.role));
      case 'import_excel':
        await GuidedImportScreen.open(context, businessId: biz.id);
      case 'catalog':
        await CatalogGeneratorModal.show(context: context, business: biz);
      case 'promotions':
        await PromotionsScreen.open(context, business: biz);
      case 'profits':
        await ProfitReportScreen.open(context, biz);
      case 'goals':
        await GoalsView.open(context, business: biz, role: widget.role);
      case 'team':
        await AppPane.open(context, (_) => EmployeesScreen(business: biz));
      case 'roles':
        await RolesScreen.open(context, business: biz, canEdit: widget.role == Permissions.owner);
      case 'modules':
        await ModulesScreen.open(context, business: biz, canEdit: Permissions.can(widget.role, Perm.modules));
      case 'pro':
        await ProScreen.open(context, biz);
      default:
        // Las que tienen su propio lugar en el menú (Caja, Stock, Clientes y
        // proveedores, Tienda, Servicios…) llevan a ese lugar, sin abrir copias
        widget.onNavigateToTab(f.tab);
        return;
    }
    widget.onReturn();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ProService.instance.status,
      builder: (context, status, _) {
        final services = status.services;
        final items = _current(services);
        // Una sola fila, arriba del Inicio (0.16.1). Si no caben, se desliza: en el
        // celular se ven 4 y un pedazo del siguiente, para que se note que hay más.
        return Semantics(
          label: 'Accesos rápidos',
          container: true,
          child: LayoutBuilder(builder: (context, box) {
            const gap = AppSpace.sm;
            final count = items.length + 1;
            final fits = (box.maxWidth - gap * (count - 1)) / count >= 84;
            // Nunca más angosto que 64 px (en una ventana muy estrecha, simplemente se desliza)
            final w = math.max(64.0, fits ? (box.maxWidth - gap * (count - 1)) / count : (box.maxWidth - gap * 4) / 4.4);
            final tiles = [
              for (final f in items) _tile(f),
              _tile(null, onTap: () => _customize(services)),
            ];
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: fits ? const NeverScrollableScrollPhysics() : null,
              // Todos del mismo alto, tengan el nombre en una o dos líneas (0.16.3)
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      SizedBox(width: w, child: tiles[i]),
                    ],
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }

  /// Un acceso; sin función es «Editar» (elegir y ordenar los accesos)
  Widget _tile(AppFunction? f, {VoidCallback? onTap}) {
    final c = context.colors;
    final edit = f == null;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: edit ? c.lineStrong : c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: edit ? onTap : () => _open(f),
        child: Tooltip(
          message: edit ? 'Elegir y ordenar los accesos rápidos' : f.where,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm + 2, horizontal: AppSpace.xs),
            child: Column(
              children: [
                Icon(edit ? Icons.tune_outlined : f.icon, color: edit ? c.inkMuted : c.accent, size: 22),
                const SizedBox(height: 6),
                Text(
                  edit ? 'Editar' : f.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption(context, weight: FontWeight.w600, color: c.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoja para elegir y ordenar los accesos rápidos de Inicio
class QuickActionsCustomizer {
  /// Devuelve la selección nueva, o null si se cerró sin guardar
  static Future<List<String>?> show(
    BuildContext context, {
    required List<String> current,
    required List<AppFunction> available,
  }) async {
    final selected = List<String>.from(current);
    final byId = {for (final f in available) f.id: f};

    final saved = await AppSheet.show<bool>(
      context: context,
      title: 'Accesos rápidos',
      subtitle: 'Toca una función para fijarla en Inicio. Arrástrala desde el asa para cambiar el orden.',
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final c = ctx.colors;
        final toAdd = available.where((f) => !selected.contains(f.id)).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${selected.length} de $kMaxShortcuts fijados', style: AppText.small(ctx, weight: FontWeight.w600)),
            const SizedBox(height: AppSpace.sm),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: selected.length,
              // onReorderItem ya entrega la posición final, sin restar 1
              onReorderItem: (from, to) => setSheet(() => selected.insert(to, selected.removeAt(from))),
              itemBuilder: (_, i) {
                final f = byId[selected[i]]!;
                return Padding(
                  key: ValueKey(f.id),
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: c.line),
                    ),
                    child: Row(
                      children: [
                        Icon(f.icon, color: c.accent, size: 20),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.title, style: AppText.body(ctx, weight: FontWeight.w600)),
                              Text(f.where, style: AppText.caption(ctx)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Quitar de Inicio',
                          icon: Icon(Icons.close_outlined, size: 18, color: c.inkMuted),
                          onPressed: () {
                            if (selected.length > 1) {
                              setSheet(() => selected.removeAt(i));
                            } else {
                              AppToast.show(ctx, message: 'Deja al menos un acceso rápido', type: ToastType.warning);
                            }
                          },
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Tooltip(
                            message: 'Arrastra para cambiar el orden',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                              child: Icon(Icons.drag_indicator_outlined, color: c.inkMuted),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (toAdd.isNotEmpty) ...[
              const SectionLabel('PARA AGREGAR', padding: EdgeInsets.fromLTRB(0, AppSpace.lg, 0, AppSpace.sm)),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final f in toAdd)
                    ActionChip(
                      avatar: Icon(f.icon, size: 16, color: c.accent),
                      label: Text(f.title),
                      onPressed: () {
                        if (selected.length >= kMaxShortcuts) {
                          AppToast.show(ctx,
                              message: 'Máximo $kMaxShortcuts accesos, para que Inicio se vea ordenado',
                              type: ToastType.warning);
                          return;
                        }
                        setSheet(() => selected.add(f.id));
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        );
      }),
    );
    return saved == true ? selected : null;
  }
}
