import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/supabase_service.dart';
import '../core/theme/app_tokens.dart';

/// Verificación en dos pasos del panel (0.16.0, fase 6, obligatoria). Después de la
/// contraseña:
/// • sin factor todavía: «Activa la verificación en dos pasos» (QR + código);
/// • con factor: «Escribe el código de 6 números».
/// La nube también lo exige: sin el código (sesión aal2) ninguna función del panel
/// responde (migración admin_mfa).
class AdminMfaGate extends StatefulWidget {
  final Widget child;
  final VoidCallback onSignOut;
  const AdminMfaGate({super.key, required this.child, required this.onSignOut});

  @override
  State<AdminMfaGate> createState() => _AdminMfaGateState();
}

class _AdminMfaGateState extends State<AdminMfaGate> {
  GoTrueMFAApi get _mfa => SupabaseService.instance.client!.auth.mfa;

  bool _loading = true;
  bool _verified = false;

  /// Factor ya activado (pedir código) o null (activar)
  String? _factorId;

  /// Inscripción en curso (QR y clave)
  AuthMFAEnrollResponse? _enroll;

  final _code = TextEditingController();
  String? _error;
  bool _working = false;

  /// Una inscripción a la vez en toda la app: si la pantalla se arma de nuevo mientras
  /// otra está inscribiendo, espera esa en vez de borrarla y empezar otra (antes eso
  /// hacía un bucle de «borrar y crear» hasta que la nube frenaba la sesión)
  static Future<AuthMFAEnrollResponse>? _enrolling;

  /// De qué cuenta es [_enrolling]: nunca se muestra el QR de una cuenta a otra
  static String? _enrollingFor;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final level = _mfa.getAuthenticatorAssuranceLevel();
      if (level.currentLevel == AuthenticatorAssuranceLevels.aal2) {
        if (mounted) setState(() => (_verified = true, _loading = false));
        return;
      }
      final factors = await _mfa.listFactors();
      final ready = factors.totp.where((f) => f.status == FactorStatus.verified).firstOrNull;
      if (ready != null) {
        if (mounted) setState(() => (_factorId = ready.id, _loading = false));
        return;
      }
      // Sin factor: limpia los a medias y empieza uno nuevo (solo uno a la vez, por cuenta)
      final userId = SupabaseService.instance.client!.auth.currentUser?.id;
      if (userId == null) throw StateError('Sin sesión');
      if (_enrollingFor != userId) {
        _enrolling = null;
        _enrollingFor = userId;
      }
      final enroll = await (_enrolling ??= () async {
        for (final f in factors.all.where((f) => f.status != FactorStatus.verified)) {
          await _mfa.unenroll(f.id);
        }
        return _mfa.enroll(factorType: FactorType.totp, issuer: 'Stockealo', friendlyName: 'Panel Stockealo');
      }());
      // Si mientras tanto cambió la cuenta, ese QR no es de quien está ahora
      if (SupabaseService.instance.client!.auth.currentUser?.id != userId) return;
      if (mounted) setState(() => (_enroll = enroll, _loading = false));
    } catch (e) {
      _enrolling = null;
      if (mounted) setState(() => (_error = 'No se pudo preparar la verificación. Recarga la página.', _loading = false));
    }
  }

  Future<void> _verify() async {
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      setState(() => _error = 'Escribe los 6 números.');
      return;
    }
    final factorId = _factorId ?? _enroll?.id;
    if (factorId == null) return;
    setState(() => (_working = true, _error = null));
    try {
      await _mfa.challengeAndVerify(factorId: factorId, code: code);
      _enrolling = null;
      if (mounted) setState(() => _verified = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Ese código no sirve. Revisa la hora del celular y escribe el que sale ahora.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verified) return widget.child;
    final c = context.colors;
    final enroll = _enroll?.totp;
    return Scaffold(
      backgroundColor: c.paper,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(AppSpace.xl),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.line)),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.verified_user_outlined, size: 36, color: c.accent),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          enroll != null ? 'Activa la verificación en dos pasos' : 'Verificación en dos pasos',
                          textAlign: TextAlign.center,
                          style: AppText.title(context),
                        ),
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          enroll != null
                              ? 'Es obligatoria para el panel. Escanea el código con Google Authenticator o Microsoft Authenticator.'
                              : 'Escribe el código de 6 números que te sale en la app de códigos.',
                          textAlign: TextAlign.center,
                          style: AppText.small(context, color: c.inkMuted),
                        ),
                        if (enroll != null) ...[
                          const SizedBox(height: AppSpace.md),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(AppSpace.sm),
                              color: Colors.white,
                              child: BarcodeWidget(barcode: Barcode.qrCode(), data: enroll.uri, width: 180, height: 180, color: Colors.black),
                            ),
                          ),
                          const SizedBox(height: AppSpace.sm),
                          Text('¿No puedes escanear? Escribe esta clave:', textAlign: TextAlign.center, style: AppText.small(context, color: c.inkMuted)),
                          SelectableText(
                            enroll.secret.replaceAllMapped(RegExp(r'.{4}'), (m) => '${m[0]} ').trim(),
                            textAlign: TextAlign.center,
                            style: AppText.mono(context),
                          ),
                        ],
                        const SizedBox(height: AppSpace.md),
                        TextField(
                          controller: _code,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 6,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          autofillHints: const [AutofillHints.oneTimeCode],
                          decoration: InputDecoration(labelText: 'Código de 6 números', errorText: _error, counterText: ''),
                          onSubmitted: (_) => _verify(),
                        ),
                        const SizedBox(height: AppSpace.md),
                        FilledButton(
                          onPressed: _working ? null : _verify,
                          child: Text(_working ? 'Revisando…' : (enroll != null ? 'Activar' : 'Entrar')),
                        ),
                        const SizedBox(height: AppSpace.xs),
                        TextButton(
                            onPressed: () {
                              _enrolling = null;
                              _enrollingFor = null;
                              widget.onSignOut();
                            },
                            child: const Text('Cerrar sesión')),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
