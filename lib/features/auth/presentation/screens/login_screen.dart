import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/design/phone_field.dart';
import '../../../../core/design/primary_action_button.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/countries.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/auth_repository.dart';
import '../../../legal/presentation/screens/legal_document_screen.dart';
import '../widgets/forgot_password_dialog.dart';
import '../widgets/stocky_mascot.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authRepo = AuthRepository.instance;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _phoneValid = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  StockyState _mascotState = StockyState.idle;
  double _mascotLookProgress = 0.0;

  bool _isRegisterMode = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _acceptTerms = false;
  String? _errorMessage;

  late final _termsTap = TapGestureRecognizer()
    ..onTap = () => LegalDocumentScreen.show(context, initialTabIndex: 0);
  late final _privacyTap = TapGestureRecognizer()
    ..onTap = () => LegalDocumentScreen.show(context, initialTabIndex: 1);

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(_onFocusChanged);
    _passwordFocus.addListener(_onFocusChanged);
    _confirmPasswordFocus.addListener(_onFocusChanged);
    _emailController.addListener(_onEmailChanged);
  }

  void _onEmailChanged() {
    final text = _emailController.text;
    final len = text.length;
    final p = ((len / 25.0) * 2.0 - 1.0).clamp(-1.0, 1.0);
    if (_mascotLookProgress != p) {
      setState(() => _mascotLookProgress = p);
    }
  }

  void _onFocusChanged() {
    if (_isLoading) return;
    if (_passwordFocus.hasFocus || _confirmPasswordFocus.hasFocus) {
      if (_mascotState != StockyState.coveringEyes) {
        setState(() => _mascotState = StockyState.coveringEyes);
      }
    } else if (_emailFocus.hasFocus) {
      if (_mascotState != StockyState.trackingEmail) {
        setState(() => _mascotState = StockyState.trackingEmail);
      }
    } else {
      if (_mascotState != StockyState.idle && _errorMessage == null) {
        setState(() => _mascotState = StockyState.idle);
      }
    }
  }

  @override
  void dispose() {
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _emailController.removeListener(_onEmailChanged);
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
        _onFocusChanged();
      });
    }
  }

  Future<void> _submit() async {
    _clearError();
    if (!_formKey.currentState!.validate()) return;

    if (_isRegisterMode && !_acceptTerms) {
      setState(() {
        _errorMessage = 'Para crear la cuenta acepta los términos y la política de privacidad.';
      });
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (_isRegisterMode && !_phoneValid) {
      setState(() => _errorMessage = 'Revisa el número de teléfono o déjalo vacío.');
      return;
    }

    if (_isRegisterMode && password != _confirmPasswordController.text.trim()) {
      setState(() {
        _errorMessage = 'Las contraseñas no coinciden.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _mascotState = StockyState.loading;
    });

    try {
      if (_isRegisterMode) {
        await _authRepo.requestRegistrationCode(email);
        if (!mounted) return;
        final code = await _askVerificationCode(email);
        if (code == null) {
          setState(() => _mascotState = StockyState.idle);
          return;
        }
        await _authRepo.completeRegistration(
          email: email,
          code: code,
          password: password,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
        );
      } else {
        await _authRepo.login(email, password);
      }

      if (mounted) {
        setState(() => _mascotState = StockyState.success);
        await Future.delayed(const Duration(milliseconds: 650));
        if (mounted) {
          widget.onLoginSuccess();
        }
      }
    } catch (e) {
      if (mounted) {
        final rawMsg = e.toString().replaceAll('Exception: ', '');
        setState(() {
          _errorMessage = rawMsg;
          _mascotState = StockyState.error;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Pide el código de 6 dígitos enviado al correo para confirmar el registro
  Future<String?> _askVerificationCode(String email) {
    final codeController = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirma tu correo', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enviamos un código de 6 dígitos a $email. Escríbelo para crear tu cuenta.',
              style: TextStyle(color: context.colors.inkMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (value) {
                if (value.trim().length == 6) Navigator.pop(ctx, value.trim());
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final code = codeController.text.trim();
              if (code.length == 6) Navigator.pop(ctx, code);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  void _setMode(bool register) {
    if (_isLoading || register == _isRegisterMode) return;
    setState(() {
      _isRegisterMode = register;
      _errorMessage = null;
      _formKey.currentState?.reset();
    });
  }

  void _openForgotPassword() {
    ForgotPasswordDialog.show(
      context,
      initialEmail: _emailController.text.trim(),
      onPasswordResetSuccess: (email) {
        setState(() {
          _emailController.text = email;
          _passwordController.clear();
          _errorMessage = null;
        });
        _passwordFocus.requestFocus();
        AppToast.showSuccess(context, 'Contraseña lista. Ya puedes ingresar.');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Stocky reacciona a lo que pasa en el formulario
          Center(
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent.withOpacity(0.10)),
              child: Center(
                child: StockyMascot(size: 92, state: _mascotState, lookProgress: _mascotLookProgress),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            _isRegisterMode ? 'Crea tu cuenta' : 'Hola de nuevo',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: c.ink),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            _isRegisterMode
                ? 'Es gratis. Tu inventario queda guardado en la nube.'
                : 'Entra para ver tu inventario y tus ventas.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.4, color: c.inkMuted),
          ),
          const SizedBox(height: AppSpace.xl),
          _AuthModeSwitch(register: _isRegisterMode, onChanged: _setMode),
          const SizedBox(height: AppSpace.xl),

          // Aviso de error
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _errorMessage == null
                ? const SizedBox(width: double.infinity)
                : Container(
                    margin: const EdgeInsets.only(bottom: AppSpace.lg),
                    padding: const EdgeInsets.fromLTRB(AppSpace.md + 2, AppSpace.sm, AppSpace.xs, AppSpace.sm),
                    decoration: BoxDecoration(
                      color: c.dangerSoft,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: c.danger.withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: c.danger, size: 20),
                        const SizedBox(width: AppSpace.sm + 2),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.35),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar aviso',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close_rounded, size: 18, color: c.inkMuted),
                          onPressed: () => setState(() => _errorMessage = null),
                        ),
                      ],
                    ),
                  ),
          ),

          // Campos exclusivos del registro
          if (_isRegisterMode) ...[
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clearError(),
              decoration: InputDecoration(
                labelText: 'Tu nombre',
                hintText: 'José Martínez',
                prefixIcon: Icon(Icons.person_outline_rounded, color: c.inkMuted),
              ),
              validator: (v) {
                if (!_isRegisterMode) return null;
                if (v == null || v.trim().isEmpty) return 'Ingresa tu nombre o apodo comercial';
                if (v.trim().length < 2) return 'El nombre debe tener al menos 2 letras';
                return null;
              },
            ),
            const SizedBox(height: AppSpace.lg),
            PhoneField(
              defaultCountry: deviceCountry(),
              label: 'WhatsApp (opcional)',
              onChanged: (value) {
                _phoneController.text = value.e164 ?? '';
                _phoneValid = value.isValid;
                _clearError();
              },
            ),
            const SizedBox(height: AppSpace.lg),
          ],

          TextFormField(
            controller: _emailController,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            onChanged: (_) => _clearError(),
            decoration: InputDecoration(
              labelText: 'Correo',
              hintText: 'tu@correo.com',
              prefixIcon: Icon(Icons.mail_outline_rounded, color: c.inkMuted),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Ingresa tu correo';
              if (!v.contains('@')) return 'Correo inválido';
              return null;
            },
          ),
          const SizedBox(height: AppSpace.lg),
          TextFormField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            obscureText: _obscurePassword,
            textInputAction: _isRegisterMode ? TextInputAction.next : TextInputAction.done,
            autofillHints: [_isRegisterMode ? AutofillHints.newPassword : AutofillHints.password],
            onChanged: (_) => _clearError(),
            onFieldSubmitted: _isRegisterMode ? null : (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: Icon(Icons.lock_outline_rounded, color: c.inkMuted),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: c.inkMuted,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Ingresa tu contraseña';
              if (v.length < 6) return 'Mínimo 6 caracteres';
              return null;
            },
          ),

          if (!_isRegisterMode)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _openForgotPassword,
                style: TextButton.styleFrom(foregroundColor: _linkColor(c)),
                child: const Text('¿Olvidaste tu contraseña?', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),

          if (_isRegisterMode) ...[
            const SizedBox(height: AppSpace.lg),
            TextFormField(
              controller: _confirmPasswordController,
              focusNode: _confirmPasswordFocus,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onChanged: (_) => _clearError(),
              decoration: InputDecoration(
                labelText: 'Repite la contraseña',
                prefixIcon: Icon(Icons.lock_reset_rounded, color: c.inkMuted),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Confirma tu contraseña';
                return null;
              },
            ),
            const SizedBox(height: AppSpace.md),
            _termsRow(c),
          ],
          const SizedBox(height: AppSpace.xl),
          PrimaryActionButton(
            label: _isLoading
                ? (_isRegisterMode ? 'Creando cuenta…' : 'Ingresando…')
                : (_isRegisterMode ? 'Crear cuenta' : 'Ingresar'),
            icon: _isRegisterMode ? Icons.person_add_alt_1_rounded : Icons.arrow_forward_rounded,
            onPressed: _isLoading ? null : _submit,
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => LegalDocumentScreen.show(context, initialTabIndex: 0),
                style: TextButton.styleFrom(foregroundColor: c.inkMuted, visualDensity: VisualDensity.compact),
                child: const Text('Términos', style: TextStyle(fontSize: 12.5)),
              ),
              Text('·', style: TextStyle(color: c.inkFaint)),
              TextButton(
                onPressed: () => LegalDocumentScreen.show(context, initialTabIndex: 1),
                style: TextButton.styleFrom(foregroundColor: c.inkMuted, visualDensity: VisualDensity.compact),
                child: const Text('Privacidad', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: isWide ? AppSpace.xxl : AppSpace.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              // En pantallas anchas el formulario va en una tarjeta; en el celular, directo sobre el fondo
              child: isWide
                  ? Container(
                      padding: const EdgeInsets.all(AppSpace.xxl),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(AppRadius.sheet),
                        border: Border.all(color: c.line),
                      ),
                      child: AutofillGroup(child: form),
                    )
                  : AutofillGroup(child: form),
            ),
          ),
        ),
      ),
    );
  }

  /// En oscuro el verde de marca se aclara para que los enlaces se lean sobre el fondo
  Color _linkColor(StockealoColors c) =>
      Theme.of(context).brightness == Brightness.dark ? Color.lerp(c.accent, Colors.white, 0.4)! : c.accent;

  Widget _termsRow(StockealoColors c) {
    final linkStyle = TextStyle(fontWeight: FontWeight.w700, color: _linkColor(c), decoration: TextDecoration.underline);
    return Row(
      children: [
        Checkbox(
          value: _acceptTerms,
          onChanged: (val) {
            setState(() => _acceptTerms = val ?? false);
            _clearError();
          },
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 13, height: 1.4, color: c.ink),
              children: [
                const TextSpan(text: 'Acepto los '),
                TextSpan(
                  text: 'términos de uso',
                  style: linkStyle,
                  recognizer: _termsTap,
                ),
                const TextSpan(text: ' y la '),
                TextSpan(
                  text: 'política de privacidad',
                  style: linkStyle,
                  recognizer: _privacyTap,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Selector "Iniciar sesión" / "Crear cuenta"
class _AuthModeSwitch extends StatelessWidget {
  final bool register;
  final ValueChanged<bool> onChanged;

  const _AuthModeSwitch({required this.register, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget option(bool value, String label) {
      final selected = register == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm + 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? c.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.control - 2),
                border: Border.all(color: selected ? c.line : Colors.transparent),
              ),
              child: Text(
                label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? c.ink : c.inkMuted),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.control + 2),
      ),
      child: Row(
        children: [
          option(false, 'Iniciar sesión'),
          option(true, 'Crear cuenta'),
        ],
      ),
    );
  }
}
