import 'dart:async';
import '../../../../core/widgets/tooltip_cleaner.dart';
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
import '../../navigation/app_pane.dart';
import '../../navigation/app_places.dart';
import '../../../sales/presentation/screens/sell_screen.dart';
import '../../../sales/data/sell_cart.dart';
import '../../../store/presentation/screens/online_store_screen.dart';
import '../widgets/app_header_bar.dart';
import '../widgets/where_things_moved_sheet.dart';
import '../widgets/global_search_dialog.dart';
import '../widgets/notifications_modal.dart';
import '../../../dashboard/presentation/widgets/stocky_floating_button.dart';
import '../../../../core/widgets/sync_banner.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../store/data/store_orders_repository.dart';
import 'package:intl/intl.dart';
import '../../../services/data/appointments_repository.dart';
import '../../../services/models/service_template.dart';
import '../../../team/data/roles_repository.dart';
import '../../../../core/permissions/permissions.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../../team/presentation/widgets/authorization_gate.dart';
import '../../../team/data/authorization_service.dart';
import '../../../services/models/work_schedule.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/security/app_lock.dart';
import '../../../../core/security/app_lock_gate.dart';
import '../widgets/whats_new_sheet.dart';
import '../../../auth/presentation/logout_confirm.dart';

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

  /// Cerrar sesión pregunta antes (0.16.1), desde el menú, Ajustes o fuera de horario
  Future<void> _logout() async {
    if (await LogoutConfirm.ask(context)) {
      AppPane.clear();
      widget.onLogout();
    }
  }

  int _currentIndex = 0;
  final _authRepo = AuthRepository.instance;
  final _businessRepo = BusinessRepository.instance;
  final _teamRepo = TeamRepository.instance;

  Business? _activeBusiness;
  String _userName = 'Comerciante';
  /// El rol de la persona en el negocio activo
  String _realRole = 'OWNER';

  /// El rol con el que se ve la app: el propio o el de «Ver como» (0.15.0)
  String get _userRole => Permissions.viewAs.value ?? _realRole;

  late final AppLifecycleListener _lifecycle;

  /// Web: revisa cada cierto tiempo si se publicó una versión nueva
  Timer? _webUpdateTimer;

  /// Revisa los pedidos de la tienda cada 2 minutos (por si el tiempo real se corta)
  /// y así salen también los recordatorios de 2 horas
  Timer? _ordersTimer;
  bool _webUpdateShown = false;

  @override
  void initState() {
    super.initState();
    // Ctrl K escucha el teclado de toda la app, no un foco que se pierde al volver
    // de otras pantallas (0.16.6, hallazgo 46)
    HardwareKeyboard.instance.addHandler(_onKey);
    AppPlace.request.addListener(_onPlaceRequest);
    Permissions.viewAs.addListener(_onViewAs);
    _loadNavigationContext();
    _checkAppUpdateSilently();
    // Copia diaria de los datos en el celular; sin esperar y sin estorbar si falla.
    // También al volver a la app, por si quedó abierta varios días
    AutoBackupService.instance.runIfDue();
    _refreshPhoneAlerts();
    _lifecycle = AppLifecycleListener(onResume: () {
      AutoBackupService.instance.runIfDue();
      _refreshPhoneAlerts();
      _pullOrders();
      if (kIsWeb) _checkWebUpdate();
    });
    if (kIsWeb) {
      _webUpdateTimer = Timer.periodic(WebUpdateService.checkEvery, (_) => _checkWebUpdate());
    }
    // Con Pro Servicios aparece la pestaña Servicios
    ProService.instance.status.addListener(_onProChanged);
    // Después de actualizar: «Dónde quedó cada cosa» y «Lo nuevo», una sola vez cada uno
    Future.delayed(const Duration(seconds: 2), () async {
      if (mounted) await WhereThingsMovedSheet.showOnce(context);
      if (mounted) await WhatsNewSheet.showOnce(context);
    });
    _ordersTimer = Timer.periodic(const Duration(minutes: 2), (_) => _pullOrders());
    StoreOrdersRepository.instance.unseen.addListener(_onUnseenChanged);
    // En el celular, la primera vez: «Activa los avisos» (0.13.5)
    Future.delayed(const Duration(seconds: 3), _askForAlerts);
  }

  void _onUnseenChanged() {
    if (mounted) setState(() {});
  }

  /// Baja los pedidos nuevos de la tienda; avisa de los nuevos y de los que esperan
  Future<void> _pullOrders() async {
    final biz = _activeBusiness;
    if (biz == null) return;
    await StoreOrdersRepository.instance.pull(biz.id);
    await AppointmentsRepository.instance.pullOnline(biz.id);
  }

  /// Conecta los avisos de pedidos con la campana y el celular (una vez por negocio)
  void _wireOrderAlerts(String businessId) {
    OrderAlerts.onNewOrder = (o) {
      final total = CurrencyFormatter.format(o.total);
      NotificationService.instance.addNotification(
        title: 'Nuevo pedido ${o.code}',
        message: '${o.name ?? 'Un cliente'} · $total. Ábrelo en Ventas › Cotizaciones.',
        type: NotificationType.order,
        data: {'business_id': businessId, 'quotation_id': o.id},
      );
      PhoneAlertsService.instance.showStoreOrder(id: o.id, code: o.code, name: o.name, total: total);
    };
    OrderAlerts.onReminder = (o) {
      NotificationService.instance.addNotification(
        title: '${o.name ?? 'Un cliente'} sigue esperando',
        message: 'El pedido ${o.code} lleva más de 2 horas sin abrir.',
        type: NotificationType.order,
        data: {'business_id': businessId, 'quotation_id': o.id},
      );
      PhoneAlertsService.instance.showOrderReminder(id: o.id, code: o.code, name: o.name);
    };
    // Reserva en línea nueva: campana y celular («Nueva reserva de Ana · sáb 3:00 p. m.»)
    AppointmentsRepository.onNewBooking = (a) {
      final when = DateFormat("EEE d, h:mm a", 'es_CO').format(a.startsAt);
      NotificationService.instance.addNotification(
        title: 'Nueva reserva de ${a.customerName}',
        message: '$when · ${a.serviceNames}. Confírmala en Servicios › Agenda.',
        type: NotificationType.order,
        data: {'business_id': businessId, 'appointment_id': a.id},
      );
      PhoneAlertsService.instance.showBooking(id: a.id, name: a.customerName, when: when, services: a.serviceNames);
    };
    NotificationService.instance.onStoreOrder = () async {
      await StoreOrdersRepository.instance.pull(businessId);
      await AppointmentsRepository.instance.pullOnline(businessId);
    };
  }

  /// La primera vez en el celular: explica los avisos y pide el permiso del sistema.
  /// Si la persona dice que no, no se vuelve a preguntar (queda en Ajustes › Avisos).
  Future<void> _askForAlerts() async {
    final alerts = PhoneAlertsService.instance;
    if (!mounted || !alerts.isSupported || await alerts.promptShown()) return;
    await alerts.setPromptShown();
    if (await alerts.hasPermission() || !mounted) return;
    final yes = await AppDialog.show<bool>(
      context: context,
      icon: Icons.notifications_active_outlined,
      title: 'Activa los avisos',
      subtitle: 'Para no perderte nada de tu negocio:',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in const [
            'Cuando llegue un pedido de tu tienda en línea',
            'Cuando un producto llegue a su mínimo',
            'El resumen de cómo te fue en el día',
            'Cuando toque cobrar un fiado o pase un proveedor',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: context.colors.accent),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(t, style: AppText.body(context))),
                ],
              ),
            ),
          const SizedBox(height: AppSpace.xs),
          Text('Puedes apagar cada uno cuando quieras en Ajustes › Avisos.', style: AppText.small(context)),
        ],
      ),
      actions: [
        Builder(builder: (ctx) => TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ahora no'))),
        Builder(builder: (ctx) => FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Activar avisos'))),
      ],
    );
    if (yes == true) await alerts.ensurePermission();
  }

  void _onProChanged() {
    if (mounted) setState(() {});
  }

  /// Prepara los avisos del celular y pone al día el resumen programado
  Future<void> _refreshPhoneAlerts() async {
    final alerts = PhoneAlertsService.instance;
    await alerts.init();
    await alerts.seedDefaults();
    await alerts.refreshDailySummary();
    await alerts.refreshCashReminder();
    await alerts.refreshDebtReminders();
    await alerts.refreshVisitReminders();
  }

  // Horario de acceso (0.15.0, Pro Servicios): fuera de horario la app se bloquea
  WorkSchedule? _accessSchedule;
  Timer? _accessTimer;
  String? _accessWarned;

  bool get _outOfHours =>
      _accessSchedule != null &&
      Permissions.viewAs.value == null &&
      _accessSchedule!.stateAt(DateTime.now()) != ShiftState.during;

  void _watchAccess(WorkSchedule? schedule) {
    _accessTimer?.cancel();
    _accessSchedule = schedule;
    if (schedule == null) return;
    // Cada minuto: aviso 10 minutos antes de que termine y bloqueo al terminar
    _accessTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final shift = schedule.on(now);
      final minute = now.hour * 60 + now.minute;
      final key = '${now.year}-${now.month}-${now.day}';
      if (shift != null && minute >= shift.end - 10 && minute < shift.end && _accessWarned != key) {
        _accessWarned = key;
        AppToast.showWarning(context, 'Tu horario termina a las ${ShiftTime.clock(shift.end)}. Termina lo que estás haciendo.');
      }
      setState(() {});
    });
  }

  RealtimeChannel? _authChannel;
  final Set<String> _authShown = {};

  void _wireAuthorizations(String businessId, String role) {
    _authChannel?.unsubscribe();
    _authChannel = null;
    if (!Permissions.can(role, Perm.authorize)) return;
    final service = AuthorizationService.instance;
    void prompt(AuthRequest r) {
      if (!mounted || r.requestedBy == service.myUserId || !_authShown.add(r.id)) return;
      AuthorizationPrompt.show(context, r);
    }

    _authChannel = service.listen(businessId, prompt);
    // Las que llegaron con la app cerrada y siguen esperando
    service.pendingFor(businessId).then((list) => list.forEach(prompt)).catchError((_) {});
  }

  /// Empieza o termina «Ver como»: se redibuja todo con ese rol
  void _onViewAs() {
    if (!mounted) return;
    // «Ver como»: lo abierto en el panel era del rol de antes
    AppPane.clear();
    setState(() {});
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    AppPlace.request.removeListener(_onPlaceRequest);
    Permissions.viewAs.removeListener(_onViewAs);
    _authChannel?.unsubscribe();
    _accessTimer?.cancel();
    _lifecycle.dispose();
    _webUpdateTimer?.cancel();
    _ordersTimer?.cancel();
    StoreOrdersRepository.instance.unseen.removeListener(_onUnseenChanged);
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
        // Roles del negocio (0.15.0): antes de leer el de la persona
        await RolesRepository.instance.apply(biz.id);
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
        ProService.instance.refresh(biz.id).then((_) => PhoneAlertsService.instance.refreshDebtReminders());
        // Pedidos de la tienda: aviso al llegar y número en Ventas (0.13.5)
        _wireOrderAlerts(biz.id);
        StoreOrdersRepository.instance.pull(biz.id);
        // Autorizaciones (0.15.0): a quien puede autorizar le llegan al instante
        _wireAuthorizations(biz.id, role);
        // Horario de acceso (0.15.0)
        _watchAccess(await _teamRepo.myAccessSchedule(businessId: biz.id, userId: user.id, userEmail: user.email));
        AppointmentsRepository.instance.pullOnline(biz.id);
      }
      if (mounted) {
        // Otro negocio: lo abierto en el panel era del anterior
        if (_activeBusiness?.id != biz?.id) AppPane.clear();
        setState(() {
          _activeBusiness = biz;
          _realRole = role;
          Permissions.current = role;
          // Al cambiar de negocio se sale de «Ver como»
          Permissions.viewAs.value = null;
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

  Future<void> _navigateToTab(int index) async {
    // Lo abierto en el panel se cierra al ir a otro lugar del menú; si tiene cambios
    // sin guardar, esa pantalla pregunta y, si se queda, no se cambia de lugar
    if (!await AppPane.closeAll() || !mounted) return;
    // Al cambiar de lugar no queda ninguna ayuda del mouse pegada (0.16.3)
    TooltipCleaner.clear();
    setState(() {
      _currentIndex = index;
      _opened.add(index);
    });
  }

  /// Servicios se ve con Pro Servicios y, desde la 0.14.0, gratis (hasta 3 empleados)
  /// en los negocios de servicios: los que eligieron un tipo de servicio al crearse o
  /// ya lo usan
  bool get _showServices {
    final b = _activeBusiness;
    return ProService.instance.status.value.services ||
        (b != null && (b.servicesEnabled || ServiceTemplate.suggestedFor(b.icon) != null));
  }

  /// Ajustes › Equipo, donde se agregan las personas que hacen los servicios
  Future<void> _openTeam() async {
    final biz = _activeBusiness;
    if (biz == null) return;
    await AppPane.open(context, (_) => EmployeesScreen(business: biz));
  }

  /// Ctrl K (o Cmd K) abre el buscador si esta pantalla es la de arriba
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyK) return false;
    final keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed && !keys.isMetaPressed) return false;
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    // Nada por encima del bloqueo con PIN ni fuera del horario de acceso
    if (AppLock.instance.locked.value || _outOfHours) return false;
    _openSearch();
    return true;
  }

  void _openSearch() => GlobalSearchDialog.show(
        context,
        businessId: _activeBusiness?.id,
        userRole: _userRole,
        onNavigateToTab: _navigateToTab,
      );

  void _openNotifications() => NotificationsModal.show(context: context, onNavigateToTab: _navigateToTab);

  /// «Nueva venta» del encabezado: lleva a Vender. Si ya se está cobrando algo, esa
  /// cuenta pasa a En espera y queda una vacía (0.16.6, decisión D2, hallazgo 22).
  void _newSale() {
    final cart = SellCart.instance;
    if (_currentIndex == AppPlace.vender && !cart.isEmpty) {
      cart.hold();
      AppToast.showInfo(context, 'La cuenta anterior quedó en espera. Esta es una venta nueva.');
      return;
    }
    _navigateToTab(AppPlace.vender);
  }

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
    // Bloqueo con PIN o huella (0.16.0, fase 6): tapa la app sin cerrarla
    return AppLockGate(
      title: _activeBusiness?.name,
      onUsePassword: () async => widget.onLogout(),
      child: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    // Fuera de su horario de acceso: la app se bloquea hasta su próximo turno
    if (_outOfHours) {
      return _OutOfHours(schedule: _accessSchedule!, businessName: _activeBusiness?.name, onLogout: _logout);
    }
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
            menuBadge: StoreOrdersRepository.instance.unseen.value,
            onMenuTap: () {
              TooltipCleaner.clear();
              _scaffoldKey.currentState?.openDrawer();
            },
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
          onLogout: _logout,
          inDrawer: inDrawer,
          // Pedidos de la tienda sin ver (0.13.5)
          badges: {
            if (StoreOrdersRepository.instance.unseen.value > 0)
              AppPlace.ventas: (count: StoreOrdersRepository.instance.unseen.value, tone: AppTone.info),
          },
        );

    return Focus(
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
                // «Ver como» (0.15.0): franja arriba con «Salir»
                if (Permissions.viewAs.value != null)
                  Positioned(
                    top: AppSpace.sm,
                    left: 0,
                    right: 0,
                    child: Center(child: _ViewAsBanner(role: Permissions.viewAs.value!)),
                  ),
                // Stocky abajo a la derecha (no en Ajustes ni Reportes). En Vender se
                // esconde mientras haya productos en el carrito: no tapa «Cobrar» (0.16.3)
                if (showStocky)
                  Positioned(
                    right: isWide ? AppSpace.xl : AppSpace.lg,
                    bottom: (isWide ? AppSpace.xl : AppSpace.lg) + MediaQuery.of(context).padding.bottom,
                    child: ListenableBuilder(
                      listenable: SellCart.instance,
                      builder: (context, _) => _currentIndex == AppPlace.vender && SellCart.instance.lines.isNotEmpty
                          ? const SizedBox.shrink()
                          : StockyFloatingButton(
                              businessId: _activeBusiness?.id,
                              onNavigateToTab: _navigateToTab,
                              compact: !isWide,
                            ),
                    ),
                  ),
              ],
            );

            if (isWide) {
              return Scaffold(
                key: _scaffoldKey,
                body: Row(
                  children: [
                    menu(inDrawer: false),
                    // Panel (0.16.7): el detalle de un producto, Equipo, etc. se abren
                    // aquí, con el menú a la izquierda
                    Expanded(child: AppPaneHost(home: Column(children: [header(false), Expanded(child: body)]))),
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
    );
  }
}

/// Franja de «Ver como»: recuerda con qué rol se está viendo la app y deja salir
class _ViewAsBanner extends StatelessWidget {
  final String role;
  const _ViewAsBanner({required this.role});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.ink,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, 4, 4, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_outlined, size: 16, color: c.surface),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              child: Text('Estás viendo la app como ${Permissions.labelOf(role)}',
                  overflow: TextOverflow.ellipsis, style: AppText.small(context, weight: FontWeight.w600, color: c.surface)),
            ),
            const SizedBox(width: AppSpace.sm),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: c.surface, visualDensity: VisualDensity.compact),
              onPressed: () => Permissions.viewAs.value = null,
              child: const Text('Salir'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fuera del horario de acceso (0.15.0): qué días y horas puede entrar, y salir
class _OutOfHours extends StatelessWidget {
  final WorkSchedule schedule;
  final String? businessName;
  final VoidCallback onLogout;

  const _OutOfHours({required this.schedule, required this.businessName, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = schedule.on(DateTime.now());
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule_outlined, size: 48, color: c.accent),
                  const SizedBox(height: AppSpace.md),
                  Text('Estás fuera de tu horario', textAlign: TextAlign.center, style: AppText.heading(context)),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    today == null
                        ? 'Hoy no tienes turno${businessName == null ? '' : ' en $businessName'}.'
                        : 'Hoy puedes usar la app de ${today.label}.',
                    textAlign: TextAlign.center,
                    style: AppText.bodyLarge(context, color: c.inkMuted),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text('Tu horario: ${schedule.describe()}', textAlign: TextAlign.center, style: AppText.small(context)),
                  const SizedBox(height: AppSpace.xl),
                  OutlinedButton.icon(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout_outlined, size: 18),
                    label: const Text('Cerrar sesión'),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text('Si necesitas entrar ahora, pídeselo al dueño.', style: AppText.caption(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
