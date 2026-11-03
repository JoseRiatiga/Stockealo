import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_shell.dart';
import 'admin_widgets.dart';

/// Portada del panel: las cifras importantes y lo que necesita atención
class AdminSummaryPage extends StatefulWidget {
  final ValueChanged<AdminSection> onOpen;

  const AdminSummaryPage({super.key, required this.onOpen});

  @override
  State<AdminSummaryPage> createState() => _AdminSummaryPageState();
}

class _AdminSummaryPageState extends State<AdminSummaryPage> {
  AdminSummary? _summary;
  AdminConfig? _config;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final admin = ProAdminService.instance;
      final results = await Future.wait([admin.summary(), admin.config()]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as AdminSummary;
        _config = results[1] as AdminConfig;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = _summary;
    final state = AdminLoadState(loading: _loading, error: _error, empty: s == null, emptyText: '', onRetry: _load);
    return AdminPage(
      title: 'Resumen',
      subtitle: 'Cómo va Stockealo hoy',
      onRefresh: _load,
      children: state.blocking
          ? [state]
          : [
              if (_config?.missingPaymentData == true)
                _alert(c, 'Faltan los datos de pago (Nequi y WhatsApp): los clientes no saben a dónde pagar Pro.',
                    'Completar', () => widget.onOpen(AdminSection.config)),
              if (s!.subscriptionsEnding7d > 0)
                _alert(c, '${s.subscriptionsEnding7d} suscripciones vencen en los próximos 7 días.', 'Ver',
                    () => widget.onOpen(AdminSection.subscriptions)),
              LayoutBuilder(
                builder: (context, box) {
                  final columns = box.maxWidth >= 720 ? 3 : 2;
                  final tiles = [
                    _Tile('Cuentas', '${s.usersTotal}', '+${s.users7d} esta semana · +${s.users30d} en 30 días',
                        Icons.people_outline_rounded, () => widget.onOpen(AdminSection.users)),
                    _Tile('Negocios', '${s.businessesTotal}', '${s.businessesPro} con Pro', Icons.store_mall_directory_outlined,
                        null),
                    _Tile('Suscripciones activas', '${s.subscriptionsActive}', '${s.redemptions30d} canjes en 30 días',
                        Icons.workspace_premium_outlined, () => widget.onOpen(AdminSection.subscriptions)),
                    _Tile('Códigos sin usar', '${s.codesUnused}', 'Listos para entregar', Icons.confirmation_number_outlined,
                        () => widget.onOpen(AdminSection.codes)),
                    _Tile('Tiendas', '${s.storesTotal}', '${s.storesLive} publicadas', Icons.storefront_outlined,
                        () => widget.onOpen(AdminSection.stores)),
                  ];
                  final tileWidth = (box.maxWidth - AppSpace.sm * (columns - 1)) / columns;
                  return Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [for (final t in tiles) SizedBox(width: tileWidth, child: _tile(c, t))],
                  );
                },
              ),
            ],
    );
  }

  Widget _alert(StockealoColors c, String text, String action, VoidCallback onTap) => Container(
        margin: const EdgeInsets.only(bottom: AppSpace.md),
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.sm, AppSpace.sm),
        decoration: BoxDecoration(color: c.warningSoft, borderRadius: BorderRadius.circular(AppRadius.card)),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: c.warning),
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text(text, style: TextStyle(color: c.ink))),
            TextButton(onPressed: onTap, child: Text(action)),
          ],
        ),
      );

  Widget _tile(StockealoColors c, _Tile t) => Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: t.onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(t.label, style: TextStyle(fontSize: 13, color: c.inkMuted))),
                    Icon(t.icon, size: 20, color: c.inkFaint),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Text(t.value, style: AppText.amount(context, size: 28, color: c.ink)),
                Text(t.detail, maxLines: 2, style: TextStyle(fontSize: 12, color: c.inkMuted)),
              ],
            ),
          ),
        ),
      );
}

class _Tile {
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final VoidCallback? onTap;

  const _Tile(this.label, this.value, this.detail, this.icon, this.onTap);
}
