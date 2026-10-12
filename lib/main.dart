import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/models/app_user.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/business/data/business_repository.dart';
import 'features/business/models/business.dart';
import 'features/business/presentation/screens/create_initial_business_screen.dart';
import 'features/home/presentation/screens/main_navigation_screen.dart';

import 'core/services/supabase_service.dart';
import 'core/theme/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.instance.initialize();
  await ThemeController.instance.initialize();
  // Sincronización automática silenciosa en segundo plano al arrancar la app
  SupabaseService.instance.syncToCloud();
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
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeController.instance.themeMode,
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

class _AuthWrapperState extends State<AuthWrapper> {
  final _authRepo = AuthRepository.instance;
  final _businessRepo = BusinessRepository.instance;
  late Future<AppUser?> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = _authRepo.restoreSession();
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
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF059669)),
            ),
          );
        }

        final currentUser = _authRepo.currentUser;

        // 1. Si no hay usuario autenticado -> Pantalla de Login / Registro
        if (currentUser == null) {
          return LoginScreen(
            onLoginSuccess: _refresh,
          );
        }

        // 2. Si el usuario está autenticado, verificamos si ya tiene al menos una empresa creada
        return FutureBuilder<Business?>(
          future: _businessRepo.getActiveBusiness(currentUser.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Colors.white,
                body: Center(
                  child: CircularProgressIndicator(color: Color(0xFF059669)),
                ),
              );
            }

            final activeBusiness = snapshot.data;

            // Si no tiene ninguna empresa -> Pantalla de bienvenida para crear su primera empresa desde cero
            if (activeBusiness == null) {
              return CreateInitialBusinessScreen(
                userId: currentUser.id,
                onBusinessCreated: _refresh,
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
