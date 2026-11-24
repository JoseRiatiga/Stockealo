import 'package:flutter/material.dart';
import '../../../business/data/branch_repository.dart';
import '../../../business/presentation/widgets/branch_picker_sheet.dart';
import '../../../../core/widgets/theme_mode_button.dart';

import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/business_identity.dart';
import '../../navigation/app_places.dart';
import '../../../../core/permissions/permissions.dart';

/// Contador de un lugar del menú («Stock 7», «Clientes y proveedores 2»)
typedef MenuBadge = ({int count, AppTone tone});

/// EL menú de Stockealo: el mismo en el computador (fijo a la izquierda, se puede
/// plegar a solo íconos) y en el celular (se abre con ☰). Arriba el negocio,
/// después los lugares agrupados como sigue el día, y abajo Ajustes y la persona.
class AppMenu extends StatefulWidget {
  final int selectedId;
  final ValueChanged<int> onSelect;
  final Business? business;
  final String userName;
  final String userRole;
  final bool services;
  final VoidCallback onSelectBusiness;
  final VoidCallback onLogout;

  /// En el celular va dentro del cajón lateral: sin botón de plegar
  final bool inDrawer;

  /// Pendientes por lugar (se muestran como contador al lado del nombre)
  final Map<int, MenuBadge> badges;

  const AppMenu({
    super.key,
    required this.selectedId,
    required this.onSelect,
    required this.business,
    required this.userName,
    required this.userRole,
    required this.services,
    required this.onSelectBusiness,
    required this.onLogout,
    this.inDrawer = false,
    this.badges = const {},
  });

  @override
  State<AppMenu> createState() => _AppMenuState();
}

class _AppMenuState extends State<AppMenu> {
  bool _collapsed = false;

  String get _roleLabel => Permissions.labelOf(widget.userRole);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final collapsed = _collapsed && !widget.inDrawer;
    final places = AppPlace.visible(role: widget.userRole, services: widget.services);

    final items = <Widget>[];
    String? group;
    for (final p in places) {
      if (p.group != group) {
        group = p.group;
        if (!collapsed) {
          items.add(SectionLabel(group, padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xs)));
        } else {
          items.add(const SizedBox(height: AppSpace.md));
        }
      }
      items.add(_MenuItem(
        place: p,
        selected: widget.selectedId == p.id,
        collapsed: collapsed,
        badge: widget.badges[p.id],
        onTap: () => widget.onSelect(p.id),
      ));
    }

    return AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.normal),
      curve: AppMotion.curve,
      // 272: «Clientes y proveedores» y «Salir» caben enteros (0.16.7, hallazgos 12 y 38)
      width: widget.inDrawer ? 304 : (collapsed ? 80 : 272),
      decoration: BoxDecoration(color: c.surface, border: widget.inDrawer ? null : Border(right: BorderSide(color: c.line))),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo y plegar (el cajón del celular se cierra tocando fuera o con la ✕)
            Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? AppSpace.md : AppSpace.lg, AppSpace.lg, AppSpace.sm, AppSpace.md),
              child: Row(
                mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  if (!collapsed) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.tile),
                      child: Image.asset('assets/icon/app_icon.png', width: 32, height: 32),
                    ),
                    const SizedBox(width: AppSpace.md - 2),
                    Expanded(child: Text('Stockealo', style: AppText.title(context, weight: FontWeight.w700))),
                  ],
                  // En el celular el botón de tema vive aquí (0.16.3), no en el encabezado
                  if (widget.inDrawer) const ThemeModeButton(size: 20),
                  if (widget.inDrawer)
                    IconButton(
                      tooltip: 'Cerrar menú',
                      icon: Icon(Icons.close_outlined, size: 20, color: c.inkMuted),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  else
                    IconButton(
                      tooltip: collapsed ? 'Mostrar el menú' : 'Plegar el menú',
                      icon: Icon(collapsed ? Icons.menu_open_outlined : Icons.menu_outlined, size: 20, color: c.inkMuted),
                      onPressed: () => setState(() => _collapsed = !_collapsed),
                    ),
                ],
              ),
            ),

            // Negocio o sede activa
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              // Con sedes (0.18.0) se elige la sede ahí mismo; «Otro negocio…» abre el de siempre
              child: ListenableBuilder(
                listenable: BranchRepository.instance,
                builder: (context, _) {
                  final branches = BranchRepository.instance;
                  // Con solo sedes cerradas, el dueño igual puede elegir «Todas las sedes»
                  final hasBranches = branches.openBranches.isNotEmpty || branches.canSwitch;
                  return _BusinessButton(
                    business: widget.business,
                    collapsed: collapsed,
                    branch: hasBranches
                        ? (branches.viewAll.value ? 'Todas las sedes' : branches.nameOf(BranchRepository.active))
                        : null,
                    onTap: hasBranches
                        ? () => BranchPickerSheet.show(context, onOtherBusiness: widget.onSelectBusiness)
                        : widget.onSelectBusiness,
                  );
                },
              ),
            ),

            // Lugares
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md),
                children: items,
              ),
            ),

            // Ajustes y la persona, separados de los lugares del día
            Divider(height: 1, color: c.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
              child: _MenuItem(
                place: AppPlace.settings,
                selected: widget.selectedId == AppPlace.ajustes,
                collapsed: collapsed,
                onTap: () => widget.onSelect(AppPlace.ajustes),
              ),
            ),
            Divider(height: AppSpace.lg, color: c.line),
            Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? AppSpace.sm : AppSpace.md, 0, AppSpace.sm, AppSpace.md),
              child: collapsed
                  ? IconButton(
                      tooltip: 'Cerrar sesión',
                      icon: Icon(Icons.logout_outlined, size: 20, color: c.danger),
                      onPressed: widget.onLogout,
                    )
                  : Row(
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: c.surfaceMuted,
                          child: Text(
                            _initials(widget.userName),
                            style: AppText.small(context, weight: FontWeight.w700, color: c.ink),
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm + 2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.userName,
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(context, weight: FontWeight.w600)),
                              Text(_roleLabel, style: AppText.caption(context)),
                            ],
                          ),
                        ),
                        // En rojo para que se distinga (0.16.1), en la misma fila para no
                        // hacer más alto el menú; pide confirmación antes de salir
                        const SizedBox(width: AppSpace.xs),
                        Tooltip(
                          message: 'Cerrar sesión',
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: c.danger,
                              backgroundColor: c.dangerSoft,
                              side: BorderSide(color: c.danger.withValues(alpha: 0.35)),
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm + 2),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: widget.onLogout,
                            icon: const Icon(Icons.logout_outlined, size: 17),
                            label: const Text('Salir'),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    return (parts.first[0] + (parts.length > 1 ? parts[1][0] : '')).toUpperCase();
  }
}

/// Negocio activo: abre el selector de negocios (y, con sedes, de sede)
class _BusinessButton extends StatelessWidget {
  final Business? business;
  final bool collapsed;
  final VoidCallback onTap;

  /// Sede elegida (0.18.0); null = el negocio no tiene sedes
  final String? branch;

  const _BusinessButton({required this.business, required this.collapsed, required this.onTap, this.branch});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final avatar = business != null
        ? BusinessAvatar(business: business!, size: 32)
        : Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.tile)),
            child: Icon(Icons.storefront_outlined, size: 18, color: c.inkMuted),
          );
    final radius = BorderRadius.circular(AppRadius.control);
    return Tooltip(
      message: collapsed ? (business?.name ?? 'Elegir negocio') : '',
      child: Semantics(
        button: true,
        label: 'Negocio: ${business?.name ?? 'ninguno'}${branch == null ? '' : ', sede $branch'}. Cambiar',
        excludeSemantics: true,
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(collapsed ? AppSpace.xs + 2 : AppSpace.sm + 2),
              child: collapsed
                  ? Center(child: avatar)
                  : Row(
                      children: [
                        avatar,
                        const SizedBox(width: AppSpace.sm + 2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Hasta dos renglones: el nombre del negocio se lee entero
                              Text(business?.name ?? 'Elegir negocio',
                                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(context, weight: FontWeight.w700)),
                              branch == null
                                  ? Text('Cambiar negocio', style: AppText.caption(context))
                                  : Row(children: [
                                      Icon(Icons.place_outlined, size: 13, color: c.accent),
                                      const SizedBox(width: 2),
                                      Flexible(
                                        child: Text(branch!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppText.caption(context, weight: FontWeight.w700, color: c.accent)),
                                      ),
                                    ]),
                            ],
                          ),
                        ),
                        Icon(Icons.unfold_more_outlined, size: 18, color: c.inkFaint),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un lugar del menú. El elegido va lleno con el color del negocio.
class _MenuItem extends StatelessWidget {
  final AppPlace place;
  final bool selected;
  final bool collapsed;
  final MenuBadge? badge;
  final VoidCallback onTap;

  const _MenuItem({required this.place, required this.selected, required this.collapsed, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onAccent : c.inkMuted;
    final radius = BorderRadius.circular(AppRadius.tile);
    final b = badge;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: collapsed ? place.label : '',
        child: Semantics(
          button: true,
          selected: selected,
          label: b != null && b.count > 0 ? '${place.label}, ${b.count} pendientes' : place.label,
          excludeSemantics: true,
          child: Material(
            color: selected ? c.accent : Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: SizedBox(
                height: 44,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : AppSpace.md - 2),
                  child: Row(
                    mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                    children: [
                      Icon(place.icon, size: 20, color: fg),
                      if (!collapsed) ...[
                        const SizedBox(width: AppSpace.md - 2),
                        Expanded(
                          child: Text(
                            place.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(context, weight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? c.onAccent : c.ink),
                          ),
                        ),
                        if (b != null && b.count > 0) StatusPill('${b.count}', tone: b.tone, compact: true),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
