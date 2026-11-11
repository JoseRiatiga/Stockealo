import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/screens/modules_screen.dart';
import '../../../cash/presentation/screens/cash_register_screen.dart';
import '../../../customers/presentation/screens/customers_screen.dart';
import '../../../suppliers/presentation/screens/suppliers_screen.dart';

/// Lugar «Caja»: abrir, movimientos y cierre. Si el negocio no usa caja, explica
/// para qué sirve y lleva a Módulos para encenderla.
class CashPlace extends StatelessWidget {
  final Business? business;
  final String role;

  const CashPlace({super.key, required this.business, required this.role});

  @override
  Widget build(BuildContext context) {
    final biz = business;
    if (biz == null) return const SizedBox.shrink();
    if (biz.cashRegisterEnabled) {
      return CashRegisterScreen(
        key: ValueKey('cash-place-${biz.id}'),
        businessId: biz.id,
        userName: AuthRepository.instance.currentUser?.displayName ?? '',
        embedded: true,
      );
    }
    final c = context.colors;
    final canEdit = role == 'OWNER' || role == 'ADMIN';
    return ColoredBox(
      color: c.paper,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.point_of_sale_outlined, size: 40, color: c.inkFaint),
                const SizedBox(height: AppSpace.md),
                Text('Tu negocio no usa caja', style: AppText.heading(context)),
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Con la caja anotas con cuánto efectivo empiezas, cada entrada y salida, '
                  'y al cerrar ves si cuadra. Se enciende en Ajustes › Módulos.',
                  textAlign: TextAlign.center,
                  style: AppText.body(context, color: c.inkMuted),
                ),
                if (canEdit) ...[
                  const SizedBox(height: AppSpace.lg),
                  FilledButton(
                    onPressed: () => ModulesScreen.open(context, business: biz, canEdit: true),
                    child: const Text('Encender la caja'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lugar «Clientes y proveedores»: las personas con las que trata el negocio.
/// Clientes (fiados y abonos) para todos; Proveedores solo para dueño y administrador.
class PeoplePlace extends StatelessWidget {
  final Business? business;
  final String role;

  const PeoplePlace({super.key, required this.business, required this.role});

  @override
  Widget build(BuildContext context) {
    final biz = business;
    if (biz == null) return const SizedBox.shrink();
    final managers = role == 'OWNER' || role == 'ADMIN';
    final customers = CustomersScreen(key: ValueKey('people-c-${biz.id}'), businessId: biz.id, embedded: true);
    if (!managers) return customers;
    final c = context.colors;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: c.surface,
            child: TabBar(
              labelColor: c.ink,
              unselectedLabelColor: c.inkMuted,
              indicatorColor: c.accent,
              dividerColor: c.line,
              labelStyle: AppText.body(context, weight: FontWeight.w600),
              tabs: const [Tab(text: 'Clientes y fiados'), Tab(text: 'Proveedores')],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                customers,
                SuppliersScreen(
                  key: ValueKey('people-s-${biz.id}'),
                  business: biz,
                  userName: AuthRepository.instance.currentUser?.displayName,
                  embedded: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
