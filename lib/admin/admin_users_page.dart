import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_widgets.dart';

/// Cuentas registradas: correo, nombre, celular, negocios y si tienen Pro
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  List<AdminUser> _users = const [];
  String _search = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await ProAdminService.instance.listUsers(search: _search);
      if (mounted) setState(() => _users = users);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AdminLoadState(
      loading: _loading,
      error: _error,
      empty: _users.isEmpty,
      emptyText: _search.isEmpty ? 'Todavía no hay cuentas.' : 'No hay cuentas con "$_search".',
      onRetry: _load,
    );
    return AdminPage(
      title: 'Usuarios',
      subtitle: _loading ? null : '${_users.length} cuentas${_search.isEmpty ? '' : ' encontradas'}',
      onRefresh: _load,
      children: [
        AdminSearchField(
          hint: 'Buscar por correo, nombre o celular',
          onSubmitted: (v) {
            _search = v;
            _load();
          },
        ),
        if (state.blocking)
          state
        else
          for (final u in _users)
            AdminCard(
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: c.surfaceMuted,
                    child: Text(
                      (u.name?.trim().isNotEmpty == true ? u.name!.trim() : u.email)[0].toUpperCase(),
                      style: TextStyle(fontWeight: FontWeight.w700, color: c.inkMuted),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(u.name?.trim().isNotEmpty == true ? u.name! : u.email,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                            ),
                            if (u.pro) ...[const SizedBox(width: AppSpace.sm), const AdminBadge('Pro', tone: AdminTone.good)],
                          ],
                        ),
                        Text(
                          [u.email, if (u.phone?.isNotEmpty == true) u.phone!].join(' · '),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.inkMuted),
                        ),
                        Text(
                          'Registro ${adminDate(u.createdAt)} · Último ingreso ${adminDate(u.lastSignInAt)} · '
                          '${u.businesses} ${u.businesses == 1 ? 'negocio' : 'negocios'}',
                          style: TextStyle(fontSize: 12, color: c.inkFaint),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar correo',
                    onPressed: () => adminCopy(context, u.email, 'Correo'),
                    icon: Icon(Icons.copy_rounded, size: 18, color: c.inkMuted),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
