import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/services/web_update_service.dart';
import '../../../pro/data/pro_service.dart';
import '../../../services/presentation/screens/services_tab.dart';
import '../../../team/presentation/screens/employees_screen.dart';
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
import '../widgets/app_menu.dart';
import '../places/places.dart';
import '../../navigation/app_places.dart';
import '../../../sales/presentation/screens/sell_screen.dart';
import '../../../store/presentation/screens/online_store_screen.dart';
import '../widgets/app_header_bar.dart';
import '../widgets/where_things_moved_sheet.dart';
import '../widgets/global_search_dialog.dart';
import '../widgets/notifications_modal.dart';
import '../../../dashboard/presentation/widgets/stocky_floating_button.dart';
import '../../../../core/widgets/sync_banner.dart';

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
    AppPlace.request.addListener(_onPlaceRequest);
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
    AppPlace.request.removeListener(_onPlaceRequest);
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
        leading: Icon(Icons.system_update_alt_outlined, color: c.info),
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

  /// Lugares que ya se abrieron: se construyen la primera vez y luego conservan su estado
  final Set<int> _opened = {AppPlace.inicio};

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Otra pantalla pidió ir a un lugar (por ejemplo, «Vender» desde un producto)
  void _onPlaceRequest() {
    final id = AppPlace.request.value;
    if (id == null || !mounted) return;
    AppPlace.request.value = null;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _navigateToTab(id);
  }

  void _navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
      _opened.add(index);
    });
  }

  bool get _showServices => ProService.instance.status.value.services;

  /// Ajustes › Equipo, donde se agregan las personas que hacen los servicios
  Future<void> _openTeam() async {
    final biz = _activeBusiness;
    if (biz == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeesScreen(business: biz)));
  }

  void _openSearch() => GlobalSearchDialog.show(
        context,
        businessId: _activeBusiness?.id,
        userRole: _userRole,
        onNavigateToTab: _navigateToTab,
      );

  void _openNotifications() => NotificationsModal.show(context: context, onNavigateToTab: _navigateToTab);

  /// «Nueva venta» del encabezado: lleva a Vender
  void _newSale() => _navigateToTab(AppPlace.vender);

  /// El lugar con ese número. Todos se identifican con el número de [AppPlace].
  Widget _placeBody(int id) => switch (id) {
        AppPlace.inicio => DashboardScreen(
            userId: widget.userId,
            onNavigateToTab: _navigateToTab,
            onLogout: widget.onLogout,
          ),
        AppPlace.vender => _activeBusiness == null
            ? const SizedBox.shrink()
            : SellScreen(key: ValueKey('sell-${_activeBusiness!.id}'), business: _activeBusiness!, role: _userRole),
        AppPlace.ventas => SalesHistoryScreen(businessId: null, userRole: _userRole),
        AppPlace.caja => CashPlace(business: _activeBusiness, role: _userRole),
        AppPlace.servicios => _showServices
            ? ServicesTab(business: _activeBusiness, userRole: _userRole, onOpenTeam: _openTeam)
            : const SizedBox.shrink(),
        AppPlace.productos => ProductsListScreen(
            userId: widget.userId,
            onLogout: widget.onLogout,
            userRole: _userRole,
            onOpenStock: () => _navigateToTab(AppPlace.stock),
          ),
        AppPlace.stock => ProductsListScreen(
            userId: widget.userId,
            onLogout: widget.onLogout,
            userRole: _userRole,
            mode: ProductsListMode.stock,
          ),
        AppPlace.personas => PeoplePlace(business: _activeBusiness, role: _userRole),
        AppPlace.tienda => _activeBusiness == null
            ? const SizedBox.shrink()
            : OnlineStoreScreen(key: ValueKey('store-${_activeBusiness!.id}'), business: _activeBusiness!, embedded: true),
        AppPlace.reportes => ReportsTab(userRole: _userRole),
        _ => ProfileScreen(onLogout: widget.onLogout),
      };

  static const _allPlaces = [
    AppPlace.inicio, AppPlace.productos, AppPlace.ventas, AppPlace.ajustes, AppPlace.reportes, AppPlace.servicios,
    AppPlace.vender, AppPlace.caja, AppPlace.stock, AppPlace.personas, AppPlace.tienda,
  ];

  @override
  Widget build(BuildContext context) {
    // Si la persona deja de poder ver el lugar (rol o plan), vuelve a Inicio
    final place = AppPlace.byId(_currentIndex);
    if (_currentIndex != AppPlace.ajustes && !place.visibleFor(role: _userRole, services: _showServices)) {
      _currentIndex = AppPlace.inicio;
    }
    final current = AppPlace.byId(_currentIndex);
    final stack = IndexedStack(
      index: _allPlaces.indexOf(_currentIndex),
      children: [
        for (final id in _allPlaces) _opened.contains(id) ? _placeBody(id) : const SizedBox.shrink(),
      ],
    );
    final showStocky = _currentIndex != AppPlace.ajustes && _currentIndex != AppPlace.reportes;
    final title = _currentIndex == AppPlace.inicio ? (_activeBusiness?.name ?? 'Inicio') : current.label;

    Widget header(bool compact) => AnimatedBuilder(
          animation: NotificationService.instance,
          builder: (context, _) => AppHeaderBar(
            title: title,
            subtitle: current.subtitle,
            compact: compact,
            business: _activeBusiness,
            alertCount: NotificationService.instance.unreadCount,
            onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
            onSearchTap: _openSearch,
            onNotificationsTap: _openNotifications,
            onNewSale: _newSale,
            onCashTap: () => _navigateToTab(AppPlace.caja),
          ),
        );

    AppMenu menu({required bool inDrawer}) => AppMenu(
          selectedId: _currentIndex,
          onSelect: (id) {
            if (inDrawer) Navigator.of(context).maybePop();
            _navigateToTab(id);
          },
          business: _activeBusiness,
          userName: _userName,
          userRole: _userRole,
          services: _showServices,
          onSelectBusiness: () {
            if (inDrawer) Navigator.of(context).maybePop();
            _handleSelectBusiness();
          },
          onLogout: widget.onLogout,
          inDrawer: inDrawer,
        );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openSearch,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 850;
            final body = Stack(
              children: [
                stack,
                // Aviso de la nube: sin conexión o cambios con error (abajo al centro-izquierda)
                Positioned(
                  left: isWide ? AppSpace.xl : AppSpace.md,
                  right: isWide ? 260 : 96,
                  bottom: (isWide ? AppSpace.xl : AppSpace.lg) + MediaQuery.of(context).padding.bottom,
                  child: const Align(alignment: Alignment.bottomLeft, child: SyncBanner()),
                ),
                // Stocky abajo a la derecha (no en Ajustes ni Reportes)
                if (showStocky)
                  Positioned(
                    right: isWide ? AppSpace.xl : AppSpace.lg,
                    // Productos y Clientes y proveedores tienen su botón abajo a la derecha: Stocky va encima
                    bottom: (isWide ? AppSpace.xl : AppSpace.lg) +
                        MediaQuery.of(context).padding.bottom +
                        (_currentIndex == AppPlace.productos || _currentIndex == AppPlace.personas ? 72 : 0),
                    child: StockyFloatingButton(businessId: _activeBusiness?.id, onNavigateToTab: _navigateToTab),
                  ),
              ],
            );

            if (isWide) {
              return Scaffold(
                key: _scaffoldKey,
                body: Row(
                  children: [
                    menu(inDrawer: false),
                    Expanded(child: Column(children: [header(false), Expanded(child: body)])),
                  ],
                ),
              );
            }

            // Celular: el mismo menú, que se abre con ☰ (sin barra de pestañas abajo)
            return Scaffold(
              key: _scaffoldKey,
              drawer: Drawer(width: 304, child: menu(inDrawer: true)),
              body: Column(children: [header(true), Expanded(child: body)]),
            );
          },
        ),
      ),
    );
  }
}
