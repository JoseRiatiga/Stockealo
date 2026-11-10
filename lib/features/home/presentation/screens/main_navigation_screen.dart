import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/services/web_update_service.dart';
import '../../../pro/data/pro_service.dart';
import '../../../services/presentation/screens/services_tab.dart';
import '../../../team/presentation/screens/employees_screen.dart';
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
import '../../../reports/presentation/screens/reports_screen.dart';
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
import '../widgets/where_things_moved_sheet.dart';
import '../widgets/global_search_dialog.dart';
import '../widgets/notifications_modal.dart';
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

  /// Web: revisa cada cierto tiempo si se publicó una versión nueva
  Timer? _webUpdateTimer;
  bool _webUpdateShown = false;

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
      if (kIsWeb) _checkWebUpdate();
    });
    if (kIsWeb) {
      _webUpdateTimer = Timer.periodic(WebUpdateService.checkEvery, (_) => _checkWebUpdate());
    }
    // Con Pro Servicios aparece la pestaña Servicios
    ProService.instance.status.addListener(_onProChanged);
    // Después de actualizar: «Dónde quedó cada cosa», una sola vez
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) WhereThingsMovedSheet.showOnce(context);
    });
  }

  void _onProChanged() {
    if (mounted) setState(() {});
  }

  /// Prepara los avisos del celular y pone al día el resumen programado
  Future<void> _refreshPhoneAlerts() async {
    final alerts = PhoneAlertsService.instance;
    await alerts.init();
    await alerts.refreshDailySummary();
    await alerts.refreshDebtReminders();
    await alerts.refreshVisitReminders();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _webUpdateTimer?.cancel();
    ProService.instance.status.removeListener(_onProChanged);
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
        // Estado Pro del negocio: decide si se ve el módulo Servicios (Pro Servicios)
        ProService.instance.refresh(biz.id);
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
      if (kIsWeb) {
        _checkWebUpdate();
        return;
      }
      try {
        final update = await UpdateService.instance.checkForUpdate();
        if (update.hasUpdate && mounted) {
          UpdateDialog.show(context, update);
        }
      } catch (_) {}
    });
  }

  /// Web: si hay una versión publicada más nueva, muestra un aviso fijo arriba
  Future<void> _checkWebUpdate() async {
    if (_webUpdateShown) return;
    final latest = await WebUpdateService.instance.checkForNewVersion();
    if (latest == null || !mounted || _webUpdateShown) return;
    _webUpdateShown = true;
    final c = context.colors;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: c.infoSoft,
        leading: Icon(Icons.system_update_alt_rounded, color: c.info),
        content: Text(
          latest.isEmpty
              ? 'Hay una versión nueva de Stockealo. Toca Actualizar para usarla.'
              : 'Hay una versión nueva de Stockealo ($latest). Toca Actualizar para usarla.',
          style: TextStyle(color: c.ink),
        ),
        actions: [
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              // Se vuelve a ofrecer en la siguiente revisión
              _webUpdateShown = false;
            },
            child: const Text('Más tarde'),
          ),
          FilledButton(
            onPressed: () => WebUpdateService.instance.reloadToLatest(),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  void _navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  /// Números de pantalla: 0 Inicio, 1 Inventario, 2 Ventas, 3 Ajustes, 4 Reportes.
  /// Reportes llegó después: se muestra antes de Ajustes sin cambiar los números
  /// que ya usan Stocky, las notificaciones y el buscador.
  static const _reportsIndex = 4;

  /// Servicios (solo con Pro Servicios) y «Más», que en el celular abre Reportes y Ajustes
  static const _servicesIndex = 5;
  static const _moreIndex = 6;

  bool get _showReports => ReportsTab.allowed(_userRole);
  bool get _showServices => ProService.instance.status.value.services;

  /// Orden en la barra de abajo: máximo 5 pestañas. Con Servicios, Reportes y
  /// Ajustes pasan a «Más».
  List<int> get _tabOrder => _showServices
      ? [0, 2, _servicesIndex, 1, _moreIndex]
      : [0, 1, 2, if (_showReports) _reportsIndex, 3];

  static const _tabInfo = <int, (IconData, IconData, String)>{
    0: (Icons.dashboard_outlined, Icons.dashboard_rounded, 'Inicio'),
    1: (Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Inventario'),
    2: (Icons.point_of_sale_outlined, Icons.point_of_sale_rounded, 'Ventas'),
    3: (Icons.settings_outlined, Icons.settings_rounded, 'Ajustes'),
    _reportsIndex: (Icons.insert_chart_outlined_rounded, Icons.insert_chart_rounded, 'Reportes'),
    _servicesIndex: (Icons.view_kanban_outlined, Icons.view_kanban_rounded, 'Servicios'),
    _moreIndex: (Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'Más'),
  };

  /// «Más»: Reportes y Ajustes, con texto
  Future<void> _openMore() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final i in [if (_showReports) _reportsIndex, 3])
              ListTile(
                leading: Icon(_tabInfo[i]!.$1),
                title: Text(_tabInfo[i]!.$3),
                onTap: () => Navigator.pop(ctx, i),
              ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
    if (picked != null) _navigateToTab(picked);
  }

  /// Ajustes › Equipo, donde se agregan las personas que hacen los servicios
  Future<void> _openTeam() async {
    final biz = _activeBusiness;
    if (biz == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeesScreen(business: biz)));
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
      ReportsTab(userRole: _userRole),
      _showServices
          ? ServicesTab(business: _activeBusiness, userRole: _userRole, onOpenTeam: _openTeam)
          : const SizedBox.shrink(),
    ];
    // Si la cuenta deja de poder ver Reportes o Servicios, vuelve a Inicio
    if (_currentIndex == _reportsIndex && !_showReports) _currentIndex = 0;
    if (_currentIndex == _servicesIndex && !_showServices) _currentIndex = 0;
    final order = _tabOrder;

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
                      showServices: _showServices,
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
                                  _reportsIndex => 'Reportes',
                                  _servicesIndex => 'Servicios',
                                  _ => 'Ajustes',
                                },
                                subtitle: switch (_currentIndex) {
                                  0 => 'Resumen de hoy',
                                  1 => 'Productos, stock y precios',
                                  2 => 'Historial, clientes y cotizaciones',
                                  _reportsIndex => 'Ganancias y descargas en Excel',
                                  _servicesIndex => 'Tablero, asistencia, historial y precios',
                                  _ => 'Haz que la app sea tuya',
                                },
                                alertCount: NotificationService.instance.unreadCount,
                                onNotificationsTap: () => NotificationsModal.show(
                                  context: context,
                                  onNavigateToTab: _navigateToTab,
                                ),
                                onSearchTap: () => GlobalSearchDialog.show(
                                  context,
                                  businessId: _activeBusiness?.id,
                                  userRole: _userRole,
                                  onNavigateToTab: _navigateToTab,
                                ),
                              );
                            },
                          ),
                          Expanded(
                            child: Stack(
                              children: [
                                IndexedStack(
                                  index: _currentIndex,
                                  children: screens,
                                ),
                                // Stocky abajo a la derecha, igual que en el celular (arriba pasaba desapercibido)
                                if (_currentIndex != 3 && _currentIndex != _reportsIndex)
                                  Positioned(
                                    right: AppSpace.xl,
                                    bottom: AppSpace.xl,
                                    child: StockyFloatingButton(
                                      businessId: _activeBusiness?.id,
                                      onNavigateToTab: _navigateToTab,
                                    ),
                                  ),
                              ],
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
            final showStockyFab = _currentIndex != 3 && _currentIndex != _reportsIndex;
            // Inventario y Ventas tienen su botón principal a la izquierda en la misma fila.
            // En celulares angostos no caben los dos: Stocky sube una fila para no taparlo
            final hasPrimaryButton = _currentIndex == 1 || _currentIndex == 2 || _currentIndex == _servicesIndex;
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
                    // Reportes y Ajustes se marcan en «Más» cuando están dentro de él
                    selectedIndex: (order.contains(_currentIndex)
                            ? order.indexOf(_currentIndex)
                            : order.indexOf(_moreIndex))
                        .clamp(0, order.length - 1),
                    onDestinationSelected: (i) => order[i] == _moreIndex ? _openMore() : _navigateToTab(order[i]),
                    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                    destinations: [
                      for (final i in order)
                        NavigationDestination(
                          icon: Icon(_tabInfo[i]!.$1),
                          selectedIcon: Icon(_tabInfo[i]!.$2),
                          label: _tabInfo[i]!.$3,
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
