import 'package:flutter/material.dart';
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
import '../../../../core/widgets/update_dialog.dart';
import '../widgets/app_sidebar_pro.dart';
import '../widgets/app_header_bar.dart';

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

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final _authRepo = AuthRepository.instance;
  final _businessRepo = BusinessRepository.instance;
  final _teamRepo = TeamRepository.instance;

  Business? _activeBusiness;
  String _userName = 'Comerciante';
  String _userRole = 'OWNER';

  @override
  void initState() {
    super.initState();
    _loadNavigationContext();
    _businessRepo.activeBusinessNotifier.addListener(_loadNavigationContext);
    _checkAppUpdateSilently();
  }

  @override
  void dispose() {
    _businessRepo.activeBusinessNotifier.removeListener(_loadNavigationContext);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
      ),
      const SalesHistoryScreen(
        businessId: null,
      ),
      ProfileScreen(
        onLogout: widget.onLogout,
      ),
    ];

    return LayoutBuilder(
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
                      AppHeaderBar(
                        title: _currentIndex == 0
                            ? (_activeBusiness?.name ?? 'Stockealo Pro')
                            : (_currentIndex == 1
                                ? 'Catálogo de Inventario'
                                : (_currentIndex == 2 ? 'Historial de Ventas' : 'Ajustes y Configuración')),
                        subtitle: _currentIndex == 0
                            ? 'Bento Dashboard Operativo en Tiempo Real'
                            : 'Gestión Comercial Inteligente',
                        onQuickSale: () => _navigateToTab(2),
                        onSearchTap: () => _navigateToTab(1),
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
        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: screens,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _navigateToTab,
            backgroundColor: isDark ? const Color(0xFF131127) : Colors.white,
            elevation: 3,
            indicatorColor: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard, color: Color(0xFF059669)),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2, color: Color(0xFF059669)),
                label: 'Inventario',
              ),
              NavigationDestination(
                icon: Icon(Icons.point_of_sale_outlined),
                selectedIcon: Icon(Icons.point_of_sale, color: Color(0xFF059669)),
                label: 'Ventas',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings, color: Color(0xFF059669)),
                label: 'Ajustes',
              ),
            ],
          ),
        );
      },
    );
  }
}
