import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../core/utils/clock_text.dart';
import '../core/widgets/app_toast.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_widgets.dart';
import '../core/design/app_dialog.dart';

/// Quién administra el panel (con su rol) y qué se ha hecho desde él
class AdminTeamPage extends StatefulWidget {
  const AdminTeamPage({super.key});

  @override
  State<AdminTeamPage> createState() => _AdminTeamPageState();
}

class _AdminTeamPageState extends State<AdminTeamPage> {
  List<Map<String, dynamic>> _admins = const [];
  List<Map<String, dynamic>> _actions = const [];

  /// Nombre de cada negocio por su id, para que el registro diga a quién (re-diseño)
  Map<String, String> _businessNames = const {};
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
      // Sin la lista de negocios el registro sigue saliendo, solo sin los nombres
      final names = <String, String>{};
      try {
        for (final b in await admin.findBusinesses('')) {
          names[b.id] = b.name;
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _admins = r[0];
        _actions = r[1];
        _businessNames = names;
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
                              style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted),
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
              Text('Registro de acciones', style: AppText.heading(context)),
              Text('Las últimas 100 cosas que se hicieron desde el panel', style: AppText.small(context, color: c.inkMuted)),
              const SizedBox(height: AppSpace.md),
              if (_actions.isEmpty)
                const AdminEmpty(
                  icon: Icons.history_outlined,
                  title: 'Todavía no hay acciones registradas',
                  detail: 'Cada vez que alguien da Pro, crea códigos o cambia un ajuste, queda aquí.',
                )
              else
                AdminCard(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, a) in _actions.indexed) ...[
                        if (_dayChanged(i))
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? AppSpace.xs : AppSpace.md, bottom: AppSpace.xs),
                            child: Text(adminDayTitle(_when(a)!), style: AppText.caption(context, color: c.inkMuted)),
                          ),
                        _actionRow(c, a),
                      ],
                    ],
                  ),
                ),
            ],
    );
  }

  DateTime? _when(Map<String, dynamic> a) => DateTime.tryParse('${a['created_at']}')?.toLocal();

  /// La acción [i] es la primera de su día (para poner «Hoy», «Ayer»…)
  bool _dayChanged(int i) {
    final d = _when(_actions[i]);
    if (d == null) return false;
    if (i == 0) return true;
    final prev = _when(_actions[i - 1]);
    return prev == null || prev.year != d.year || prev.month != d.month || prev.day != d.day;
  }

  Widget _actionRow(StockealoColors c, Map<String, dynamic> a) {
    final when = _when(a);
    final admin = '${a['admin_email'] ?? ''}'.split('@').first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(actionIcon('${a['action']}'), size: 18, color: c.inkMuted),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(actionLabel(a, businesses: _businessNames), style: AppText.small(context, color: c.ink)),
                Text('$admin · ${when == null ? '' : clockText(when)}', style: AppText.caption(context, color: c.inkFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Ícono de cada tipo de acción
  static IconData actionIcon(String action) => switch (action) {
        'grant_pro' || 'end_subscription' => Icons.workspace_premium_outlined,
        'grant_branch_slots' => Icons.place_outlined,
        'create_codes' || 'disable_code' => Icons.confirmation_number_outlined,
        'set_plan' || 'set_setting' => Icons.tune_outlined,
        'set_admin' => Icons.badge_outlined,
        'add_note' || 'delete_note' || 'set_contacted' => Icons.sticky_note_2_outlined,
        'set_maintenance' || 'end_maintenance' => Icons.construction_outlined,
        'feedback_update' => Icons.forum_outlined,
        _ => Icons.history_outlined,
      };

  /// «Dio Pro 1 año a Miselanea», «Activó mantenimiento nivel 2»… [businesses]: nombre
  /// de cada negocio por id; sin él dice «a un negocio»
  static String actionLabel(Map<String, dynamic> a, {Map<String, String> businesses = const {}}) {
    final d = Map<String, dynamic>.from((a['detail'] as Map?) ?? const {});
    final who = businesses['${d['business_id']}'];
    final to = who == null ? 'a un negocio' : 'a $who';
    String length(Object? days) => switch (days) {
          null => 'permanente',
          7 => '1 semana',
          30 || 31 => '1 mes',
          90 => '3 meses',
          365 || 366 => '1 año',
          _ => '$days días',
        };
    String plan(Object? kind) => kind == 'services' ? 'Pro Servicios' : (kind == 'global' ? 'Pro Global' : 'Pro');
    return switch ('${a['action']}') {
      'grant_pro' => 'Dio ${plan(d['kind'])} ${length(d['days'])} $to',
      'grant_branch_slots' =>
        'Dio ${d['slots'] ?? 1} ${d['slots'] == 1 || d['slots'] == null ? 'cupo' : 'cupos'} de sede $to (${length(d['days'])})',
      'feedback_update' => switch (d['status']) {
          'RESUELTO' => 'Marcó como resuelto un mensaje de soporte',
          'DESCARTADO' => 'Descartó un mensaje de soporte',
          'REVISION' => 'Puso en revisión un mensaje de soporte',
          _ => 'Cambió el estado de un mensaje de soporte',
        },
      'end_subscription' => 'Terminó una suscripción',
      'create_codes' =>
        'Creó ${d['count'] ?? 1} ${d['count'] == 1 || d['count'] == null ? 'código' : 'códigos'} de ${plan(d['kind'])} (${length(d['days'])})',
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
  static String label(Map<String, dynamic> action, {Map<String, String> businesses = const {}}) =>
      _AdminTeamPageState.actionLabel(action, businesses: businesses);
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
    return AppDialog(
      title: editing ? 'Cambiar rol' : 'Agregar al panel',
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
            RadioGroup<String>(
              groupValue: _role,
              onChanged: (v) => setState(() => _role = v ?? _role),
              child: Column(
                children: [
                  for (final e in _AdminTeamPageState.roles.entries)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: e.key,
                      title: Text(e.value.$1),
                      subtitle: Text(e.value.$2),
                    ),
                ],
              ),
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
