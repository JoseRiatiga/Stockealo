import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/business_identity.dart';

/// Barra lateral de la versión de escritorio y web: logo, negocio activo,
/// secciones y usuario. Se puede contraer para dejar solo los íconos.
class AppSidebarPro extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final Business? activeBusiness;
  final String userName;
  final String userRole;
  final VoidCallback onSelectBusiness;
  final VoidCallback onLogout;

  const AppSidebarPro({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.activeBusiness,
    required this.userName,
    required this.userRole,
    required this.onSelectBusiness,
    required this.onLogout,
  });

  @override
  State<AppSidebarPro> createState() => _AppSidebarProState();
}

class _AppSidebarProState extends State<AppSidebarPro> {
  bool _isCollapsed = false;

  static const _items = [
    (icon: Icons.space_dashboard_outlined, selectedIcon: Icons.space_dashboard_rounded, label: 'Inicio'),
    (icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2_rounded, label: 'Inventario'),
    (icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale_rounded, label: 'Ventas'),
    (icon: Icons.settings_outlined, selectedIcon: Icons.settings_rounded, label: 'Ajustes'),
  ];

  String get _roleLabel => switch (widget.userRole) {
        'OWNER' => 'Dueño',
        'ADMIN' => 'Administrador',
        _ => 'Cajero',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final collapsed = _isCollapsed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: collapsed ? 80 : 248,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo y botón para contraer
            Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? AppSpace.md : AppSpace.lg, AppSpace.lg, AppSpace.sm, AppSpace.md),
              child: Row(
                mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  if (!collapsed) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset('assets/icon/app_icon.png', width: 34, height: 34),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Text(
                        'Stockealo',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: c.ink),
                      ),
                    ),
                  ],
                  IconButton(
                    tooltip: collapsed ? 'Mostrar menú' : 'Contraer menú',
                    icon: Icon(collapsed ? Icons.menu_open_rounded : Icons.menu_rounded, size: 20, color: c.inkMuted),
                    onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
                  ),
                ],
              ),
            ),

            // Negocio activo
            Padding(
              padding: EdgeInsets.symmetric(horizontal: collapsed ? AppSpace.md : AppSpace.md),
              child: _BusinessButton(
                business: widget.activeBusiness,
                collapsed: collapsed,
                onTap: widget.onSelectBusiness,
              ),
            ),
            const SizedBox(height: AppSpace.lg),

            // Secciones
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                children: [
                  for (var i = 0; i < _items.length; i++)
                    _NavItem(
                      icon: widget.selectedIndex == i ? _items[i].selectedIcon : _items[i].icon,
                      label: _items[i].label,
                      selected: widget.selectedIndex == i,
                      collapsed: collapsed,
                      onTap: () => widget.onItemSelected(i),
                    ),
                ],
              ),
            ),

            // Usuario
            Divider(height: 1, color: c.line),
            Padding(
              padding: EdgeInsets.all(collapsed ? AppSpace.sm : AppSpace.md),
              child: collapsed
                  ? IconButton(
                      tooltip: 'Cerrar sesión',
                      icon: Icon(Icons.logout_rounded, size: 20, color: c.inkMuted),
                      onPressed: widget.onLogout,
                    )
                  : Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: c.accent.withOpacity(0.14),
                          child: Text(
                            widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : 'U',
                            // En oscuro el acento se aclara para que la inicial se lea
                            style: TextStyle(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Color.lerp(c.accent, Colors.white, 0.55)
                                  : c.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm + 2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.ink),
                              ),
                              Text(_roleLabel, style: TextStyle(fontSize: 12, color: c.inkMuted)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar sesión',
                          icon: Icon(Icons.logout_rounded, size: 19, color: c.inkMuted),
                          onPressed: widget.onLogout,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Negocio activo: abre el selector de negocios
class _BusinessButton extends StatelessWidget {
  final Business? business;
  final bool collapsed;
  final VoidCallback onTap;

  const _BusinessButton({required this.business, required this.collapsed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final avatar = business != null
        ? BusinessAvatar(business: business!, size: 34)
        : Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.storefront_outlined, size: 18, color: c.inkMuted),
          );
    final radius = BorderRadius.circular(AppRadius.control);
    return Tooltip(
      message: collapsed ? (business?.name ?? 'Elegir negocio') : '',
      child: Semantics(
        button: true,
        label: 'Negocio: ${business?.name ?? 'ninguno'}. Cambiar',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: EdgeInsets.all(collapsed ? AppSpace.xs : AppSpace.sm),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: radius,
              border: Border.all(color: c.line),
            ),
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
                            Text(
                              business?.name ?? 'Elegir negocio',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.ink),
                            ),
                            Text('Cambiar negocio', style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
                          ],
                        ),
                      ),
                      Icon(Icons.unfold_more_rounded, size: 18, color: c.inkFaint),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Sección del menú; la activa va rellena con el color de acento, como la
/// pestaña activa del celular
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onAccent : c.inkMuted;
    final radius = BorderRadius.circular(AppRadius.control);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Tooltip(
        message: collapsed ? label : '',
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 44,
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : AppSpace.md),
              decoration: BoxDecoration(color: selected ? c.accent : Colors.transparent, borderRadius: radius),
              child: Row(
                mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  Icon(icon, size: 21, color: fg),
                  if (!collapsed) ...[
                    const SizedBox(width: AppSpace.md),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? c.onAccent : c.ink,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
