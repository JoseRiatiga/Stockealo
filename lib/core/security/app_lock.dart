import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../database/app_database.dart';

/// Bloqueo de la app con PIN o huella (0.16.0, fase 6, opcional, en Perfil ›
/// Privacidad). El PIN nunca se guarda tal cual: se guarda su huella digital (SHA-256
/// con sal). Si la persona lo olvida, entra con su contraseña y el bloqueo se apaga.
class AppLock {
  AppLock._();
  static final AppLock instance = AppLock._();

  static const _onKey = 'app_lock_on';
  static const _hashKey = 'app_lock_pin_hash';
  static const _saltKey = 'app_lock_pin_salt';
  static const _bioKey = 'app_lock_bio';
  static const _afterKey = 'app_lock_after_minutes';

  /// Tras estos intentos fallidos, espera [waitAfterFails]
  static const maxFails = 5;
  static const waitAfterFails = Duration(seconds: 30);

  /// Minutos fuera de la app antes de pedir el PIN otra vez (0 = siempre al volver)
  static const afterOptions = [0, 1, 5, 15];
  static const defaultAfter = 5;

  /// Está bloqueada ahora (la pantalla del PIN lo escucha)
  final ValueNotifier<bool> locked = ValueNotifier(false);

  /// Para las pruebas: la huella (por defecto, la del celular)
  @visibleForTesting
  LocalAuthentication? biometrics;
  LocalAuthentication get _bio => biometrics ??= LocalAuthentication();

  int _fails = 0;
  DateTime? _blockedUntil;
  DateTime? _leftAt;

  Future<String?> _get(String k) => AppDatabase.instance.getSetting(k);
  Future<void> _set(String k, String? v) => AppDatabase.instance.setSetting(k, v);

  Future<bool> isOn() async => await _get(_onKey) == '1' && await _get(_hashKey) != null;
  Future<bool> bioOn() async => await _get(_bioKey) == '1';
  Future<int> afterMinutes() async => int.tryParse(await _get(_afterKey) ?? '') ?? defaultAfter;

  static bool validPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

  static String _hash(String salt, String pin) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// Enciende el bloqueo con este PIN (4 a 6 números)
  Future<void> enable(String pin) async {
    if (!validPin(pin)) throw ArgumentError('El PIN debe tener de 4 a 6 números.');
    final r = Random.secure();
    final salt = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
    await _set(_saltKey, salt);
    await _set(_hashKey, _hash(salt, pin));
    await _set(_onKey, '1');
    _fails = 0;
  }

  /// Apaga el bloqueo y borra el PIN
  Future<void> disable() async {
    for (final k in [_onKey, _hashKey, _saltKey, _bioKey]) {
      await _set(k, null);
    }
    locked.value = false;
  }

  Future<void> setBio(bool on) => _set(_bioKey, on ? '1' : null);
  Future<void> setAfter(int minutes) => _set(_afterKey, '$minutes');

  /// Si está esperando por muchos intentos, cuánto falta
  Duration? get waitLeft {
    final until = _blockedUntil;
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  /// Revisa el PIN. Si es correcto, desbloquea.
  Future<bool> check(String pin) async {
    if (waitLeft != null) return false;
    final salt = await _get(_saltKey), hash = await _get(_hashKey);
    final ok = salt != null && hash != null && _hash(salt, pin) == hash;
    if (ok) {
      _fails = 0;
      locked.value = false;
    } else if (++_fails >= maxFails) {
      _fails = 0;
      _blockedUntil = DateTime.now().add(waitAfterFails);
    }
    return ok;
  }

  /// La huella o el rostro sirven en este equipo (no en la web)
  Future<bool> bioAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _bio.isDeviceSupported() && (await _bio.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Pide la huella. Si sirve, desbloquea.
  Future<bool> unlockWithBio() async {
    if (!await bioOn() || !await bioAvailable()) return false;
    try {
      final ok = await _bio.authenticate(localizedReason: 'Abre Stockealo', biometricOnly: true, persistAcrossBackgrounding: true);
      if (ok) locked.value = false;
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Al abrir la app
  Future<void> onStart() async {
    if (await isOn()) locked.value = true;
  }

  /// La app pasó a segundo plano
  void onLeave() => _leftAt = DateTime.now();

  /// La app volvió: bloquea si pasó el tiempo elegido
  Future<void> onReturn({DateTime? now}) async {
    final left = _leftAt;
    _leftAt = null;
    if (left == null || !await isOn()) return;
    final minutes = await afterMinutes();
    if ((now ?? DateTime.now()).difference(left).inMinutes >= minutes) locked.value = true;
  }

  @visibleForTesting
  void resetForTest() {
    _fails = 0;
    _blockedUntil = null;
    _leftAt = null;
    locked.value = false;
  }
}
