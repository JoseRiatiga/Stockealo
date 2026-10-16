import 'package:flutter/material.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../products/presentation/screens/products_list_screen.dart';
import '../../../sales/presentation/screens/sales_history_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../../core/services/update_service.dart';
import '../../../../core/widgets/update_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    _checkAppUpdateSilently();
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
        businessId: null, // usa automáticamente el negocio activo
      ),
      ProfileScreen(
        onLogout: widget.onLogout,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 768;

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: _navigateToTab,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                  indicatorColor: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Stockealo',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard, color: Color(0xFF059669)),
                      label: Text('Inicio'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2, color: Color(0xFF059669)),
                      label: Text('Inventario'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.point_of_sale_outlined),
                      selectedIcon: Icon(Icons.point_of_sale, color: Color(0xFF059669)),
                      label: Text('Ventas'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings, color: Color(0xFF059669)),
                      label: Text('Ajustes'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: IndexedStack(
                        index: _currentIndex,
                        children: screens,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: screens,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _navigateToTab,
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
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
