import 'package:flutter/material.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../data/services_repository.dart';
import '../../models/service_models.dart';
import '../widgets/employees_view.dart';
import '../widgets/board_view.dart';
import '../widgets/catalog_view.dart';
import '../widgets/commissions_view.dart';
import '../widgets/history_view.dart';
import '../widgets/messages_view.dart';
import '../../../../core/design/filter_tabs.dart';

/// Secciones de la pestaña Servicios
enum ServicesSection {
  board('Tablero', Icons.view_kanban_outlined),
  employees('Empleados', Icons.badge_outlined),
  history('Historial', Icons.history_outlined),
  commissions('Comisiones', Icons.payments_outlined),
  catalog('Catálogo y precios', Icons.sell_outlined),
  messages('Mensajes', Icons.chat_outlined);

  final String label;
  final IconData icon;

  const ServicesSection(this.label, this.icon);
}

/// Pestaña Servicios (Pro Servicios). La primera vez el negocio elige su tipo y
/// recibe la plantilla; después: Tablero, Empleados, Historial y Catálogo.
/// Los empleados se agregan en Empleados (o en Ajustes › Equipo, la misma hoja).
class ServicesTab extends StatefulWidget {
  final Business? business;
  final String userRole;

  /// Lleva a Ajustes › Equipo (para agregar personas)
  final VoidCallback? onOpenTeam;

  const ServicesTab({super.key, required this.business, required this.userRole, this.onOpenTeam});

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> {
  ServicesSection _section = ServicesSection.board;
  bool _migrating = false;

  bool get _canConfigure => widget.userRole == 'OWNER' || widget.userRole == 'ADMIN';

  @override
  void initState() {
    super.initState();
    _migrateIfLegacy();
  }

  @override
  void didUpdateWidget(covariant ServicesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.business?.id != widget.business?.id) {
      _section = ServicesSection.board;
      _migrateIfLegacy();
    }
  }

  /// Los lavaderos de la 0.11.0 pasan a la plantilla de motos y carros
  Future<void> _migrateIfLegacy() async {
    final b = widget.business;
    if (b == null || b.serviceType != 'LAVADERO_MOTOS' || _migrating) return;
    _migrating = true;
    try {
      await ServicesRepository.instance.migrateLegacyLavadero(b.id, b.serviceType);
    } finally {
      _migrating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = widget.business;
    if (b == null) {
      return Center(child: Text('Elige un negocio para usar Servicios.', style: TextStyle(color: c.inkMuted)));
    }
    if (!b.servicesEnabled || b.serviceType == null) {
      return TemplatePicker(business: b, canConfigure: _canConfigure);
    }
    final template = ServiceTemplate.of(b.serviceType);
    final sections = [
      for (final s in ServicesSection.values)
        // Comisiones y catálogo: solo dueño o administrador
        if (!const {ServicesSection.catalog, ServicesSection.commissions, ServicesSection.messages}.contains(s) || _canConfigure) s,
    ];

    return Scaffold(
      backgroundColor: c.paper,
      body: Column(
        children: [
          ContentWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                // Las secciones con las mismas pestañas del resto de la app (re-diseño 0.13.4)
                child: FilterTabs<ServicesSection>(
                  options: {for (final s in sections) s: s.label},
                  value: _section,
                  onChanged: (s) => setState(() => _section = s),
                ),
              ),
            ),
          ),
          Expanded(
            child: switch (_section) {
              ServicesSection.board => ServiceBoardView(
                  key: ValueKey('board-${b.id}'),
                  business: b,
                  template: template,
                  onOpenAttendance: () => setState(() => _section = ServicesSection.employees),
                ),
              ServicesSection.employees => EmployeesView(
                  key: ValueKey('employees-${b.id}'),
                  business: b,
                  canEdit: _canConfigure,
                  onOpenCommissions: _canConfigure ? () => setState(() => _section = ServicesSection.commissions) : null,
                ),
              ServicesSection.history => HistoryView(key: ValueKey('history-${b.id}'), business: b, template: template),
              ServicesSection.commissions => CommissionsView(key: ValueKey('commissions-${b.id}'), business: b),
              ServicesSection.messages => MessagesView(key: ValueKey('messages-${b.id}'), business: b, template: template),
              ServicesSection.catalog => CatalogView(key: ValueKey('catalog-${b.id}'), business: b, template: template),
            },
          ),
        ],
      ),
    );
  }
}

/// Primera vez en Servicios: elegir el tipo de negocio. Stockealo da la plantilla
/// (nombres, servicios de ejemplo con precios) y después todo se puede ajustar en el catálogo.
class TemplatePicker extends StatefulWidget {
  final Business business;
  final bool canConfigure;

  const TemplatePicker({super.key, required this.business, required this.canConfigure});

  @override
  State<TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<TemplatePicker> {
  bool _saving = false;

  Future<void> _choose(ServiceTemplate t) async {
    setState(() => _saving = true);
    try {
      final n = await ServicesRepository.instance.setupTemplate(widget.business.id, t);
      if (!mounted) return;
      AppToast.showSuccess(
        context,
        n > 0
            ? 'Listo. Agregamos $n servicios de ejemplo: ajusta los precios en Catálogo y precios.'
            : 'Listo. Ya puedes usar Servicios.',
      );
      // updateBusiness avisa el cambio del negocio activo: la pestaña pasa al tablero
    } catch (e) {
      if (mounted) AppToast.showError(context, 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            Text('¿Qué tipo de negocio es?',
                style: TextStyle(fontSize: AppText.sizeHeading, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: AppSpace.xs),
            Text(
              widget.canConfigure
                  ? 'Te armamos la base con los nombres y servicios de ejemplo de tu tipo de negocio. '
                      'Después cambias precios y servicios en Catálogo y precios.'
                  : 'El dueño o un administrador debe elegir el tipo de negocio para empezar.',
              style: TextStyle(fontSize: AppText.sizeBody, height: 1.4, color: c.inkMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            for (final t in ServiceTemplate.all) ...[
              AppCard(
                onTap: widget.canConfigure && !_saving ? () => _choose(t) : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.label, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                          const SizedBox(height: 2),
                          Text(
                            [
                              'Cada trabajo es: ${t.unit.toLowerCase()}',
                              if (t.identifierLabel != null) 'por ${t.identifierLabel!.toLowerCase()}',
                              if (t.usesVehicleKinds) 'precio según ${t.vehicleKinds.map((k) => k.label.toLowerCase()).join(', ')}',
                              if (t.examples.isNotEmpty) '${t.examples.length} servicios de ejemplo',
                            ].join(' · '),
                            style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    if (widget.canConfigure) Icon(Icons.chevron_right_outlined, color: c.inkFaint),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          ],
        ),
      ),
    );
  }
}
