import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/screens/modules_screen.dart';
import '../../../cash/presentation/screens/cash_register_screen.dart';
import '../../../customers/presentation/screens/customers_screen.dart';
import '../../../home/data/app_functions.dart';
import '../../../pro/data/pro_service.dart';
import '../../../pro/presentation/screens/pro_screen.dart';
import '../../../products/presentation/screens/product_form_screen.dart';
import '../../../products/presentation/widgets/catalog_generator_modal.dart';
import '../../../reports/presentation/screens/guided_import_screen.dart';
import '../../../reports/presentation/screens/profit_report_screen.dart';
import '../../../sales/presentation/widgets/quick_sale_dialog.dart';
import '../../../sales/presentation/widgets/quotations_list_modal.dart';
import '../../../store/presentation/screens/online_store_screen.dart';
import '../../../suppliers/presentation/screens/suppliers_screen.dart';
import '../../../team/presentation/screens/employees_screen.dart';
import '../../data/dashboard_repository.dart';

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

  bool get _managers => widget.role == 'OWNER' || widget.role == 'ADMIN';

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
      case 'new_sale':
        await QuickSaleDialog.show(context);
      case 'customers':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomersScreen(businessId: biz.id)));
      case 'quotes':
        await QuotationsListModal.show(context, businessId: biz.id);
      case 'cash':
        if (biz.cashRegisterEnabled) {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => CashRegisterScreen(businessId: biz.id, userName: widget.userName ?? '')));
        } else {
          // La caja está apagada: se enciende en Módulos
          await ModulesScreen.open(context, business: biz, canEdit: _managers);
        }
      case 'new_product':
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => ProductFormScreen(businessId: biz.id, userRole: widget.role)));
      case 'import_excel':
        await GuidedImportScreen.open(context, businessId: biz.id);
      case 'suppliers':
        await SuppliersScreen.open(context, business: biz, userName: widget.userName);
      case 'catalog':
        await CatalogGeneratorModal.show(context: context, business: biz);
      case 'online_store':
        await OnlineStoreScreen.open(context, biz);
      case 'profits':
        await ProfitReportScreen.open(context, biz);
      case 'team':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeesScreen(business: biz)));
      case 'modules':
        await ModulesScreen.open(context, business: biz, canEdit: _managers);
      case 'pro':
        await ProScreen.open(context, biz);
      default:
        // Funciones sin pantalla propia (Servicios, Descargar Excel, Apariencia,
        // Nube y respaldo): se llega a su pestaña, igual que con el buscador
        widget.onNavigateToTab(f.tab);
        return;
    }
    widget.onReturn();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder(
      valueListenable: ProService.instance.status,
      builder: (context, status, _) {
        final services = status.services;
        final items = _current(services);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Accesos rápidos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
                ),
                TextButton.icon(
                  onPressed: () => _customize(services),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Personalizar'),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            LayoutBuilder(builder: (context, box) {
              // 4 por fila en el celular, hasta 8 en una sola fila en pantallas anchas
              final perRow = box.maxWidth >= 700 ? kMaxShortcuts : 4;
              const gap = AppSpace.sm;
              final w = (box.maxWidth - gap * (perRow - 1)) / perRow;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [for (final f in items) SizedBox(width: w, child: _tile(f))],
              );
            }),
          ],
        );
      },
    );
  }

  Widget _tile(AppFunction f) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => _open(f),
        child: Tooltip(
          message: f.where,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.md, horizontal: AppSpace.xs),
            child: Column(
              children: [
                Icon(f.icon, color: c.accent, size: 24),
                const SizedBox(height: 6),
                Text(
                  f.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w600, color: c.ink),
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

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final c = ctx.colors;
        final toAdd = available.where((f) => !selected.contains(f.id)).toList();
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.8,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpace.lg, 0, AppSpace.lg, MediaQuery.of(ctx).padding.bottom + AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Accesos rápidos',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
                    ),
                    Text('${selected.length} de $kMaxShortcuts',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.inkMuted)),
                  ],
                ),
                const SizedBox(height: 2),
                Text('Toca una función para fijarla en Inicio. Arrastra ☰ para cambiar el orden.',
                    style: TextStyle(fontSize: 13, color: c.inkMuted)),
                const SizedBox(height: AppSpace.md),
                Expanded(
                  child: ListView(
                    children: [
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: selected.length,
                        onReorder: (from, to) => setSheet(() {
                          if (from < to) to -= 1;
                          selected.insert(to, selected.removeAt(from));
                        }),
                        itemBuilder: (_, i) {
                          final f = byId[selected[i]]!;
                          return Padding(
                            key: ValueKey(f.id),
                            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                              decoration: BoxDecoration(
                                color: c.surfaceMuted,
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
                                        Text(f.title,
                                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: c.ink)),
                                        Text(f.where, style: TextStyle(fontSize: 12, color: c.inkMuted)),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Quitar de Inicio',
                                    icon: Icon(Icons.close_rounded, size: 18, color: c.inkMuted),
                                    onPressed: () {
                                      if (selected.length > 1) {
                                        setSheet(() => selected.removeAt(i));
                                      } else {
                                        AppToast.show(ctx,
                                            message: 'Deja al menos un acceso rápido', type: ToastType.warning);
                                      }
                                    },
                                  ),
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                                      child: Icon(Icons.drag_handle_rounded, color: c.inkMuted),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      if (toAdd.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.lg),
                        Text('Para agregar',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.inkMuted)),
                        const SizedBox(height: AppSpace.sm),
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
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Guardar'),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
    return saved == true ? selected : null;
  }
}
