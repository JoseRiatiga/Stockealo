import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import 'admin_feedback_page.dart';
import 'admin_codes_screen.dart';
import 'admin_config_page.dart';
import 'admin_payments_page.dart';
import 'admin_stores_page.dart';
import 'admin_subscriptions_page.dart';
import 'admin_summary_page.dart';
import 'admin_users_page.dart';
import 'admin_maintenance_page.dart';
import 'admin_search_dialog.dart';
import 'admin_team_page.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_businesses_page.dart';

/// Secciones del panel
enum AdminSection {
  summary('Resumen', Icons.dashboard_outlined),
  users('Usuarios', Icons.people_outline_outlined),
  businesses('Negocios', Icons.store_mall_directory_outlined),
  stores('Tiendas', Icons.storefront_outlined),
  subscriptions('Suscripciones', Icons.workspace_premium_outlined),
  payments('Pagos', Icons.payments_outlined),
  codes('Códigos', Icons.confirmation_number_outlined),
  feedback('Sugerencias y fallos', Icons.feedback_outlined),
  maintenance('Mantenimiento', Icons.construction_outlined),
  team('Equipo y registro', Icons.badge_outlined),
  config('Configuración', Icons.tune_outlined);

  final String label;
  final IconData icon;

  const AdminSection(this.label, this.icon);
}

/// Marco del panel: menú lateral (o desplegable en pantallas angostas) y sección activa
class AdminShell extends StatefulWidget {
  final String email;
  final VoidCallback onSignOut;

  const AdminShell({super.key, required this.email, required this.onSignOut});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  AdminSection _section = AdminSection.summary;

  void _go(AdminSection s) => setState(() => _section = s);

  Widget _page() => switch (_section) {
        AdminSection.summary => AdminSummaryPage(onOpen: _go),
        AdminSection.users => const AdminUsersPage(),
        AdminSection.businesses => const AdminBusinessesPage(),
        AdminSection.stores => const AdminStoresPage(),
        AdminSection.subscriptions => const AdminSubscriptionsPage(),
        AdminSection.payments => const AdminPaymentsPage(),
        AdminSection.codes => const AdminCodesPage(),
        AdminSection.feedback => const AdminFeedbackPage(),
        AdminSection.maintenance => const AdminMaintenancePage(),
        AdminSection.team => const AdminTeamPage(),
        AdminSection.config => const AdminConfigPage(),
      };

  @override
  void initState() {
    super.initState();
    // El rol decide qué botones se ven (el servidor igual lo hace cumplir)
    ProAdminService.instance.loadMe();
  }

  void _search() => AdminSearchDialog.show(context, onOpenSection: _go);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.of(context).size.width >= 900;
    final menu = _Menu(selected: _section, email: widget.email, onSelect: (s) {
      _go(s);
      if (!wide) Navigator.of(context).maybePop();
    }, onSignOut: widget.onSignOut, onSearch: () {
      if (!wide) Navigator.of(context).maybePop();
      _search();
    });

    return Scaffold(
      backgroundColor: c.paper,
      appBar: wide
          ? null
          : AppBar(
              title: Text('Stockealo · ${_section.label}'),
              backgroundColor: c.paper,
              actions: [
                IconButton(tooltip: 'Buscar', onPressed: _search, icon: const Icon(Icons.search_outlined)),
              ],
            ),
      drawer: wide ? null : Drawer(backgroundColor: c.surface, child: SafeArea(child: menu)),
      body: wide
          ? Row(
              children: [
                Container(
                  width: 248,
                  decoration: BoxDecoration(color: c.surface, border: Border(right: BorderSide(color: c.line))),
                  child: SafeArea(child: menu),
                ),
                Expanded(child: KeyedSubtree(key: ValueKey(_section), child: _page())),
              ],
            )
          : KeyedSubtree(key: ValueKey(_section), child: _page()),
    );
  }
}

class _Menu extends StatelessWidget {
  final AdminSection selected;
  final String email;
  final ValueChanged<AdminSection> onSelect;
  final VoidCallback onSignOut;
  final VoidCallback onSearch;

  const _Menu({
    required this.selected,
    required this.email,
    required this.onSelect,
    required this.onSignOut,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xl, AppSpace.lg, AppSpace.lg),
          child: Row(
            children: [
              Icon(Icons.admin_panel_settings_outlined, color: c.accent),
              const SizedBox(width: AppSpace.sm),
              Text('Administrador', style: TextStyle(fontSize: AppText.sizeTitle, fontWeight: FontWeight.w700, color: c.ink)),
            ],
          ),
        ),
        // Búsqueda global: correo, negocio, código Pro o referencia de pago
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.sm, 0, AppSpace.sm, AppSpace.sm),
          child: OutlinedButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.search_outlined, size: 18),
            label: const Align(alignment: Alignment.centerLeft, child: Text('Buscar…')),
            style: OutlinedButton.styleFrom(foregroundColor: c.inkMuted, alignment: Alignment.centerLeft),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
        for (final s in AdminSection.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
            child: Material(
              color: s == selected ? c.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: () => onSelect(s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
                  child: Row(
                    children: [
                      Icon(s.icon, size: 20, color: s == selected ? c.onAccent : c.inkMuted),
                      const SizedBox(width: AppSpace.md),
                      Text(s.label,
                          style: TextStyle(
                            fontWeight: s == selected ? FontWeight.w600 : FontWeight.w500,
                            color: s == selected ? c.onAccent : c.ink,
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ),
            ],
          ),
        ),
        Divider(height: 1, color: c.line),
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(email, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted)),
              ValueListenableBuilder<String>(
                valueListenable: ProAdminService.instance.role,
                builder: (context, role, _) => Text(
                  switch (role) { 'OWNER' => 'Dueño', 'SUPPORT' => 'Soporte', _ => 'Solo lectura' },
                  style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w600, color: c.inkFaint),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              OutlinedButton.icon(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout_outlined, size: 18),
                label: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
