import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/auth_repository.dart';

/// Verificar el correo (0.18.4). Las cuentas nuevas entran sin código; este aviso
/// sugiere verificar el correo, sin bloquear nada. Un solo componente: en Inicio se
/// puede cerrar (vuelve a los 7 días) y en Ajustes queda siempre mientras falte.
/// Quién está verificado lo decide la nube.
class EmailVerification {
  EmailVerification._();

  /// true verificada, false sin verificar, null sin saber (sin conexión o sin revisar)
  static ValueNotifier<bool?> get status => AuthRepository.emailVerified;

  static const dismissedKey = 'verify_email_dismissed_at';
  static const daysBetween = 7;

  /// Si lo cerraron en Inicio, vuelve a salir pasados 7 días
  static bool shouldShowOnHome({required DateTime now, DateTime? dismissedAt}) =>
      dismissedAt == null || now.difference(dismissedAt).inDays >= daysBetween;

  static Future<void> refresh() async {
    final verified = await AuthRepository.instance.isEmailVerified();
    if (verified != null) status.value = verified;
  }

  /// Envía el código y pide escribirlo. true si quedó verificada.
  static Future<bool> verify(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _VerifyEmailDialog(),
    );
    if (ok == true) {
      status.value = true;
      if (context.mounted) AppToast.showSuccess(context, 'Listo: tu correo quedó verificado.');
      return true;
    }
    return false;
  }
}

/// El aviso. [dismissible]: en Inicio se puede cerrar por 7 días.
class VerifyEmailNotice extends StatefulWidget {
  final bool dismissible;
  const VerifyEmailNotice({super.key, this.dismissible = false});

  @override
  State<VerifyEmailNotice> createState() => _VerifyEmailNoticeState();
}

class _VerifyEmailNoticeState extends State<VerifyEmailNotice> {
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      if (widget.dismissible) {
        final at = DateTime.tryParse(await AppDatabase.instance.getSetting(EmailVerification.dismissedKey) ?? '');
        if (!EmailVerification.shouldShowOnHome(now: DateTime.now(), dismissedAt: at)) {
          if (mounted) setState(() => _dismissed = true);
          return;
        }
      }
      await EmailVerification.refresh();
    } catch (_) {
      // Un aviso nunca debe romper la pantalla
    }
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    try {
      await AppDatabase.instance.setSetting(EmailVerification.dismissedKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool?>(
      valueListenable: EmailVerification.status,
      builder: (context, verified, _) {
        if (verified != false || _dismissed) return const SizedBox.shrink();
        final c = context.colors;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.lg),
          child: Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.mark_email_unread_outlined, color: c.warning),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verifica tu correo para proteger tu cuenta',
                            style: AppText.bodyLarge(context, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Te enviamos un código de 6 dígitos. Lo necesitas para entrar a un negocio '
                            'por invitación y te ayuda a recuperar la cuenta si olvidas la contraseña.',
                            style: AppText.small(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.dismissible) ...[
                      TextButton(
                        onPressed: _dismiss,
                        style: TextButton.styleFrom(foregroundColor: c.inkMuted),
                        child: const Text('Ahora no'),
                      ),
                      const SizedBox(width: AppSpace.sm),
                    ],
                    FilledButton(
                      onPressed: () => EmailVerification.verify(context),
                      child: const Text('Verificar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VerifyEmailDialog extends StatefulWidget {
  const _VerifyEmailDialog();

  @override
  State<_VerifyEmailDialog> createState() => _VerifyEmailDialogState();
}

class _VerifyEmailDialogState extends State<_VerifyEmailDialog> {
  final _code = TextEditingController();
  bool _sending = true;
  bool _checking = false;
  String? _error;

  String get _email => AuthRepository.instance.currentUser?.email ?? 'tu correo';

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await AuthRepository.instance.sendEmailVerificationCode();
    } catch (e) {
      if (mounted) setState(() => _error = AuthRepository.translateAuthError(e));
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Escribe los 6 dígitos del código.');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await AuthRepository.instance.confirmEmailVerificationCode(code);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _checking = false;
          _error = AuthRepository.translateAuthError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppDialog(
      title: 'Verifica tu correo',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _sending
                ? 'Enviando el código a $_email…'
                : 'Enviamos un código de 6 dígitos a $_email. Si no lo ves, revisa la carpeta de spam '
                    'o promociones.',
            style: TextStyle(color: c.inkMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            enabled: !_checking,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: AppText.sizeHeading, letterSpacing: 8, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: (_) => _confirm(),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(_error!, style: TextStyle(color: c.danger)),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _sending || _checking ? null : _send,
              child: const Text('Reenviar el código'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.pop(context, false),
          child: const Text('Ahora no'),
        ),
        FilledButton(
          onPressed: _checking ? null : _confirm,
          child: Text(_checking ? 'Verificando…' : 'Verificar'),
        ),
      ],
    );
  }
}
