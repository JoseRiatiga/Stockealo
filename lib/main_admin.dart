import 'package:flutter/material.dart';
import 'core/widgets/tooltip_cleaner.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin/admin_login_screen.dart';
import 'admin/admin_shell.dart';
import 'core/services/supabase_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_tokens.dart';
import 'features/pro/data/pro_admin_service.dart';
import 'core/l10n/app_locale.dart';
import 'core/services/error_reporter.dart';
import 'admin/admin_mfa_gate.dart';

/// Panel de administrador de Stockealo (solo web, en stockealo.online/admin).
/// Es una app aparte: no está dentro de la app de los negocios.
///   flutter run -d chrome -t lib/main_admin.dart
// Errores al panel de administración (0.16.0, fase 5), también los que nadie atrapa (0.16.3)
void main() => ErrorReporter.instance.run('admin', () async {
      // Fechas en español (las pantallas usan DateFormat con 'es_CO')
      await initializeDateFormatting('es_CO', null);
      await SupabaseService.instance.initialize();
      runApp(const AdminApp());
    });

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: AppLocale.locale,
      supportedLocales: AppLocale.supported,
      localizationsDelegates: AppLocale.delegates,
      title: 'Stockealo · Administrador',
      // Las ayudas del mouse no se quedan pegadas al abrir otra cosa (0.16.3)
      navigatorObservers: [TooltipCleaner()],
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

  static String? _checkedFor;
  static Future<bool>? _isAdmin;

  /// «¿Es administradora?», una vez por cuenta (se vuelve a preguntar si cambia)
  static Future<bool> _adminFor(String userId) {
    if (_checkedFor != userId || _isAdmin == null) {
      _checkedFor = userId;
      _isAdmin = ProAdminService.instance.isAdmin();
    }
    return _isAdmin!;
  }

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
          // Una sola consulta por persona: antes cada aviso de la sesión (renovar,
          // dos pasos) volvía a preguntar, rearmaba la verificación y entraba en bucle
          future: _adminFor(session.user.id),
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
            // Verificación en dos pasos obligatoria (0.16.0, fase 6)
            return AdminMfaGate(
              onSignOut: () => client.auth.signOut(),
              child: AdminShell(
                email: session.user.email ?? '',
                onSignOut: () => client.auth.signOut(),
              ),
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
              Icon(Icons.lock_outline, size: 40, color: c.inkMuted),
              const SizedBox(height: AppSpace.md),
              Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.sizeBodyLarge, color: c.ink)),
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
