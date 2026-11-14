import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import '../core/design/status_pill.dart';

/// Secciones del panel, en grupos como el menú de la app (re-diseño 2026-11)
enum AdminSection {
  summary('Resumen', Icons.dashboard_outlined, 'Operación'),
  users('Usuarios', Icons.people_outline_outlined, 'Operación'),
  businesses('Negocios', Icons.store_mall_directory_outlined, 'Operación'),
  stores('Tiendas', Icons.storefront_outlined, 'Operación'),
  subscriptions('Suscripciones', Icons.workspace_premium_outlined, 'Ingresos'),
  payments('Pagos', Icons.payments_outlined, 'Ingresos'),
  codes('Códigos', Icons.confirmation_number_outlined, 'Ingresos'),
  feedback('Sugerencias y fallos', Icons.feedback_outlined, 'Soporte'),
  maintenance('Mantenimiento', Icons.construction_outlined, 'Soporte'),
  team('Equipo y registro', Icons.badge_outlined, 'Sistema'),
  config('Configuración', Icons.tune_outlined, 'Sistema');

  final String label;
  final IconData icon;
  final String group;

  const AdminSection(this.label, this.icon, this.group);
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
    final menu = _Menu(selected: _section, email: widget.email, showSearch: !wide, onSelect: (s) {
      _go(s);
      if (!wide) Navigator.of(context).maybePop();
    }, onSignOut: widget.onSignOut, onSearch: () {
      if (!wide) Navigator.of(context).maybePop();
      _search();
    });

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyK, control: true): _search},
      child: Focus(
        autofocus: true,
        child: Scaffold(
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
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(section: _section, onSearch: _search),
                      Expanded(child: KeyedSubtree(key: ValueKey(_section), child: _page())),
                    ],
                  ),
                ),
              ],
            )
          : KeyedSubtree(key: ValueKey(_section), child: _page()),
        ),
      ),
    );
  }
}

/// Barra de arriba (computador): dónde estás, el buscador con Ctrl K y tu rol
class _TopBar extends StatelessWidget {
  final AdminSection section;
  final VoidCallback onSearch;

  const _TopBar({required this.section, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
      decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        children: [
          Text(section.group, style: AppText.small(context)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            child: Icon(Icons.chevron_right_outlined, size: 16, color: c.inkFaint),
          ),
          Text(section.label, style: AppText.body(context, weight: FontWeight.w700)),
          const Spacer(),
          SizedBox(
            width: 320,
            child: Material(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: onSearch,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
                  child: Row(
                    children: [
                      Icon(Icons.search_outlined, size: 18, color: c.inkMuted),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text('Buscar correo, negocio, código o pago',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small(context)),
                      ),
                      const StatusPill('Ctrl K', tone: AppTone.neutral, compact: true),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          ValueListenableBuilder<String>(
            valueListenable: ProAdminService.instance.role,
            builder: (context, role, _) => StatusPill(
              switch (role) { 'OWNER' => 'Dueño', 'SUPPORT' => 'Soporte', _ => 'Solo lectura' },
              tone: role == 'OWNER' ? AppTone.accent : AppTone.neutral,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  final AdminSection selected;
  final String email;
  final ValueChanged<AdminSection> onSelect;
  final VoidCallback onSignOut;
  final VoidCallback onSearch;

  /// En el computador el buscador está en la barra de arriba (sin repetirlo)
  final bool showSearch;

  const _Menu({
    this.showSearch = true,
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(AppRadius.control)),
                child: Icon(Icons.admin_panel_settings_outlined, size: 20, color: c.onAccent),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stockealo', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyLarge(context, weight: FontWeight.w800)),
                    Text('Panel de administración', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Búsqueda global: correo, negocio, código Pro o referencia de pago
        if (showSearch) Padding(
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
        for (final s in AdminSection.values) ...[
          // Nombre del grupo antes de su primera sección
          if (s.index == 0 || AdminSection.values[s.index - 1].group != s.group)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xs),
              child: Text(s.group.toUpperCase(),
                  style: AppText.caption(context, weight: FontWeight.w700).copyWith(letterSpacing: 0.8)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 1),
            child: Material(
              color: s == selected ? c.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.tile),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.tile),
                onTap: () => onSelect(s),
                child: SizedBox(
                  height: 42,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md - 2),
                    child: Row(
                      children: [
                        Icon(s.icon, size: 20, color: s == selected ? c.onAccent : c.inkMuted),
                        const SizedBox(width: AppSpace.md - 2),
                        Expanded(
                          child: Text(s.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(context,
                                  weight: s == selected ? FontWeight.w600 : FontWeight.w500,
                                  color: s == selected ? c.onAccent : c.ink)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
