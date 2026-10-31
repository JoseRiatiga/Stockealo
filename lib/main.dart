import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/models/app_user.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/business/data/business_repository.dart';
import 'features/business/models/business.dart';
import 'features/business/presentation/active_business_scope.dart';
import 'features/business/presentation/screens/create_initial_business_screen.dart';
import 'features/home/presentation/screens/main_navigation_screen.dart';

import 'core/services/supabase_service.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/presentation/widgets/stockealo_splash_screen.dart';
import 'features/onboarding/presentation/welcome_screen.dart';

/// Bienvenida pendiente en este dispositivo (se decide al arrancar, sin sesión)
bool _showWelcome = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting('es_CO', null);
  } catch (e) {
    debugPrint('Error inicializando formato de fecha: $e');
  }
  await SupabaseService.instance.initialize();
  await ThemeController.instance.initialize();
  _showWelcome = await WelcomeScreen.shouldShow();
  // La sincronización empieza al restaurar o iniciar la sesión (syncFromCloud sube
  // primero los cambios pendientes); subir todo aquí pisaba datos más nuevos.
  runApp(const StockealoApp());
}

class StockealoApp extends StatelessWidget {
  const StockealoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'Stockealo',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.light, accent: ThemeController.instance.accent),
          darkTheme: AppTheme.build(Brightness.dark, accent: ThemeController.instance.accent),
          themeMode: ThemeController.instance.themeMode,
          // Negocio activo disponible para toda la app, incluidos diálogos y rutas
          // y el tamaño de letra elegido en Apariencia, sobre el del teléfono
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final scale = (media.textScaler.scale(1) * ThemeController.instance.textScale).clamp(0.8, 1.8);
            return MediaQuery(
              data: media.copyWith(textScaler: TextScaler.linear(scale)),
              child: ActiveBusinessScope(child: child!),
            );
          },
          home: const AuthWrapper(),
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  final _authRepo = AuthRepository.instance;
  final _businessRepo = BusinessRepository.instance;
  late Future<AppUser?> _sessionFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionFuture = _authRepo.restoreSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a la app, reintentar los cambios que quedaron sin enviar
    if (state == AppLifecycleState.resumed && _authRepo.currentUser != null) {
      SupabaseService.instance.flushPendingSync();
    }
  }

  void _refresh() {
    setState(() {
      _sessionFuture = Future.value(_authRepo.currentUser);
    });
  }

  void _handleLogout() async {
    await _authRepo.logout();
    _businessRepo.setActiveBusiness(null);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: _sessionFuture,
      builder: (context, sessionSnapshot) {
        if (sessionSnapshot.connectionState == ConnectionState.waiting) {
          return const StockealoSplashScreen(statusMessage: 'Verificando sesión...');
        }

        final currentUser = _authRepo.currentUser;

        // 1. Sin sesión: la bienvenida (solo la primera vez en el dispositivo) y luego el login
        if (currentUser == null && _showWelcome) {
          return WelcomeScreen(onDone: () => setState(() => _showWelcome = false));
        }
        if (currentUser == null) {
          return LoginScreen(
            onLoginSuccess: _refresh,
          );
        }

        // 2. Si el usuario está autenticado, verificamos si ya tiene al menos una empresa creada
        return FutureBuilder<Business?>(
          future: _businessRepo.getActiveBusiness(currentUser.id, currentUser.email),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const StockealoSplashScreen(statusMessage: 'Cargando tu negocio...');
            }

            final activeBusiness = snapshot.data;

            // Si no tiene ninguna empresa -> Pantalla de bienvenida para crear su primera empresa desde cero
            if (activeBusiness == null) {
              return CreateInitialBusinessScreen(
                userId: currentUser.id,
                userEmail: currentUser.email,
                userName: currentUser.name,
                onBusinessCreated: _refresh,
                onLogout: _handleLogout,
              );
            }

            // Si tiene empresa activa -> Inicio con Dashboard y Navegación
            return MainNavigationScreen(
              userId: currentUser.id,
              onLogout: _handleLogout,
            );
          },
        );
      },
    );
  }
}
