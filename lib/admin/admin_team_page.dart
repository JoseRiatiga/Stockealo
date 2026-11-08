import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../core/widgets/app_toast.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_widgets.dart';

/// Quién administra el panel (con su rol) y qué se ha hecho desde él
class AdminTeamPage extends StatefulWidget {
  const AdminTeamPage({super.key});

  @override
  State<AdminTeamPage> createState() => _AdminTeamPageState();
}

class _AdminTeamPageState extends State<AdminTeamPage> {
  List<Map<String, dynamic>> _admins = const [];
  List<Map<String, dynamic>> _actions = const [];
  bool _loading = true;
  String? _error;

  static const roles = {
    'OWNER': ('Dueño', 'Todo: Pro, precios, códigos, mantenimiento y equipo'),
    'SUPPORT': ('Soporte', 'Ve fichas, escribe notas y marca contactados. No da Pro ni cambia precios'),
    'VIEWER': ('Solo lectura', 'Ve el panel sin cambiar nada'),
  };

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
      final admin = ProAdminService.instance;
      final r = await Future.wait([admin.listAdmins(), admin.listActions()]);
      if (!mounted) return;
      setState(() {
        _admins = r[0];
        _actions = r[1];
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit({String? email, String? role}) async {
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => _AdminDialog(email: email, role: role ?? 'SUPPORT'),
    );
    if (result == null) return;
    try {
      await ProAdminService.instance.setAdmin(result.$1, result.$2);
      if (!mounted) return;
      AppToast.show(context, message: result.$2 == null ? 'Se quitó a ${result.$1}' : 'Guardado', type: ToastType.success);
      _load();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final owner = ProAdminService.instance.isOwner;
    final state = AdminLoadState(loading: _loading, error: _error, empty: _admins.isEmpty, emptyText: '', onRetry: _load);
    return AdminPage(
      title: 'Equipo y registro',
      subtitle: 'Quién administra Stockealo y qué se ha hecho desde el panel',
      onRefresh: _load,
      actions: [
        if (owner)
          FilledButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Agregar'),
          ),
      ],
      children: state.blocking
          ? [state]
          : [
              for (final a in _admins)
                AdminCard(
                  child: Row(
                    children: [
                      Icon(Icons.badge_outlined, color: c.inkMuted),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${a['email']}', style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                            Text(
                              '${roles[a['role']]?.$1 ?? a['role']} · ${roles[a['role']]?.$2 ?? ''}',
                              style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                            ),
                          ],
                        ),
                      ),
                      if (owner)
                        TextButton(
                          onPressed: () => _edit(email: '${a['email']}', role: '${a['role']}'),
                          child: const Text('Cambiar'),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpace.xl),
              Text('Registro de acciones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
              Text('Las últimas 100 cosas que se hicieron desde el panel', style: TextStyle(fontSize: 13, color: c.inkMuted)),
              const SizedBox(height: AppSpace.md),
              if (_actions.isEmpty)
                Text('Todavía no hay acciones registradas.', style: TextStyle(color: c.inkFaint))
              else
                AdminCard(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
                  child: Column(
                    children: [
                      for (final a in _actions)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(actionLabel(a)),
                          subtitle: Text('${a['admin_email']} · ${adminDateTime(DateTime.tryParse('${a['created_at']}')?.toLocal())}'),
                        ),
                    ],
                  ),
                ),
            ],
    );
  }

  /// "Dio Pro (30 días) a un negocio", "Activó mantenimiento nivel 2"…
  static String actionLabel(Map<String, dynamic> a) {
    final d = Map<String, dynamic>.from((a['detail'] as Map?) ?? const {});
    return switch ('${a['action']}') {
      'grant_pro' => 'Dio Pro ${d['days'] == null ? 'permanente' : '(${d['days']} días)'} a un negocio',
      'end_subscription' => 'Terminó una suscripción',
      'create_codes' => 'Creó ${d['count'] ?? ''} código(s) Pro',
      'disable_code' => 'Desactivó el código ${d['code'] ?? ''}',
      'set_plan' => 'Cambió el plan ${d['id'] ?? ''}',
      'set_setting' => 'Cambió el ajuste "${d['key'] ?? ''}"',
      'set_admin' => d['role'] == null ? 'Quitó a ${d['email']} del panel' : 'Puso a ${d['email']} como ${roles[d['role']]?.$1 ?? d['role']}',
      'add_note' => 'Escribió una nota sobre ${d['email'] ?? ''}',
      'delete_note' => 'Borró una nota',
      'set_contacted' => d['contacted'] == true ? 'Marcó como contactado a ${d['email']}' : 'Quitó el contactado de ${d['email']}',
      'set_maintenance' => 'Programó mantenimiento nivel ${d['level'] ?? ''}',
      'end_maintenance' => 'Terminó el mantenimiento',
      _ => '${a['action']}',
    };
  }
}

/// Textos del registro de acciones, también para pruebas
class AdminTeamPageLabels {
  static String label(Map<String, dynamic> action) => _AdminTeamPageState.actionLabel(action);
}

class _AdminDialog extends StatefulWidget {
  final String? email;
  final String role;
  const _AdminDialog({this.email, required this.role});

  @override
  State<_AdminDialog> createState() => _AdminDialogState();
}

class _AdminDialogState extends State<_AdminDialog> {
  late final _email = TextEditingController(text: widget.email ?? '');
  late String _role = widget.role;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.email != null;
    return AlertDialog(
      title: Text(editing ? 'Cambiar rol' : 'Agregar al panel'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _email,
              enabled: !editing,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo de su cuenta de Stockealo'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpace.md),
            for (final e in _AdminTeamPageState.roles.entries)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: e.key,
                groupValue: _role,
                onChanged: (v) => setState(() => _role = v ?? _role),
                title: Text(e.value.$1),
                subtitle: Text(e.value.$2),
              ),
          ],
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            onPressed: () => Navigator.pop(context, (_email.text.trim(), null)),
            style: TextButton.styleFrom(foregroundColor: context.colors.danger),
            child: const Text('Quitar del panel'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _email.text.trim().contains('@') ? () => Navigator.pop(context, (_email.text.trim(), _role)) : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
