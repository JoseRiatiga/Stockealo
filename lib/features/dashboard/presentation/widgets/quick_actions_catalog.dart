import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// Acciones que el usuario puede fijar en "Acciones Rápidas" del panel.
class QuickActionDef {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  const QuickActionDef({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });
}

const List<QuickActionDef> kAvailableQuickActions = [
  QuickActionDef(
    id: 'sell',
    label: 'Vender',
    description: 'Escanear código de barras para venta rápida',
    icon: Icons.qr_code_scanner,
    color: Color(0xFF059669),
  ),
  QuickActionDef(
    id: 'add_product',
    label: 'Producto',
    description: 'Crear un nuevo producto en catálogo',
    icon: Icons.add_box_outlined,
    color: Color(0xFF2563EB),
  ),
  QuickActionDef(
    id: 'customers',
    label: 'Clientes',
    description: 'Gestionar clientes y cuentas por cobrar (fiados)',
    icon: Icons.people_outline_rounded,
    color: Color(0xFFD97706),
  ),
  QuickActionDef(
    id: 'alerts',
    label: 'Alertas',
    description: 'Productos agotados o con bajo inventario',
    icon: Icons.warning_amber_rounded,
    color: Color(0xFFDC2626),
  ),
  QuickActionDef(
    id: 'inventory',
    label: 'Inventario',
    description: 'Ir directo al catálogo completo de stock',
    icon: Icons.inventory_2_outlined,
    color: Color(0xFF0284C7),
  ),
  QuickActionDef(
    id: 'sales_history',
    label: 'Ventas',
    description: 'Historial detallado y recibos',
    icon: Icons.receipt_long_outlined,
    color: Color(0xFF0D9488),
  ),
  QuickActionDef(
    id: 'excel_export',
    label: 'Excel',
    description: 'Exportar catálogo, ventas y clientes en .xlsx',
    icon: Icons.file_download_outlined,
    color: Color(0xFF16A34A),
  ),
  QuickActionDef(
    id: 'profit_report',
    label: 'Reportes',
    description: 'Ganancias y pérdidas por periodo',
    icon: Icons.insights_rounded,
    color: AppPalette.brand,
  ),
  QuickActionDef(
    id: 'catalog_pdf',
    label: 'Catálogo',
    description: 'Generar catálogo PDF de productos en stock',
    icon: Icons.picture_as_pdf_outlined,
    color: Color(0xFFDC2626),
  ),
  QuickActionDef(
    id: 'team',
    label: 'Equipo',
    description: 'Administrar colaboradores y roles',
    icon: Icons.group_outlined,
    color: Color(0xFF7C3AED),
  ),
  QuickActionDef(
    id: 'biz_info',
    label: 'Mi Negocio',
    description: 'Información general y métricas del comercio',
    icon: Icons.storefront_outlined,
    color: Color(0xFF475569),
  ),
];
