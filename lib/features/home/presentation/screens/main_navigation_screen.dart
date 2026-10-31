import '../../../../core/design/glass_surface.dart';
import '../../../../core/services/phone_alerts_service.dart';
import '../../../backup/data/auto_backup_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../business/presentation/active_business_scope.dart';
import '../../../../core/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../products/presentation/screens/products_list_screen.dart';
import '../../../sales/presentation/screens/sales_history_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/data/business_repository.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/widgets/business_selector_modal.dart';
import '../../../team/data/team_repository.dart';
import '../../../../core/services/update_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/widgets/update_dialog.dart';
import '../widgets/app_sidebar_pro.dart';
import '../widgets/app_header_bar.dart';
import '../widgets/global_search_dialog.dart';
import '../widgets/notifications_modal.dart';
import '../../../sales/presentation/widgets/quick_sale_dialog.dart';
import '../../../dashboard/presentation/widgets/stocky_assistant_modal.dart';
import '../../../dashboard/presentation/widgets/stocky_floating_button.dart';

class MainNavigationScreen extends StatefulWidget {
  final String userId;
  final VoidCallback onLogout;

  const MainNavigationScreen({
    super.key,
    required this.userId,
    required this.onLogout,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with ActiveBusinessAware {
  @override
  void onActiveBusinessChanged() => _loadNavigationContext();

  int _currentIndex = 0;
  final _authRepo = AuthRepository.instance;
  final _businessRepo = BusinessRepository.instance;
  final _teamRepo = TeamRepository.instance;

  Business? _activeBusiness;
  String _userName = 'Comerciante';
  String _userRole = 'OWNER';

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _loadNavigationContext();
    _checkAppUpdateSilently();
    // Copia diaria de los datos en el celular; sin esperar y sin estorbar si falla.
    // También al volver a la app, por si quedó abierta varios días
    AutoBackupService.instance.runIfDue();
    _refreshPhoneAlerts();
    _lifecycle = AppLifecycleListener(onResume: () {
      AutoBackupService.instance.runIfDue();
      _refreshPhoneAlerts();
    });
  }

  /// Prepara los avisos del celular y pone al día el resumen programado
  Future<void> _refreshPhoneAlerts() async {
    final alerts = PhoneAlertsService.instance;
    await alerts.init();
    await alerts.refreshDailySummary();
    await alerts.refreshDebtReminders();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    NotificationService.instance.stopRealtimeSalesListening();
    super.dispose();
  }

  Future<void> _loadNavigationContext() async {
    final user = _authRepo.currentUser;
    if (user != null) {
      _userName = user.displayName.isNotEmpty ? user.displayName : user.email.split('@')[0];
      final biz = await _businessRepo.getActiveBusiness(widget.userId, user.email);
      String role = 'OWNER';
      if (biz != null) {
        role = await _teamRepo.getUserRoleInBusiness(
          businessId: biz.id,
          userId: user.id,
          userEmail: user.email,
        );
        // Iniciar escucha de ventas en tiempo real si hay negocio activo
        NotificationService.instance.startRealtimeSalesListening(
          businessId: biz.id,
          onRemoteSale: () => SupabaseService.instance.syncFromCloud(user.id, user.email),
        );
      }
      if (mounted) {
        setState(() {
          _activeBusiness = biz;
          _userRole = role;
        });
      }
    }
  }

  Future<void> _handleSelectBusiness() async {
    final changed = await BusinessSelectorModal.show(
      context,
      userId: widget.userId,
      onLogout: widget.onLogout,
    );
    if (changed == true) {
      _loadNavigationContext();
    }
  }

  void _checkAppUpdateSilently() {
    Future.delayed(const Duration(seconds: 4), () async {
      try {
        final update = await UpdateService.instance.checkForUpdate();
        if (update.hasUpdate && mounted) {
          UpdateDialog.show(context, update);
        }
      } catch (_) {}
    });
  }

  void _navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        userId: widget.userId,
        onNavigateToInventory: () => _navigateToTab(1),
        onNavigateToSales: () => _navigateToTab(2),
        onLogout: widget.onLogout,
      ),
      ProductsListScreen(
        userId: widget.userId,
        onLogout: widget.onLogout,
        userRole: _userRole,
      ),
      SalesHistoryScreen(
        businessId: null,
        userRole: _userRole,
      ),
      ProfileScreen(
        onLogout: widget.onLogout,
      ),
    ];

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          GlobalSearchDialog.show(
            context,
            businessId: _activeBusiness?.id,
            userRole: _userRole,
            onNavigateToTab: _navigateToTab,
          );
        },
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 850;

            if (isWide) {
              return Scaffold(
                body: Row(
                  children: [
                    // Sidebar Pro tipo Bento / Nuxt Suite
                    AppSidebarPro(
                      selectedIndex: _currentIndex,
                      onItemSelected: _navigateToTab,
                      activeBusiness: _activeBusiness,
                      userName: _userName,
                      userRole: _userRole,
                      onSelectBusiness: _handleSelectBusiness,
                      onLogout: widget.onLogout,
                    ),
                    // Área Principal con Header Bar
                    Expanded(
                      child: Column(
                        children: [
                          AnimatedBuilder(
                            animation: NotificationService.instance,
                            builder: (context, _) {
                              return AppHeaderBar(
                                title: switch (_currentIndex) {
                                  0 => _activeBusiness?.name ?? 'Inicio',
                                  1 => 'Inventario',
                                  2 => 'Ventas',
                                  _ => 'Ajustes',
                                },
                                subtitle: switch (_currentIndex) {
                                  0 => 'Resumen de hoy',
                                  1 => 'Productos, stock y precios',
                                  2 => 'Historial, clientes y cotizaciones',
                                  _ => 'Haz que la app sea tuya',
                                },
                                alertCount: NotificationService.instance.unreadCount,
                                onNotificationsTap: () => NotificationsModal.show(
                                  context: context,
                                  onNavigateToTab: _navigateToTab,
                                ),
                                onQuickSale: () => QuickSaleDialog.show(context),
                                onSearchTap: () => GlobalSearchDialog.show(
                                  context,
                                  businessId: _activeBusiness?.id,
                                  userRole: _userRole,
                                  onNavigateToTab: _navigateToTab,
                                ),
                                onStockyAssistantTap: _currentIndex != 3
                                    ? () => StockyAssistantModal.show(
                                          context,
                                          businessId: _activeBusiness?.id,
                                          onNavigateToTab: _navigateToTab,
                                        )
                                    : null,
                              );
                            },
                          ),
                          Expanded(
                            child: IndexedStack(
                              index: _currentIndex,
                              children: screens,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            // Modo Móvil
            final showStockyFab = _currentIndex != 3;
            // Inventario y Ventas tienen su botón principal a la izquierda en la misma fila.
            // En celulares angostos no caben los dos: Stocky sube una fila para no taparlo
            final hasPrimaryButton = _currentIndex == 1 || _currentIndex == 2;
            final liftStocky = hasPrimaryButton && constraints.maxWidth < 400;

            return Scaffold(
              // El contenido pasa por debajo de la barra de cristal
              extendBody: true,
              body: Builder(
                // Este contexto ya incluye el alto de la barra en padding.bottom
                builder: (bodyContext) => Stack(
                  children: [
                    IndexedStack(
                      index: _currentIndex,
                      children: screens,
                    ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      right: AppSpace.lg,
                      bottom: showStockyFab
                          ? MediaQuery.of(bodyContext).padding.bottom + AppSpace.lg + (liftStocky ? 64 : 0)
                          : -80,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: showStockyFab ? 1.0 : 0.0,
                        child: StockyFloatingButton(
                          businessId: _activeBusiness?.id,
                          onNavigateToTab: _navigateToTab,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: SafeArea(
                minimum: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
                child: GlassSurface(
                  borderRadius: BorderRadius.circular(28),
                  child: NavigationBar(
                    height: 64,
                    selectedIndex: _currentIndex,
                    onDestinationSelected: _navigateToTab,
                    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard_rounded),
                        label: 'Inicio',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.inventory_2_outlined),
                        selectedIcon: Icon(Icons.inventory_2_rounded),
                        label: 'Inventario',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.point_of_sale_outlined),
                        selectedIcon: Icon(Icons.point_of_sale_rounded),
                        label: 'Ventas',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings_rounded),
                        label: 'Ajustes',
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
