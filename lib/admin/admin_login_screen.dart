import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/design/primary_action_button.dart';
import '../core/services/supabase_service.dart';
import '../core/theme/app_tokens.dart';

/// Inicio de sesión del panel de administrador (misma cuenta de Stockealo)
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Escribe tu correo y tu contraseña.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.client!.auth.signInWithPassword(email: email, password: password);
      // El panel aparece solo: _AdminGate escucha el cambio de sesión
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message.toLowerCase().contains('invalid')
            ? 'Correo o contraseña incorrectos.'
            : 'No se pudo iniciar sesión. Inténtalo de nuevo.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo conectar. Revisa tu internet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.all(AppSpace.xl),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: c.line),
              ),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.admin_panel_settings_outlined, size: 40, color: c.accent),
                    const SizedBox(height: AppSpace.md),
                    Text('Stockealo · Administrador',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
                    const SizedBox(height: AppSpace.xs),
                    Text('Solo para cuentas administradoras',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.inkMuted)),
                    const SizedBox(height: AppSpace.xl),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline_rounded)),
                    ),
                    const SizedBox(height: AppSpace.md),
                    TextField(
                      controller: _passwordController,
                      obscureText: _hidePassword,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _signIn(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _hidePassword ? 'Mostrar' : 'Ocultar',
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpace.md),
                      Text(_error!, style: TextStyle(fontSize: 13, color: c.danger)),
                    ],
                    const SizedBox(height: AppSpace.lg),
                    PrimaryActionButton(
                      label: _loading ? 'Entrando…' : 'Entrar',
                      icon: Icons.login_rounded,
                      onPressed: _loading ? null : _signIn,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
