import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../core/widgets/app_toast.dart';
import '../core/widgets/maintenance_gate.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_widgets.dart';

/// Programar o activar el mantenimiento: nivel, partes, horario y mensaje
class AdminMaintenancePage extends StatefulWidget {
  const AdminMaintenancePage({super.key});

  @override
  State<AdminMaintenancePage> createState() => _AdminMaintenancePageState();
}

class _AdminMaintenancePageState extends State<AdminMaintenancePage> {
  Map<String, dynamic>? _current;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  int _level = 2;
  final Set<String> _scopes = {'app', 'stores'};
  bool _startNow = true;
  DateTime _startsAt = DateTime.now().add(const Duration(hours: 2));
  Duration _duration = const Duration(hours: 1);
  int _noticeHours = 2;
  final _message = TextEditingController();
  final _confirm = TextEditingController();

  static const _durations = [
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 4),
    Duration(hours: 8),
    Duration(hours: 24),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final m = await ProAdminService.instance.getMaintenance();
      if (mounted) setState(() => _current = m);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> get _public => Map<String, dynamic>.from((_current?['public'] as Map?) ?? const {});
  String get _state => '${_public['state'] ?? 'none'}';

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_startsAt));
    if (time == null) return;
    setState(() => _startsAt = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final starts = _startNow ? DateTime.now() : _startsAt;
    final ends = starts.add(_duration);
    setState(() => _saving = true);
    try {
      await ProAdminService.instance.setMaintenance(
        level: _level,
        scopes: _scopes.toList(),
        startsAt: starts,
        endsAt: ends,
        message: _message.text.trim(),
        noticeHours: _noticeHours,
        confirm: _confirm.text,
      );
      if (!mounted) return;
      AppToast.show(
        context,
        message: _startNow ? 'Mantenimiento activado hasta ${MaintenanceGate.when(ends)}.' : 'Mantenimiento programado.',
        type: ToastType.success,
      );
      _confirm.clear();
      _load();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _end() async {
    try {
      await ProAdminService.instance.endMaintenance();
      if (!mounted) return;
      AppToast.show(context, message: 'Mantenimiento terminado. Todo vuelve a funcionar.', type: ToastType.success);
      _load();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final owner = ProAdminService.instance.isOwner;
    final state = AdminLoadState(loading: _loading, error: _error, empty: _current == null, emptyText: '', onRetry: _load);
    return AdminPage(
      title: 'Mantenimiento',
      subtitle: 'Avisa, pausa la nube o cierra Stockealo mientras haces cambios',
      onRefresh: _load,
      children: state.blocking
          ? [state]
          : [
              _statusCard(c),
              const SizedBox(height: AppSpace.md),
              if (!owner)
                Text('Solo el dueño del panel puede programar mantenimientos.', style: TextStyle(color: c.inkMuted))
              else
                _form(c),
            ],
    );
  }

  Widget _statusCard(StockealoColors c) {
    final p = _public;
    final scopes = {for (final s in (p['scopes'] as List? ?? const [])) '$s'};
    final parts = [
      if (scopes.contains('app')) 'app y web',
      if (scopes.contains('stores')) 'tiendas en línea',
      if (scopes.contains('payments')) 'pagos de Pro',
    ].join(', ');
    final ends = DateTime.tryParse('${p['ends_at']}')?.toLocal();
    final starts = DateTime.tryParse('${p['starts_at']}')?.toLocal();
    final (title, tone) = switch (_state) {
      'active' => ('En mantenimiento: ${_levelName(p['level'] as int? ?? 0)}', c.warning),
      'notice' => ('Mantenimiento programado: ya se está avisando', c.info),
      _ => ('Todo funcionando normal', c.success),
    };
    return AdminCard(
      child: Row(
        children: [
          Icon(_state == 'none' ? Icons.check_circle_outline_rounded : Icons.construction_rounded, color: tone),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                if (_state != 'none')
                  Text(
                    '$parts · ${_state == 'notice' ? 'empieza ${MaintenanceGate.when(starts)} · ' : ''}'
                    'termina solo ${MaintenanceGate.when(ends)}',
                    style: TextStyle(fontSize: 13, color: c.inkMuted),
                  ),
              ],
            ),
          ),
          if (_state != 'none' && ProAdminService.instance.isOwner)
            FilledButton(onPressed: _end, child: const Text('Terminar ya')),
        ],
      ),
    );
  }

  static String _levelName(int level) => switch (level) {
        1 => 'solo aviso',
        2 => 'nube en pausa',
        _ => 'cierre total',
      };

  Widget _form(StockealoColors c) {
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.sm),
          child: Text(t, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
        );
    final ends = (_startNow ? DateTime.now() : _startsAt).add(_duration);
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nuevo mantenimiento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
          label('1. Nivel'),
          for (final (lvl, title, detail) in const [
            (1, 'Solo aviso', 'Se muestra una franja con el horario. Todo sigue funcionando.'),
            (2, 'Nube en pausa', 'La app sigue funcionando en cada equipo: venden y editan, y todo sube al terminar. '
                'Las tiendas en línea muestran "en mantenimiento".'),
            (3, 'Cierre total', 'La app y la web muestran la pantalla de mantenimiento. Tú sigues entrando para probar.'),
          ])
            RadioListTile<int>(
              contentPadding: EdgeInsets.zero,
              value: lvl,
              groupValue: _level,
              onChanged: (v) => setState(() => _level = v ?? 2),
              title: Text(title),
              subtitle: Text(detail, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
            ),
          label('2. Qué entra en mantenimiento'),
          for (final (key, title) in const [
            ('app', 'App y web (inventario, ventas…)'),
            ('stores', 'Tiendas en línea'),
            ('payments', 'Pagos de Pro (Wompi)'),
          ])
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _scopes.contains(key),
              onChanged: (v) => setState(() => v == true ? _scopes.add(key) : _scopes.remove(key)),
              title: Text(title),
            ),
          label('3. Cuándo'),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Ahora')),
              ButtonSegment(value: false, label: Text('Programar')),
            ],
            selected: {_startNow},
            onSelectionChanged: (v) => setState(() => _startNow = v.first),
          ),
          if (!_startNow) ...[
            const SizedBox(height: AppSpace.sm),
            OutlinedButton.icon(
              onPressed: _pickStart,
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text('Empieza ${MaintenanceGate.when(_startsAt)}'),
            ),
            const SizedBox(height: AppSpace.sm),
            Row(children: [
              Text('Avisar desde ', style: TextStyle(color: c.inkMuted)),
              DropdownButton<int>(
                value: _noticeHours,
                items: [for (final h in const [0, 1, 2, 6, 12, 24]) DropdownMenuItem(value: h, child: Text(h == 0 ? 'el inicio' : '$h h antes'))],
                onChanged: (v) => setState(() => _noticeHours = v ?? 2),
              ),
            ]),
          ],
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Dura', style: TextStyle(color: c.inkMuted)),
              for (final d in _durations)
                ChoiceChip(
                  label: Text(d.inMinutes < 60 ? '${d.inMinutes} min' : '${d.inHours} h'),
                  selected: _duration == d,
                  onSelected: (_) => setState(() => _duration = d),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: Text('Termina solo ${MaintenanceGate.when(ends)}, aunque se te olvide.',
                style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
          ),
          label('4. Mensaje (opcional)'),
          TextField(
            controller: _message,
            maxLength: 200,
            decoration: const InputDecoration(hintText: 'Ej. Estamos mejorando la velocidad de la app.'),
          ),
          if (_level == 3) ...[
            label('5. Confirma el cierre total'),
            TextField(
              controller: _confirm,
              decoration: const InputDecoration(hintText: 'Escribe MANTENIMIENTO'),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ||
                      _scopes.isEmpty ||
                      (_level == 3 && _confirm.text.trim().toUpperCase() != 'MANTENIMIENTO')
                  ? null
                  : _save,
              icon: const Icon(Icons.construction_rounded),
              label: Text(_saving ? 'Guardando…' : (_startNow ? 'Activar ahora' : 'Programar')),
            ),
          ),
        ],
      ),
    );
  }
}
