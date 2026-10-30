import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/auth_repository.dart';

class ForgotPasswordDialog extends StatefulWidget {
  final String? initialEmail;
  final ValueChanged<String>? onPasswordResetSuccess;

  const ForgotPasswordDialog({
    super.key,
    this.initialEmail,
    this.onPasswordResetSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    String? initialEmail,
    ValueChanged<String>? onPasswordResetSuccess,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ForgotPasswordDialog(
        initialEmail: initialEmail,
        onPasswordResetSuccess: onPasswordResetSuccess,
      ),
    );
  }

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final _authRepo = AuthRepository.instance;

  int _currentStep = 1; // 1: Correo, 2: Código OTP, 3: Nueva contraseña, 4: Éxito
  bool _isLoading = false;
  String? _errorMessage;

  // Paso 1
  late final TextEditingController _emailController;
  final _emailFormKey = GlobalKey<FormState>();

  // Paso 2
  final _otpController = TextEditingController();
  final _otpFormKey = GlobalKey<FormState>();
  Timer? _resendTimer;
  int _resendCountdown = 60;
  bool _canResend = false;

  // Paso 3
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _passwordFormKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  /// La nueva contraseña resultó ser la actual: se ofrece quedarse con ella
  bool _samePasswordNotice = false;

  /// Terminó quedándose con la contraseña actual (cambia el texto del paso 4)
  bool _keptCurrentPassword = false;

  /// La sesión del código verificado se cierra si el paso 3 queda abandonado
  Timer? _sessionTimer;
  static const _sessionTimeout = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    // Si se cerró sin terminar, no dejar abierta la sesión del código verificado
    if (_currentStep != 4) _authRepo.cancelPasswordReset();
    _sessionTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _resendCountdown = 60;
      _canResend = false;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _resendCountdown = 0;
            _canResend = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _resendCountdown--;
          });
        }
      }
    });
  }

  String _translateAuthError(dynamic error) {
    final raw = error.toString().replaceAll('Exception: ', '').trim();
    final msg = raw.toLowerCase();
    if (msg.contains('for security purposes') || (msg.contains('after') && msg.contains('seconds')) || msg.contains('rate limit')) {
      final match = RegExp(r'(\d+)\s*seconds').firstMatch(msg);
      final sec = match != null ? match.group(1) : '15';
      return 'Por seguridad, debes esperar $sec segundos antes de solicitar un nuevo código.';
    }
    if (msg.contains('invalid token') || msg.contains('token has expired') || msg.contains('otp expired') || msg.contains('código inválido')) {
      return 'El código ingresado es incorrecto o ya expiró.';
    }
    if (msg.contains('user not found')) {
      return 'No encontramos ninguna cuenta registrada con este correo.';
    }
    if (msg.contains('network') || msg.contains('socketexception') || msg.contains('failed host lookup')) {
      return 'Error de conexión. Verifica tu internet e inténtalo de nuevo.';
    }
    return raw;
  }

  Future<void> _handleSendOtp() async {
    setState(() => _errorMessage = null);
    if (!_emailFormKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    setState(() => _isLoading = true);

    try {
      await _authRepo.requestPasswordResetOtp(email);
      if (mounted) {
        _startResendTimer();
        setState(() {
          _currentStep = 2;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = _translateAuthError(e);
        });
      }
    }
  }

  Future<void> _handleResendOtp() async {
    if (!_canResend || _isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      await _authRepo.requestPasswordResetOtp(email);
      if (mounted) {
        _startResendTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nuevo código de verificación enviado a tu correo.'),
            backgroundColor: Color(0xFF059669),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _translateAuthError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleVerifyOtp() async {
    setState(() => _errorMessage = null);
    if (!_otpFormKey.currentState!.validate()) return;

    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'El código debe tener exactamente 6 dígitos.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authRepo.verifyPasswordResetCode(email: _emailController.text.trim(), code: code);
      if (!mounted) return;
      _sessionTimer?.cancel();
      _sessionTimer = Timer(_sessionTimeout, () {
        _expireVerification('Pasaron 10 minutos sin terminar. Pide un código nuevo para continuar.');
      });
      setState(() {
        _currentStep = 3;
        _samePasswordNotice = false;
      });
    } catch (e) {
      // El error se muestra en el paso 2, junto al botón de reenviar el código
      if (mounted) setState(() => _errorMessage = _translateAuthError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// La verificación ya no sirve: volver al paso del código y permitir pedir otro
  void _expireVerification(String message) {
    _sessionTimer?.cancel();
    _authRepo.cancelPasswordReset();
    if (!mounted) return;
    setState(() {
      _currentStep = 2;
      _otpController.clear();
      _samePasswordNotice = false;
      _canResend = true;
      _resendTimer?.cancel();
      _errorMessage = message;
    });
  }

  /// Quedarse con la contraseña actual cuando se eligió la misma
  Future<void> _keepCurrentPassword() async {
    setState(() => _isLoading = true);
    await _authRepo.finishPasswordReset(_emailController.text.trim());
    _sessionTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _keptCurrentPassword = true;
      _currentStep = 4;
      _isLoading = false;
      _errorMessage = null;
    });
  }

  Future<void> _handleResetPassword() async {
    setState(() => _errorMessage = null);
    if (!_passwordFormKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final newPassword = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword != confirmPassword) {
      setState(() => _errorMessage = 'Las contraseñas no coinciden.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final changed = await _authRepo.setNewPassword(email: email, newPassword: newPassword);
      if (!mounted) return;
      if (!changed) {
        // Misma contraseña: no es un error; la sesión sigue para elegir otra
        setState(() {
          _samePasswordNotice = true;
          _isLoading = false;
        });
        return;
      }
      _sessionTimer?.cancel();
      setState(() {
        _currentStep = 4;
        _isLoading = false;
        _errorMessage = null;
      });
    } on PasswordResetExpiredException {
      _expireVerification('La verificación venció. Pide un código nuevo para continuar.');
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = _translateAuthError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const primaryColor = Color(0xFF059669);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Encabezado con botón de cerrar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _currentStep == 4
                              ? Icons.check_circle_outline
                              : Icons.lock_reset_rounded,
                          color: primaryColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _currentStep == 4 ? '¡Listo!' : 'Recuperar Clave',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  if (_currentStep != 4)
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Indicador de pasos
              if (_currentStep < 4) ...[
                Row(
                  children: [
                    _buildStepIndicator(1, 'Correo', _currentStep >= 1, isDark),
                    _buildStepDivider(_currentStep >= 2, isDark),
                    _buildStepIndicator(2, 'Código', _currentStep >= 2, isDark),
                    _buildStepDivider(_currentStep >= 3, isDark),
                    _buildStepIndicator(3, 'Nueva Clave', _currentStep >= 3, isDark),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              // Banner de error si existe
              if (_errorMessage != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFCA5A5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Contenido según el paso activo
              if (_currentStep == 1) _buildStep1(isDark, primaryColor),
              if (_currentStep == 2) _buildStep2(isDark, primaryColor),
              if (_currentStep == 3) _buildStep3(isDark, primaryColor),
              if (_currentStep == 4) _buildStep4(isDark, primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label, bool isActive, bool isDark) {
    const primaryColor = Color(0xFF059669);
    final isCurrent = _currentStep == step;

    return Expanded(
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? primaryColor
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            ),
            child: Text(
              '$step',
              style: TextStyle(
                color: isActive
                    ? Colors.white
                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
              color: isCurrent
                  ? (isDark ? Colors.white : const Color(0xFF0F172A))
                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStepDivider(bool isActive, bool isDark) {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 18),
      color: isActive
          ? const Color(0xFF059669)
          : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
    );
  }

  // --- PASO 1: Ingreso de correo ---
  Widget _buildStep1(bool isDark, Color primaryColor) {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ingresa tu correo registrado',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Te enviaremos un código de seguridad de 6 dígitos para verificar tu identidad y restablecer tu clave.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofocus: true,
            onFieldSubmitted: (_) => _handleSendOtp(),
            decoration: InputDecoration(
              labelText: 'Correo Electrónico',
              hintText: 'ejemplo@gmail.com',
              prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF64748B)),
              filled: true,
              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Ingresa tu correo electrónico';
              if (!v.contains('@') || !v.contains('.')) return 'Ingresa un correo válido';
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleSendOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Enviar código de seguridad',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // --- PASO 2: Ingreso de código OTP ---
  Widget _buildStep2(bool isDark, Color primaryColor) {
    final email = _emailController.text.trim();

    return Form(
      key: _otpFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Código de verificación',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                height: 1.4,
              ),
              children: [
                const TextSpan(text: 'Escribe el código de seguridad enviado a:\n'),
                TextSpan(
                  text: email,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autofocus: true,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 8,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '• • • • • •',
              hintStyle: TextStyle(
                color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                letterSpacing: 8,
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Ingresa el código de seguridad';
              if (v.trim().length != 6) {
                return 'El código debe tener exactamente 6 dígitos';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          // Temporizador de reenvío
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_canResend) ...[
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Text(
                  'Reenviar código en $_resendCountdown s',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ] else ...[
                TextButton.icon(
                  onPressed: _isLoading ? null : _handleResendOtp,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reenviar código ahora'),
                  style: TextButton.styleFrom(
                    foregroundColor: primaryColor,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _currentStep = 1;
                      _errorMessage = null;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_back_rounded,
                          size: 14,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Cambiar correo',
                          style: TextStyle(
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleVerifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Verificar código',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- PASO 3: Nueva contraseña ---
  Widget _buildStep3(bool isDark, Color primaryColor) {
    return Form(
      key: _passwordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Crea tu nueva contraseña',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ingresa tu nueva clave de acceso personal. Se actualizará para todos tus negocios.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofocus: true,
            onChanged: (_) {
              if (_samePasswordNotice) setState(() => _samePasswordNotice = false);
            },
            decoration: InputDecoration(
              labelText: 'Nueva Contraseña',
              prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF64748B)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: const Color(0xFF94A3B8),
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Ingresa tu nueva contraseña';
              if (v.trim().length < 6) return 'Mínimo 6 caracteres';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: 'Confirmar Nueva Contraseña',
              prefixIcon: const Icon(Icons.lock_reset, color: Color(0xFF64748B)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                  color: const Color(0xFF94A3B8),
                ),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Confirma tu contraseña';
              if (v != _passwordController.text) return 'Las contraseñas no coinciden';
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleResetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Guardar nueva contraseña',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          if (_samePasswordNotice) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.25)),
              ),
              child: const Text(
                'Esa ya es tu contraseña actual. Puedes ingresar con ella o escribir una diferente arriba.',
                style: TextStyle(fontSize: 13, color: Color(0xFF2563EB), height: 1.4),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: _isLoading ? null : _keepCurrentPassword,
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  side: BorderSide(color: primaryColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Usar mi contraseña actual', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- PASO 4: Éxito ---
  Widget _buildStep4(bool isDark, Color primaryColor) {
    final email = _emailController.text.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle_rounded,
            color: primaryColor,
            size: 48,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _keptCurrentPassword ? 'Mantienes tu contraseña' : '¡Contraseña actualizada!',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _keptCurrentPassword
              ? 'Tu correo quedó verificado y tu contraseña no cambió. Ingresa con la que ya usabas.'
              : 'Tu contraseña ha sido restablecida exitosamente. Ahora puedes ingresar con tus nuevas credenciales.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onPasswordResetSuccess?.call(email);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'Ir a Iniciar Sesión',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
