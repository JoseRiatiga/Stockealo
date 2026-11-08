import 'package:flutter/material.dart';

import '../services/maintenance_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_tokens.dart';

/// Envuelve la app: franja de aviso cuando hay mantenimiento programado o en curso,
/// y pantalla de mantenimiento en el cierre total (los administradores siguen entrando).
class MaintenanceGate extends StatefulWidget {
  final Widget child;
  const MaintenanceGate({super.key, required this.child});

  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  /// "hoy a las 4:30 p. m." o "12 de noviembre a las 10:00 p. m.". Se arma a mano y
  /// no con los formatos de intl: el panel y las tiendas no cargaban el español y
  /// la página quedaba en gris ("Locale data has not been initialized").
  static String when(DateTime? d, {DateTime? now}) {
    if (d == null) return '';
    final today = now ?? DateTime.now();
    final sameDay = d.year == today.year && d.month == today.month && d.day == today.day;
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final hour = '$h12:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'a. m.' : 'p. m.'}';
    return sameDay ? 'hoy a las $hour' : '${d.day} de ${_months[d.month - 1]} a las $hour';
  }

  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate> {
  final _service = MaintenanceService.instance;
  bool _wasPaused = false;

  @override
  void initState() {
    super.initState();
    _service.state.addListener(_changed);
  }

  @override
  void dispose() {
    _service.state.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    // Al terminar la pausa de la nube se envía lo que se guardó mientras tanto
    final paused = _service.cloudPaused;
    if (_wasPaused && !paused) SupabaseService.instance.flushPendingSync();
    _wasPaused = paused;
    if (mounted) setState(() {});
  }

  String? _bannerText(MaintenanceState s) {
    if (!s.affects('app')) return null;
    final note = (s.message ?? '').trim();
    final extra = note.isEmpty ? '' : ' $note';
    if (s.notice) {
      return 'Mantenimiento programado ${MaintenanceGate.when(s.startsAt)}, '
          'hasta ${MaintenanceGate.when(s.endsAt)}.$extra';
    }
    if (!s.active) return null;
    if (_service.isAdmin) return 'Mantenimiento en curso (nivel ${s.level}): eres administrador, puedes seguir usando la app.';
    if (s.level >= 2) {
      return 'La nube está en mantenimiento hasta ${MaintenanceGate.when(s.endsAt)}. Puedes seguir vendiendo: '
          'todo se guarda en este equipo y se sube al terminar.$extra';
    }
    return 'Mantenimiento en curso hasta ${MaintenanceGate.when(s.endsAt)}.$extra';
  }

  @override
  Widget build(BuildContext context) {
    final s = _service.state.value;
    if (_service.appClosed) return _ClosedScreen(state: s);
    final text = _bannerText(s);
    if (text == null) return widget.child;
    final c = context.colors;
    return Column(
      children: [
        Material(
          color: c.warningSoft,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
              child: Row(
                children: [
                  Icon(Icons.construction_rounded, size: 18, color: c.warning),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: c.ink))),
                ],
              ),
            ),
          ),
        ),
        // La franja ya ocupa el borde de arriba: el resto no necesita volver a apartarlo
        Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.child)),
      ],
    );
  }
}

class _ClosedScreen extends StatelessWidget {
  final MaintenanceState state;
  const _ClosedScreen({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final note = (state.message ?? '').trim();
    return Material(
      color: c.paper,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset('assets/icon/app_icon.png', width: 64, height: 64),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Text(
                    'Estamos en mantenimiento',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.ink),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Volvemos ${MaintenanceGate.when(state.endsAt)}. Tus datos están a salvo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.4, color: c.inkMuted),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.md),
                    Text(note, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.ink)),
                  ],
                  const SizedBox(height: AppSpace.xl),
                  OutlinedButton.icon(
                    onPressed: MaintenanceService.instance.refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Volver a intentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
