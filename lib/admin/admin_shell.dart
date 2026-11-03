import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import 'admin_codes_screen.dart';
import 'admin_config_page.dart';
import 'admin_payments_page.dart';
import 'admin_stores_page.dart';
import 'admin_subscriptions_page.dart';
import 'admin_summary_page.dart';
import 'admin_users_page.dart';

/// Secciones del panel
enum AdminSection {
  summary('Resumen', Icons.dashboard_outlined),
  users('Usuarios', Icons.people_outline_rounded),
  stores('Tiendas', Icons.storefront_outlined),
  subscriptions('Suscripciones', Icons.workspace_premium_outlined),
  payments('Pagos', Icons.payments_outlined),
  codes('Códigos', Icons.confirmation_number_outlined),
  config('Configuración', Icons.tune_rounded);

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
        AdminSection.stores => const AdminStoresPage(),
        AdminSection.subscriptions => const AdminSubscriptionsPage(),
        AdminSection.payments => const AdminPaymentsPage(),
        AdminSection.codes => const AdminCodesPage(),
        AdminSection.config => const AdminConfigPage(),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.of(context).size.width >= 900;
    final menu = _Menu(selected: _section, email: widget.email, onSelect: (s) {
      _go(s);
      if (!wide) Navigator.of(context).maybePop();
    }, onSignOut: widget.onSignOut);

    return Scaffold(
      backgroundColor: c.paper,
      appBar: wide
          ? null
          : AppBar(
              title: Text('Stockealo · ${_section.label}'),
              backgroundColor: c.paper,
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

  const _Menu({required this.selected, required this.email, required this.onSelect, required this.onSignOut});

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
              Text('Administrador', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
            ],
          ),
        ),
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
        const Spacer(),
        Divider(height: 1, color: c.line),
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(email, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.inkMuted)),
              const SizedBox(height: AppSpace.sm),
              OutlinedButton.icon(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
