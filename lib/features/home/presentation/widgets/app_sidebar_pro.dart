import 'package:flutter/material.dart';
import '../../../business/models/business.dart';

class AppSidebarPro extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final Business? activeBusiness;
  final String userName;
  final String userRole;
  final VoidCallback onSelectBusiness;
  final VoidCallback onLogout;

  const AppSidebarPro({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.activeBusiness,
    required this.userName,
    required this.userRole,
    required this.onSelectBusiness,
    required this.onLogout,
  });

  @override
  State<AppSidebarPro> createState() => _AppSidebarProState();
}

class _AppSidebarProState extends State<AppSidebarPro> {
  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0E1D) : Colors.white;
    final borderColor = isDark ? const Color(0xFF262046) : const Color(0xFFE2E8F0);
    final width = _isCollapsed ? 76.0 : 236.0;

    final navItems = [
      {'icon': Icons.dashboard_rounded, 'label': 'Dashboard', 'index': 0},
      {'icon': Icons.inventory_2_rounded, 'label': 'Inventario', 'index': 1},
      {'icon': Icons.point_of_sale_rounded, 'label': 'Ventas & POS', 'index': 2},
      {'icon': Icons.tune_rounded, 'label': 'Ajustes', 'index': 3},
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: width,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(right: BorderSide(color: borderColor, width: 1.2)),
      ),
      child: Column(
        children: [
          // Header del Sidebar
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: _isCollapsed ? 12 : 18,
              vertical: 20,
            ),
            child: Row(
              mainAxisAlignment: _isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
              children: [
                if (!_isCollapsed)
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF059669), Color(0xFF10B981)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF059669).withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stockealo',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                              color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Bento Pro Suite',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                IconButton(
                  icon: Icon(
                    _isCollapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
                    size: 20,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                  onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
                  splashRadius: 18,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Selector de Sede / Negocio Activo
          if (!_isCollapsed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: InkWell(
                onTap: widget.onSelectBusiness,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A182F) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF2E2954) : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.business_rounded,
                        size: 16,
                        color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.activeBusiness?.name ?? 'Mi Negocio',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.unfold_more_rounded,
                        size: 16,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),

          // Items de Navegación
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: navItems.map((item) {
                final idx = item['index'] as int;
                final isSelected = widget.selectedIndex == idx;
                final icon = item['icon'] as IconData;
                final label = item['label'] as String;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: InkWell(
                    onTap: () => widget.onItemSelected(idx),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: EdgeInsets.symmetric(
                        horizontal: _isCollapsed ? 0 : 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark
                                ? const Color(0xFF059669).withOpacity(0.18)
                                : const Color(0xFFECFDF5))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? (isDark ? const Color(0xFF10B981).withOpacity(0.4) : const Color(0xFFA7F3D0))
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: _isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: isSelected
                                ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          ),
                          if (!_isCollapsed) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected
                                      ? (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF065F46))
                                      : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                                ),
                              ),
                            ),
                            if (isSelected)
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Footer con Perfil y Rol
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(_isCollapsed ? 10 : 14),
            child: Row(
              mainAxisAlignment: _isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF059669),
                  child: Text(
                    widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : 'U',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                if (!_isCollapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.userName,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.userRole == 'OWNER' ? 'Dueño' : (widget.userRole == 'ADMIN' ? 'Admin' : 'Cajero'),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    tooltip: 'Cerrar Sesión',
                    onPressed: widget.onLogout,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
