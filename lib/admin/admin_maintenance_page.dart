import 'package:flutter/material.dart';

import '../core/services/maintenance_service.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/maintenance_text.dart';
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

  /// Inicio y fin programados: se eligen en hora de Colombia (se guardan como instantes)
  DateTime _startsAt = _roundedHour(DateTime.now().add(const Duration(hours: 2)));
  DateTime _endsAt = _roundedHour(DateTime.now().add(const Duration(hours: 5)));

  /// Con «Ahora»: cuánto dura
  Duration _nowDuration = const Duration(hours: 1);

  /// Horas antes del inicio en que empieza el aviso; -1 = desde ya
  int _noticeHours = 24;
  final _message = TextEditingController();
  final _confirm = TextEditingController();

  static DateTime _roundedHour(DateTime d) => DateTime(d.year, d.month, d.day, d.hour);

  static const _nowDurations = [
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 3),
    Duration(hours: 4),
    Duration(hours: 8),
  ];

  static const _noticeOptions = <int, String>{
    0: 'al empezar',
    2: '2 h antes',
    12: '12 h antes',
    24: '1 día antes',
    48: '2 días antes',
    72: '3 días antes',
    168: '1 semana antes',
    -1: 'desde ya',
  };

  DateTime get _starts => _startNow ? DateTime.now() : _startsAt;
  DateTime get _ends => _startNow ? DateTime.now().add(_nowDuration) : _endsAt;

  /// Horas de aviso que se envían al servidor («desde ya» = hasta que empiece)
  int get _noticeToSend {
    if (_startNow) return 0;
    if (_noticeHours >= 0) return _noticeHours;
    return (_startsAt.difference(DateTime.now()).inMinutes / 60).ceil().clamp(0, 720);
  }

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

  /// Elegir fecha y hora en hora de Colombia
  Future<DateTime?> _pickColombia(DateTime current, {bool timeOnly = false}) async {
    final co = MaintenanceText.colombiaWall(current);
    var day = DateTime(co.year, co.month, co.day);
    if (!timeOnly) {
      final now = MaintenanceText.colombiaWall(DateTime.now());
      final picked = await showDatePicker(
        context: context,
        initialDate: day.isBefore(DateTime(now.year, now.month, now.day)) ? DateTime(now.year, now.month, now.day) : day,
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: DateTime(now.year, now.month, now.day).add(const Duration(days: 30)),
        helpText: 'Fecha (hora Colombia)',
      );
      if (picked == null || !mounted) return null;
      day = picked;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: co.hour, minute: co.minute),
      helpText: 'Hora de Colombia',
    );
    if (time == null) return null;
    return MaintenanceText.fromColombia(day.year, day.month, day.day, time.hour, time.minute).toLocal();
  }

  Future<void> _pickStart() async {
    final picked = await _pickColombia(_startsAt);
    if (picked == null) return;
    final length = _endsAt.difference(_startsAt);
    setState(() {
      _startsAt = picked;
      // Conserva la duración que había
      _endsAt = picked.add(length.isNegative || length == Duration.zero ? const Duration(hours: 3) : length);
    });
  }

  /// La hora de fin: si queda antes del inicio, es al día siguiente (cruza la medianoche)
  Future<void> _pickEnd() async {
    final picked = await _pickColombia(_endsAt, timeOnly: true);
    if (picked == null) return;
    final startCo = MaintenanceText.colombiaWall(_startsAt);
    final endCo = MaintenanceText.colombiaWall(picked);
    var end = MaintenanceText.fromColombia(startCo.year, startCo.month, startCo.day, endCo.hour, endCo.minute).toLocal();
    if (!end.isAfter(_startsAt)) end = end.add(const Duration(days: 1));
    setState(() => _endsAt = end);
  }

  Future<void> _save() async {
    final starts = _starts;
    final ends = _ends;
    if (ends.difference(starts) > const Duration(hours: 48)) {
      AppToast.show(context, message: 'Un mantenimiento dura como máximo 48 horas.', type: ToastType.warning);
      return;
    }
    setState(() => _saving = true);
    try {
      await ProAdminService.instance.setMaintenance(
        level: _level,
        scopes: _scopes.toList(),
        startsAt: starts,
        endsAt: ends,
        message: _message.text.trim(),
        noticeHours: _noticeToSend,
        confirm: _confirm.text,
      );
      if (!mounted) return;
      AppToast.show(
        context,
        message: _startNow
            ? 'Mantenimiento activado hasta ${MaintenanceGate.when(ends)}.'
            : 'Mantenimiento programado ${MaintenanceText.describe(starts, ends)}.',
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

  /// "5 de diciembre a las 11:00 p. m." en hora de Colombia
  static String _coLabel(DateTime d) {
    final co = MaintenanceText.colombiaWall(d);
    return MaintenanceGate.when(DateTime(co.year, co.month, co.day, co.hour, co.minute),
        now: MaintenanceText.colombiaWall(DateTime.now()).copyWith(isUtc: false));
  }

  /// La franja y la ventana tal como las verán los usuarios
  Widget _preview(StockealoColors c, DateTime starts, DateTime ends) {
    final s = MaintenanceState(
      state: _startNow ? 'active' : 'notice',
      level: _level,
      scopes: _scopes,
      message: _message.text.trim(),
      startsAt: starts,
      endsAt: ends,
    );
    // Vista como la de alguien en Colombia
    final banner = MaintenanceText.banner(s, isAdmin: false, deviceOffset: MaintenanceText.colombiaOffset);
    final dialog = MaintenanceText.noticeDialog(s, deviceOffset: MaintenanceText.colombiaOffset);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (banner != null)
          Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(color: c.warningSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Row(
              children: [
                Icon(Icons.construction_rounded, size: 18, color: c.warning),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(banner, style: TextStyle(fontSize: 12.5, color: c.ink))),
              ],
            ),
          )
        else
          Text('Sin «App y web» marcada, la app no muestra franja.', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
        if (_scopes.contains('app')) ...[
          const SizedBox(height: AppSpace.sm),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ventana (sale una vez): ${dialog.title}', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                const SizedBox(height: AppSpace.xs),
                Text(dialog.body, style: TextStyle(fontSize: 13, color: c.ink)),
              ],
            ),
          ),
        ],
      ],
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
    final starts = _starts;
    final ends = _ends;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nuevo mantenimiento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
          label('1. Nivel'),
          RadioGroup<int>(
            groupValue: _level,
            onChanged: (v) => setState(() => _level = v ?? 2),
            child: Column(
              children: [
                for (final (lvl, title, detail) in const [
                  (1, 'Solo aviso', 'Se muestra una franja con el horario. Todo sigue funcionando.'),
                  (2, 'Nube en pausa', 'La app sigue funcionando en cada equipo: venden y editan, y todo sube al terminar. '
                      'Las tiendas en línea muestran "en mantenimiento".'),
                  (3, 'Cierre total', 'La app y la web muestran la pantalla de mantenimiento. Tú sigues entrando para probar.'),
                ])
                  RadioListTile<int>(
                    contentPadding: EdgeInsets.zero,
                    value: lvl,
                    title: Text(title),
                    subtitle: Text(detail, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                  ),
              ],
            ),
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
          label('3. Cuándo (hora Colombia)'),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Ahora')),
              ButtonSegment(value: false, label: Text('Programar')),
            ],
            selected: {_startNow},
            onSelectionChanged: (v) => setState(() => _startNow = v.first),
          ),
          const SizedBox(height: AppSpace.sm),
          if (_startNow)
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Dura', style: TextStyle(color: c.inkMuted)),
                for (final d in _nowDurations)
                  ChoiceChip(
                    label: Text(MaintenanceText.duration(d)),
                    selected: _nowDuration == d,
                    onSelected: (_) => setState(() => _nowDuration = d),
                  ),
              ],
            )
          else ...[
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickStart,
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text('Empieza ${_coLabel(_startsAt)}'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickEnd,
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text('Termina ${_coLabel(_endsAt)}'),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Row(children: [
              Text('Avisar ', style: TextStyle(color: c.inkMuted)),
              DropdownButton<int>(
                value: _noticeHours,
                items: [for (final e in _noticeOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _noticeHours = v ?? 24),
              ),
            ]),
          ],
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: Text(
              'Dura ${MaintenanceText.duration(ends.difference(starts))} · termina solo, aunque se te olvide.',
              style: TextStyle(fontSize: 12.5, color: ends.difference(starts) > const Duration(hours: 48) ? c.danger : c.inkMuted),
            ),
          ),
          label('4. Mensaje'),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final (title, text) in MaintenanceText.presets)
                ActionChip(
                  label: Text(title),
                  onPressed: () => setState(() {
                    final current = _message.text.trim();
                    _message.text = current.isEmpty ? text : '$current $text';
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _message,
            maxLength: 300,
            maxLines: 3,
            minLines: 1,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Ej. Te recomendamos no agregar productos durante ese horario.'),
          ),
          label('Vista previa: así lo verán'),
          _preview(c, starts, ends),
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
