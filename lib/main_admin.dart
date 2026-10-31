import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin/admin_codes_screen.dart';
import 'admin/admin_login_screen.dart';
import 'core/services/supabase_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_tokens.dart';
import 'features/pro/data/pro_admin_service.dart';

/// Panel de administrador de Stockealo (solo web, en stockealo.online/admin).
/// Es una app aparte: no está dentro de la app de los negocios.
///   flutter run -d chrome -t lib/main_admin.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.instance.initialize();
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stockealo · Administrador',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const _AdminGate(),
    );
  }
}

/// Sin sesión: iniciar sesión. Con sesión: comprueba en el servidor que la cuenta
/// sea administradora antes de mostrar el panel.
class _AdminGate extends StatelessWidget {
  const _AdminGate();

  @override
  Widget build(BuildContext context) {
    final client = SupabaseService.instance.client;
    if (client == null) {
      return const _Message(text: 'No se pudo conectar con el servidor. Recarga la página.');
    }
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, _) {
        final session = client.auth.currentSession;
        if (session == null) return const AdminLoginScreen();
        return FutureBuilder<bool>(
          key: ValueKey(session.user.id),
          future: ProAdminService.instance.isAdmin(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.data != true) {
              return _Message(
                text: 'La cuenta ${session.user.email ?? ''} no es administradora.',
                onSignOut: () => client.auth.signOut(),
              );
            }
            return AdminCodesScreen(
              email: session.user.email ?? '',
              onSignOut: () => client.auth.signOut(),
            );
          },
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final VoidCallback? onSignOut;

  const _Message({required this.text, this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 40, color: c.inkMuted),
              const SizedBox(height: AppSpace.md),
              Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.ink)),
              if (onSignOut != null) ...[
                const SizedBox(height: AppSpace.lg),
                OutlinedButton(onPressed: onSignOut, child: const Text('Cerrar sesión')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
