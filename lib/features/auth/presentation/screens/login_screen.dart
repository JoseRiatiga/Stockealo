import 'package:flutter/material.dart';
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
        _errorMessage = 'Debes aceptar los Términos y Condiciones y la Política de Privacidad.';
      });
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

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
        await _authRepo.register(
          email: email,
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 600;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : (isWide ? const Color(0xFFF1F5F9) : Colors.white),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 24 : 28,
              vertical: isWide ? 40 : 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: isWide ? const EdgeInsets.all(32) : EdgeInsets.zero,
                  decoration: isWide
                      ? BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        )
                      : null,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                  // Mascota Interactiva Stocky
                  StockyMascot(
                    size: 96,
                    state: _mascotState,
                    lookProgress: _mascotLookProgress,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Stockealo',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Control de inventario y ventas para tu negocio',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Selector de Iniciar Sesión / Crear cuenta
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _isRegisterMode = false;
                                _errorMessage = null;
                                _formKey.currentState?.reset();
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: !_isRegisterMode
                                    ? (isDark ? const Color(0xFF334155) : Colors.white)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: !_isRegisterMode
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                                          blurRadius: 4,
                                        )
                                      ]
                                    : null,
                              ),
                              child: Text(
                                'Iniciar Sesión',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: !_isRegisterMode
                                      ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                      : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _isRegisterMode = true;
                                _errorMessage = null;
                                _formKey.currentState?.reset();
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _isRegisterMode
                                    ? (isDark ? const Color(0xFF334155) : Colors.white)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: _isRegisterMode
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                                          blurRadius: 4,
                                        )
                                      ]
                                    : null,
                              ),
                              child: Text(
                                'Crear cuenta',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: _isRegisterMode
                                      ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                      : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Banner animado de Error
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: _errorMessage != null
                        ? AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: _errorMessage != null ? 1.0 : 0.0,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFCA5A5),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFDC2626).withOpacity(0.06),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
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
                                  const SizedBox(width: 4),
                                  InkWell(
                                    onTap: () => setState(() => _errorMessage = null),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.close,
                                        size: 16,
                                        color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  // Campos exclusivos de Registro
                  if (_isRegisterMode) ...[
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => _clearError(),
                      decoration: const InputDecoration(
                        labelText: 'Nombre Completo o Comercial *',
                        hintText: 'Ej. José Martínez o Don José',
                        prefixIcon: Icon(Icons.person_outline, color: Color(0xFF64748B)),
                      ),
                      validator: (v) {
                        if (!_isRegisterMode) return null;
                        if (v == null || v.trim().isEmpty) return 'Ingresa tu nombre o apodo comercial';
                        if (v.trim().length < 2) return 'El nombre debe tener al menos 2 letras';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => _clearError(),
                      decoration: const InputDecoration(
                        labelText: 'Teléfono / WhatsApp (Opcional)',
                        hintText: 'Ej. +57 300 123 4567',
                        prefixIcon: Icon(Icons.phone_outlined, color: Color(0xFF64748B)),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Campo Correo
                  TextFormField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => _clearError(),
                    decoration: const InputDecoration(
                      labelText: 'Correo Electrónico',
                      hintText: 'tu@correo.com',
                      prefixIcon: Icon(Icons.email_outlined, color: Color(0xFF64748B)),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Ingresa tu correo';
                      if (!v.contains('@')) return 'Correo inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Campo Contraseña
                  TextFormField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    obscureText: _obscurePassword,
                    onChanged: (_) => _clearError(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF64748B)),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: const Color(0xFF94A3B8),
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

                  // Enlace de Recuperación de Contraseña (Solo en Modo Iniciar Sesión)
                  if (!_isRegisterMode) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
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
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Contraseña restablecida con éxito. Ya puedes ingresar.'),
                                        backgroundColor: Color(0xFF059669),
                                      ),
                                    );
                                  },
                                );
                              },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          visualDensity: VisualDensity.compact,
                          foregroundColor: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                        ),
                        child: const Text(
                          '¿Olvidaste tu contraseña?',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Confirmar contraseña en registro
                  if (_isRegisterMode) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      focusNode: _confirmPasswordFocus,
                      obscureText: _obscurePassword,
                      onChanged: (_) => _clearError(),
                      decoration: const InputDecoration(
                        labelText: 'Confirmar Contraseña',
                        prefixIcon: Icon(Icons.lock_reset, color: Color(0xFF64748B)),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Confirma tu contraseña';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // Checkbox de Términos y Privacidad
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _acceptTerms,
                            activeColor: const Color(0xFF059669),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            onChanged: (val) {
                              setState(() {
                                _acceptTerms = val ?? false;
                                _clearError();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Acepto los ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                ),
                              ),
                              InkWell(
                                onTap: () => LegalDocumentScreen.show(context, initialTabIndex: 0),
                                child: Text(
                                  'Términos de Uso',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                              Text(
                                ' y la ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                ),
                              ),
                              InkWell(
                                onTap: () => LegalDocumentScreen.show(context, initialTabIndex: 1),
                                child: Text(
                                  'Política de Privacidad',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Botón Principal
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              _isRegisterMode ? 'Crear cuenta' : 'Ingresar',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Enlaces Legales al pie
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      InkWell(
                        onTap: () => LegalDocumentScreen.show(context, initialTabIndex: 0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: Text(
                            'Términos y Condiciones',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        '•',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                      InkWell(
                        onTap: () => LegalDocumentScreen.show(context, initialTabIndex: 1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: Text(
                            'Política de Privacidad',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    ),
  ),
);
  }
}
