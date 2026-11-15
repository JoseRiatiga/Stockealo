import 'package:flutter/material.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/filter_tabs.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../pro/data/pro_service.dart';
import '../../data/roles_repository.dart';
import '../../models/business_role.dart';
import '../../../../core/design/status_pill.dart';
import 'package:flutter/services.dart';

/// Ajustes › Equipo › Roles y permisos (0.15.0, etapa 2 de `docs/plan-roles.md`).
///
/// En el computador, una matriz: un rol por columna y los permisos por grupo, con
/// interruptores. En el celular, un rol a la vez. El Dueño tiene todo y no se cambia.
/// Solo el dueño cambia los interruptores; los demás ven la pantalla para leer.
class RolesScreen extends StatefulWidget {
  final Business business;

  /// Solo el dueño crea y cambia roles
  final bool canEdit;

  const RolesScreen({super.key, required this.business, required this.canEdit});

  static Future<void> open(BuildContext context, {required Business business, required bool canEdit}) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => RolesScreen(business: business, canEdit: canEdit)));

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

/// Una columna: el Dueño, el Administrador, el Cajero o un rol propio
class _Col {
  final String key;
  final String name;
  final IconData icon;
  final bool locked;
  final BusinessRole? role;
  const _Col({required this.key, required this.name, required this.icon, this.locked = false, this.role});
  bool get custom => role != null && !role!.isBuiltin;
}

class _RolesScreenState extends State<RolesScreen> {
  final _repo = RolesRepository.instance;
  List<_Col> _cols = const [];
  final Map<String, Set<Perm>> _orig = {};
  final Map<String, Set<Perm>> _draft = {};

  /// Límites con números (Pro): lo guardado y lo que se está cambiando
  final Map<String, Map<RoleLimit, double>> _origLimits = {};
  final Map<String, Map<RoleLimit, double>> _draftLimits = {};
  final Map<String, TextEditingController> _limitFields = {};

  bool get _pro => ProService.instance.status.value.active;
  String _selected = Permissions.cashier;
  bool _loading = true;
  bool _saving = false;

  /// Línea de ayuda de lo último que cambió solo (dependencias)
  String? _note;

  String get _bizId => widget.business.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final roles = await _repo.list(_bizId);
    BusinessRole? builtin(String code) => roles.where((r) => r.builtin == code).firstOrNull;
    final cols = <_Col>[
      const _Col(key: Permissions.owner, name: 'Dueño', icon: Icons.workspace_premium_outlined, locked: true),
      _Col(key: Permissions.admin, name: 'Administrador', icon: Icons.admin_panel_settings_outlined, role: builtin(Permissions.admin)),
      _Col(key: Permissions.cashier, name: 'Cajero', icon: Icons.point_of_sale_outlined, role: builtin(Permissions.cashier)),
      for (final r in roles.where((r) => !r.isBuiltin))
        _Col(key: r.id, name: r.name, icon: _iconOf(r.templateId), role: r),
    ];
    _orig
      ..clear()
      ..addAll({
        for (final c in cols)
          c.key: c.locked
              ? Perm.values.toSet()
              : (c.role?.perms ?? Permissions.factoryDefaults(c.key)),
      });
    _draft
      ..clear()
      ..addAll({for (final e in _orig.entries) e.key: {...e.value}});
    _origLimits
      ..clear()
      ..addAll({for (final c in cols) if (!c.locked) c.key: {...?c.role?.limits}});
    _draftLimits
      ..clear()
      ..addAll({for (final e in _origLimits.entries) e.key: {...e.value}});
    for (final f in _limitFields.values) {
      f.dispose();
    }
    _limitFields
      ..clear()
      ..addAll({
        for (final e in _origLimits.entries)
          for (final l in RoleLimit.values)
            '${e.key}|${l.name}': TextEditingController(text: e.value[l] == null ? '' : e.value[l]!.round().toString()),
      });
    if (!mounted) return;
    setState(() {
      _cols = cols;
      if (!cols.any((c) => c.key == _selected)) _selected = Permissions.cashier;
      _loading = false;
    });
  }

  static IconData _iconOf(String? templateId) =>
      Permissions.templates.where((t) => t.id == templateId).firstOrNull?.icon ?? Icons.badge_outlined;

  bool _changed(String key, Perm p) => _draft[key]!.contains(p) != _orig[key]!.contains(p);

  bool _limitChanged(String key, RoleLimit l) => _draftLimits[key]?[l] != _origLimits[key]?[l];

  int get _changes => [
        for (final c in _cols) ...[
          for (final p in Perm.values)
            if (_changed(c.key, p)) 1,
          if (!c.locked)
            for (final l in RoleLimit.values)
              if (_limitChanged(c.key, l)) 1,
        ],
      ].length;

  @override
  void dispose() {
    for (final f in _limitFields.values) {
      f.dispose();
    }
    super.dispose();
  }

  int get _active => _draft.values.fold(0, (t, s) => t + s.length);

  void _toggle(_Col col, Perm p) {
    if (col.locked || !widget.canEdit) return;
    setState(() {
      final set = _draft[col.key]!;
      if (set.contains(p)) {
        // Apagar: se apagan también los que lo necesitan
        final dependents = Permissions.dependentsOf(p).where(set.contains).toList();
        set
          ..remove(p)
          ..removeAll(dependents);
        _note = dependents.isEmpty ? null : 'También se apagó: ${dependents.map((d) => d.label).join(', ')}';
      } else {
        // Encender: se encienden también los que necesita
        final needed = Permissions.withDependencies({p}).difference(set)..remove(p);
        set.addAll({p, ...needed});
        _note = needed.isEmpty ? null : 'También se encendió: ${needed.map((d) => d.label).join(', ')}';
      }
    });
  }

  void _toggleAll(_Col col) {
    if (col.locked || !widget.canEdit) return;
    setState(() {
      final set = _draft[col.key]!;
      if (set.length == Perm.values.length) {
        set.clear();
      } else {
        set.addAll(Perm.values);
      }
      _note = null;
    });
  }

  void _discard() => setState(() {
        for (final e in _orig.entries) {
          _draft[e.key] = {...e.value};
        }
        for (final e in _origLimits.entries) {
          _draftLimits[e.key] = {...e.value};
          for (final l in RoleLimit.values) {
            _limitFields['${e.key}|${l.name}']?.text = e.value[l] == null ? '' : e.value[l]!.round().toString();
          }
        }
        _note = null;
      });

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      for (final col in _cols) {
        if (col.locked) continue;
        final before = _orig[col.key]!;
        final after = _draft[col.key]!;
        final limits = {..._draftLimits[col.key]!};
        final permsSame = before.length == after.length && before.containsAll(after);
        final limitsSame = RoleLimit.values.every((l) => !_limitChanged(col.key, l));
        if (permsSame && limitsSame) continue;
        final summary = [
          if (!permsSame) RolesRepository.changeSummary(col.name, before, after),
          if (!limitsSame) 'Cambió los límites de ${col.name}: ${RolesRepository.limitsSummary(limits)}',
        ].join('. ');
        if (col.custom) {
          await _repo.save(col.role!.copyWith(perms: {...after}, limits: limits), summary: summary);
        } else {
          await _repo.save(_repo.builtinWith(_bizId, col.key, {...after}, limits: limits), summary: summary);
        }
      }
      final n = _changes;
      await _load();
      if (mounted) AppToast.showSuccess(context, '$n ${n == 1 ? 'cambio guardado' : 'cambios guardados'}. Queda en Actividad del equipo.');
    } catch (e) {
      if (mounted) AppToast.showError(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _create() async {
    final customs = _cols.where((c) => c.custom).length;
    if (customs >= RolesRepository.freeCustomLimit && !ProService.instance.status.value.active) {
      AppToast.showWarning(context,
          'En el plan gratis puedes tener ${RolesRepository.freeCustomLimit} rol propio. Con Stockealo Pro, sin límite.');
      return;
    }
    if (_changes > 0) {
      AppToast.showWarning(context, 'Primero guarda o descarta los cambios.');
      return;
    }
    final name = TextEditingController();
    String template = Permissions.templates.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final c = ctx.colors;
          return AppDialog(
            icon: Icons.badge_outlined,
            title: 'Crear rol',
            subtitle: 'Parte de una plantilla y después cambia lo que haga falta',
            maxWidth: 460,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RadioGroup<String>(
                  groupValue: template,
                  onChanged: (v) => setD(() => template = v ?? ''),
                  child: Column(
                    children: [
                      for (final t in [...Permissions.templates, null])
                        RadioListTile<String>(
                          value: t?.id ?? '',
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          secondary: Icon(t?.icon ?? Icons.add_outlined, color: c.inkMuted),
                          title: Text(t?.name ?? 'Desde cero', style: AppText.body(ctx, weight: FontWeight.w600)),
                          subtitle: Text(t == null ? 'Sin permisos: los eliges tú' : '${t.forWho} · ${t.perms.length} permisos',
                              style: AppText.caption(ctx)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: name,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nombre del rol (opcional)', hintText: 'Si lo dejas vacío, se usa el de la plantilla'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(
                // Sin nombre se usa el de la plantilla
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Crear'),
              ),
            ],
          );
        },
      ),
    );
    final typed = name.text.trim();
    name.dispose();
    if (ok != true || !mounted) return;
    final t = Permissions.templates.where((x) => x.id == template).firstOrNull;
    final text = typed.isNotEmpty ? typed : (t?.name ?? 'Rol propio');
    final role = _repo.newCustom(_bizId, name: text, perms: t?.perms ?? const {}, templateId: t?.id);
    await _repo.save(role, summary: 'Creó el rol ${role.name}${t == null ? '' : ' (desde la plantilla ${t.name})'}');
    _selected = role.id;
    await _load();
    if (mounted) AppToast.showSuccess(context, 'Rol ${role.name} creado. Ahora asígnaselo a alguien en Equipo.');
  }

  Future<void> _delete(_Col col) async {
    final ok = await AppDialog.confirm(
      context: context,
      title: 'Borrar el rol ${col.name}',
      message: 'Quienes lo tienen vuelven a su rol anterior (Administrador o Cajero). Queda en Actividad del equipo.',
      confirmText: 'Borrar',
      destructive: true,
    );
    if (!ok) return;
    await _repo.delete(col.role!);
    await _load();
  }

  /// «Ver como»: la app como la vería este rol, hasta tocar «Salir»
  void _viewAs(_Col col) {
    if (_changes > 0) {
      AppToast.showWarning(context, 'Primero guarda o descarta los cambios.');
      return;
    }
    Permissions.viewAs.value = col.custom ? Permissions.customRole(col.key) : col.key;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        title: const Text('Roles y permisos'),
        actions: [
          if (widget.canEdit && !_loading)
            TextButton.icon(onPressed: _create, icon: const Icon(Icons.add_outlined, size: 18), label: const Text('Crear rol')),
          const SizedBox(width: AppSpace.sm),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(wide ? AppSpace.xl : AppSpace.lg, AppSpace.lg, wide ? AppSpace.xl : AppSpace.lg, 120),
              children: [
                _header(c),
                if (_note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.sm),
                    child: Text(_note!, style: AppText.small(context, color: c.info)),
                  ),
                const SizedBox(height: AppSpace.md),
                if (wide) _matrix(c) else _single(c),
                const SizedBox(height: AppSpace.lg),
                _legend(c),
              ],
            ),
      bottomNavigationBar: _changes == 0 ? null : _saveBar(c),
    );
  }

  Widget _header(StockealoColors c) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lo que puede hacer cada rol', style: AppText.title(context)),
                const SizedBox(height: 2),
                Text(
                  widget.canEdit
                      ? 'Los cambios se aplican a todo el equipo. El Dueño siempre tiene todo.'
                      : 'Solo el dueño puede cambiar los roles. Aquí ves lo que puede hacer cada uno.',
                  style: AppText.small(context, color: c.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$_active/${_cols.length * Perm.values.length}', style: AppText.heading(context)),
              Text('permisos activos', style: AppText.caption(context)),
            ],
          ),
        ],
      );

  // ---------------------------------------------------------------------------
  // Computador: la matriz
  // ---------------------------------------------------------------------------

  static const _labelWidth = 280.0;
  static const _colWidth = 150.0;

  Widget _matrix(StockealoColors c) {
    final rows = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: _labelWidth),
          for (final col in _cols) SizedBox(width: _colWidth, child: _colHeader(c, col)),
        ],
      ),
    ];
    for (final g in PermGroup.values) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.xs),
        child: Text(g.label.toUpperCase(), style: AppText.caption(context, weight: FontWeight.w700, color: c.inkFaint)),
      ));
      for (final p in Perm.values.where((p) => p.group == g)) {
        rows.add(Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(
            children: [
              SizedBox(width: _labelWidth, child: _permLabel(c, p)),
              for (final col in _cols) SizedBox(width: _colWidth, child: Center(child: _switch(c, col, p))),
            ],
          ),
        ));
      }
    }
    rows.add(_limitsTitle(c));
    for (final l in RoleLimit.values) {
      rows.add(Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Row(
          children: [
            SizedBox(width: _labelWidth, child: _limitLabel(c, l)),
            for (final col in _cols) SizedBox(width: _colWidth, child: Center(child: _limitField(c, col, l))),
          ],
        ),
      ));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: _labelWidth + _colWidth * _cols.length,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
      ),
    );
  }

  Widget _colHeader(StockealoColors c, _Col col) {
    final n = _draft[col.key]!.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: c.line)),
      child: Column(
        children: [
          Icon(col.icon, size: 20, color: c.inkMuted),
          const SizedBox(height: 2),
          Text(col.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(context, weight: FontWeight.w700)),
          if (col.custom) Text('Rol propio', style: AppText.caption(context, color: c.info)),
          const SizedBox(height: 4),
          _countBar(c, n),
          Text('$n/${Perm.values.length}', style: AppText.caption(context)),
          const SizedBox(height: 4),
          _colActions(c, col, compact: true),
        ],
      ),
    );
  }

  Widget _countBar(StockealoColors c, int n) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: LinearProgressIndicator(
          value: n / Perm.values.length,
          minHeight: 5,
          backgroundColor: c.surfaceMuted,
          color: c.accent,
        ),
      );

  /// Seleccionar todo, Ver como y Borrar (rol propio); el Dueño: candado
  Widget _colActions(StockealoColors c, _Col col, {required bool compact}) {
    if (col.locked) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 14, color: c.inkFaint),
          const SizedBox(width: 4),
          Flexible(
            child: Text('Siempre todo',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption(context, color: c.inkFaint)),
          ),
        ],
      );
    }
    final all = _draft[col.key]!.length == Perm.values.length;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 2,
      children: [
        // En la matriz (columnas angostas) va como ícono; en el celular, con texto
        if (widget.canEdit && compact)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: all ? 'Quitar todo' : 'Seleccionar todo',
            onPressed: () => _toggleAll(col),
            icon: Icon(all ? Icons.remove_done_outlined : Icons.done_all_outlined, size: 18, color: c.accent),
          )
        else if (widget.canEdit)
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
            onPressed: () => _toggleAll(col),
            child: Text(all ? 'Quitar todo' : 'Seleccionar todo', style: AppText.caption(context, weight: FontWeight.w700, color: c.accent)),
          ),
        if (widget.canEdit)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Ver como ${col.name}',
            onPressed: () => _viewAs(col),
            icon: Icon(Icons.visibility_outlined, size: 18, color: c.inkMuted),
          ),
        if (widget.canEdit && col.custom)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Borrar el rol ${col.name}',
            onPressed: () => _delete(col),
            icon: Icon(Icons.delete_outline, size: 18, color: c.danger),
          ),
      ],
    );
  }

  Widget _permLabel(StockealoColors c, Perm p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.label, style: AppText.body(context, weight: FontWeight.w600)),
          Text(p.help, style: AppText.caption(context)),
        ],
      );

  Widget _switch(StockealoColors c, _Col col, Perm p) {
    final on = _draft[col.key]!.contains(p);
    final sw = Semantics(
      label: '${col.name}: ${p.label}',
      toggled: on,
      child: Switch(
        value: on,
        onChanged: col.locked || !widget.canEdit ? null : (_) => _toggle(col, p),
      ),
    );
    if (!_changed(col.key, p)) return sw;
    // Cambio sin guardar: un punto al lado
    return Stack(
      clipBehavior: Clip.none,
      children: [
        sw,
        Positioned(
          right: -2,
          top: 4,
          child: Container(width: 8, height: 8, decoration: BoxDecoration(color: c.warning, shape: BoxShape.circle)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Celular: un rol a la vez
  // ---------------------------------------------------------------------------

  Widget _single(StockealoColors c) {
    final col = _cols.firstWhere((x) => x.key == _selected, orElse: () => _cols[2]);
    final n = _draft[col.key]!.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterTabs<String>(
          wrap: true,
          options: {for (final x in _cols) x.key: x.name},
          value: col.key,
          onChanged: (v) => setState(() => _selected = v),
        ),
        const SizedBox(height: AppSpace.md),
        Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: c.line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(col.icon, color: c.inkMuted),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(col.name, style: AppText.body(context, weight: FontWeight.w700)),
                        Text('$n/${Perm.values.length} permisos${col.custom ? ' · rol propio' : ''}', style: AppText.caption(context)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              _countBar(c, n),
              const SizedBox(height: AppSpace.xs),
              Align(alignment: Alignment.centerRight, child: _colActions(c, col, compact: false)),
            ],
          ),
        ),
        for (final g in PermGroup.values) ...[
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.xs),
            child: Text(g.label.toUpperCase(), style: AppText.caption(context, weight: FontWeight.w700, color: c.inkFaint)),
          ),
          for (final p in Perm.values.where((p) => p.group == g))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
              child: Row(children: [Expanded(child: _permLabel(c, p)), _switch(c, col, p)]),
            ),
        ],
        _limitsTitle(c),
        for (final l in RoleLimit.values)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: Row(children: [Expanded(child: _limitLabel(c, l)), const SizedBox(width: AppSpace.sm), _limitField(c, col, l)]),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Límites con números (Pro)
  // ---------------------------------------------------------------------------

  Widget _limitsTitle(StockealoColors c) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.xs),
        child: Row(
          children: [
            Text('LÍMITES', style: AppText.caption(context, weight: FontWeight.w700, color: c.inkFaint)),
            const SizedBox(width: AppSpace.sm),
            const StatusPill('Pro', tone: AppTone.accent, compact: true),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              child: Text('Vacío = sin límite. Si se pasa, pide autorización.',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.caption(context)),
            ),
          ],
        ),
      );

  Widget _limitLabel(StockealoColors c, RoleLimit l) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.label, style: AppText.body(context, weight: FontWeight.w600)),
          Text(l.help, style: AppText.caption(context)),
        ],
      );

  Widget _limitField(StockealoColors c, _Col col, RoleLimit l) {
    if (col.locked) return Text('Sin límite', style: AppText.caption(context, color: c.inkFaint));
    final field = _limitFields['${col.key}|${l.name}']!;
    final editable = widget.canEdit && _pro;
    final box = SizedBox(
      width: 112,
      child: TextField(
        controller: field,
        enabled: editable,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        onChanged: (v) => setState(() {
          final n = double.tryParse(v.trim());
          if (n == null) {
            _draftLimits[col.key]!.remove(l);
          } else {
            _draftLimits[col.key]![l] = n;
          }
        }),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Sin límite',
          prefixText: l.unit == '\$' ? '\$ ' : null,
          suffixText: l.unit == '\$' ? null : l.unit,
        ),
      ),
    );
    if (!_limitChanged(col.key, l)) return box;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        box,
        Positioned(
          right: -4,
          top: -2,
          child: Container(width: 8, height: 8, decoration: BoxDecoration(color: c.warning, shape: BoxShape.circle)),
        ),
      ],
    );
  }

  Widget _legend(StockealoColors c) => Wrap(
        spacing: AppSpace.lg,
        runSpacing: AppSpace.xs,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c.warning, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text('Cambio sin guardar', style: AppText.caption(context)),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 14, color: c.inkFaint),
            const SizedBox(width: 4),
            Text('No se puede cambiar', style: AppText.caption(context)),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.visibility_outlined, size: 14, color: c.inkFaint),
            const SizedBox(width: 4),
            Text('Ver la app como ese rol', style: AppText.caption(context)),
          ]),
        ],
      );

  Widget _saveBar(StockealoColors c) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(AppSpace.md),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: c.lineStrong)),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: c.warning, shape: BoxShape.circle)),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text('$_changes ${_changes == 1 ? 'cambio sin guardar' : 'cambios sin guardar'}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(context)),
              ),
              TextButton(onPressed: _saving ? null : _discard, child: const Text('Descartar')),
              const SizedBox(width: AppSpace.xs),
              // Mientras guarda: el mismo botón con un indicador (no cambia de ancho)
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Guardar'),
              ),
            ],
          ),
        ),
      );
}
