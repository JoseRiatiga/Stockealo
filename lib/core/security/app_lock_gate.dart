import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_lock.dart';

/// Tapa la app con el PIN cuando [AppLock] está bloqueada (0.16.0, fase 6): al abrirla
/// y al volver después del tiempo elegido.
class AppLockGate extends StatefulWidget {
  final Widget child;
  final String? title;

  /// «¿Olvidaste tu PIN? Entra con tu contraseña»: apaga el bloqueo y cierra la sesión
  final Future<void> Function() onUsePassword;

  const AppLockGate({super.key, required this.child, required this.onUsePassword, this.title});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final _lock = AppLock.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lock.onStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) _lock.onLeave();
    if (state == AppLifecycleState.resumed) _lock.onReturn();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _lock.locked,
      builder: (context, locked, child) => Stack(
        children: [
          // La app sigue viva debajo (no se pierde lo que estaba haciendo)
          Offstage(offstage: locked, child: TickerMode(enabled: !locked, child: child!)),
          if (locked) Positioned.fill(child: LockScreen(title: widget.title, onUsePassword: widget.onUsePassword)),
        ],
      ),
      child: widget.child,
    );
  }
}

/// La pantalla del PIN
class LockScreen extends StatefulWidget {
  final String? title;
  final Future<void> Function() onUsePassword;
  const LockScreen({super.key, this.title, required this.onUsePassword});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _lock = AppLock.instance;
  String _pin = '';
  String? _error;
  bool _bio = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _lock.pinLength().then((n) {
      if (mounted) setState(() => _length = n);
    });
    _prepareBio();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Cuántos números tiene el PIN: al completarlos se revisa solo
  int? _length;

  Future<void> _prepareBio() async {
    final on = await _lock.bioOn() && await _lock.bioAvailable();
    if (!mounted) return;
    setState(() => _bio = on);
    if (on) _lock.unlockWithBio();
  }

  Future<void> _type(String d) async {
    if (_lock.waitLeft != null) return;
    setState(() {
      _error = null;
      if (_pin.length < 6) _pin += d;
    });
    // Se revisa una sola vez, al completar el PIN (o con «Entrar» si no se sabe el largo)
    final length = _length;
    if (length != null ? _pin.length == length : _pin.length == 6) {
      if (!await _lock.check(_pin) && mounted) _wrong();
    }
  }

  void _wrong() {
    final wait = _lock.waitLeft;
    setState(() {
      _pin = '';
      _error = wait != null ? 'Muchos intentos. Espera ${wait.inSeconds} segundos.' : 'PIN incorrecto';
    });
    if (wait != null) {
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (t) {
        final left = _lock.waitLeft;
        if (!mounted) return t.cancel();
        setState(() => _error = left == null ? null : 'Muchos intentos. Espera ${left.inSeconds} segundos.');
        if (left == null) t.cancel();
      });
    }
  }

  Future<void> _submit() async {
    if (_pin.length < 4) return;
    if (!await _lock.check(_pin) && mounted) _wrong();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget key(String label, {VoidCallback? onTap, IconData? icon, String? tooltip}) => SizedBox(
          width: 76,
          height: 64,
          child: TextButton(
            onPressed: onTap,
            child: icon != null
                ? Icon(icon, size: 26, semanticLabel: tooltip)
                : Text(label, style: AppText.heading(context, weight: FontWeight.w500)),
          ),
        );
    return Material(
      color: c.paper,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 36, color: c.accent),
                const SizedBox(height: AppSpace.sm),
                Text(widget.title ?? 'Stockealo', textAlign: TextAlign.center, style: AppText.title(context)),
                const SizedBox(height: AppSpace.xs),
                Text('Escribe tu PIN', style: AppText.body(context, color: c.inkMuted)),
                const SizedBox(height: AppSpace.md),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 6; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _pin.length ? c.ink : null,
                          border: Border.all(color: i < _pin.length ? c.ink : c.lineStrong, width: 1.5),
                        ),
                      ),
                  ],
                ),
                SizedBox(
                  height: 28,
                  child: _error == null
                      ? null
                      : Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(_error!, style: AppText.small(context, color: c.danger))),
                ),
                for (final row in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                ])
                  Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d, onTap: () => _type(d))]),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _bio
                        ? key('', icon: Icons.fingerprint, tooltip: 'Usar la huella', onTap: () => _lock.unlockWithBio())
                        : key('', icon: Icons.backspace_outlined, tooltip: 'Borrar', onTap: _pin.isEmpty ? null : () => setState(() => _pin = _pin.substring(0, _pin.length - 1))),
                    key('0', onTap: () => _type('0')),
                    key('', icon: Icons.check, tooltip: 'Entrar', onTap: _pin.length >= 4 ? _submit : null),
                  ],
                ),
                if (_bio)
                  TextButton.icon(
                    onPressed: _pin.isEmpty ? null : () => setState(() => _pin = _pin.substring(0, _pin.length - 1)),
                    icon: const Icon(Icons.backspace_outlined, size: 18),
                    label: const Text('Borrar'),
                  ),
                const SizedBox(height: AppSpace.md),
                TextButton(
                  onPressed: () async {
                    await _lock.disable();
                    await widget.onUsePassword();
                  },
                  child: const Text('¿Olvidaste tu PIN? Entra con tu contraseña'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
