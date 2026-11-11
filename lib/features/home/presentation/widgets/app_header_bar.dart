import 'package:flutter/material.dart';

import '../../../../core/design/status_pill.dart';
import '../../../../core/services/data_events.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/theme_mode_button.dart';
import '../../../business/models/business.dart';
import '../../../cash/data/cash_register_repository.dart';
import '../../../cash/models/cash_session.dart';

/// EL encabezado de Stockealo, en el computador y en el celular: título del lugar
/// con su línea de contexto, la caja siempre a la vista, el buscador (Ctrl K), los
/// avisos, claro u oscuro y el botón principal «Nueva venta».
///
/// En el celular ([compact]) va en dos filas: ☰ · título · avisos · tema, y
/// debajo la caja y «Nueva venta».
class AppHeaderBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool compact;
  final Business? business;
  final VoidCallback? onMenuTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onNewSale;
  final VoidCallback? onCashTap;
  final int alertCount;

  const AppHeaderBar({
    super.key,
    required this.title,
    this.subtitle,
    this.compact = false,
    this.business,
    this.onMenuTap,
    this.onSearchTap,
    this.onNotificationsTap,
    this.onNewSale,
    this.onCashTap,
    this.alertCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bell = IconButton(
      tooltip: alertCount > 0 ? '$alertCount avisos' : 'Avisos',
      onPressed: onNotificationsTap,
      style: IconButton.styleFrom(side: BorderSide(color: c.line)),
      icon: Badge(
        isLabelVisible: alertCount > 0,
        label: Text(alertCount > 99 ? '99+' : '$alertCount'),
        child: Icon(Icons.notifications_outlined, size: 20, color: c.inkMuted),
      ),
    );
    final newSale = onNewSale == null
        ? null
        : FilledButton.icon(
            onPressed: onNewSale,
            icon: const Icon(Icons.add_outlined, size: 18),
            label: const Text('Nueva venta'),
          );
    final cash = business == null ? null : CashPill(business: business!, onTap: onCashTap);

    if (compact) {
      return Material(
        color: c.surface,
        child: SafeArea(
          bottom: false,
          child: Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Abrir el menú',
                      onPressed: onMenuTap,
                      style: IconButton.styleFrom(side: BorderSide(color: c.line)),
                      icon: Icon(Icons.menu_outlined, size: 20, color: c.ink),
                    ),
                    const SizedBox(width: AppSpace.sm + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(context)),
                          if (subtitle != null)
                            Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption(context)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Buscar (producto, cliente o función)',
                      onPressed: onSearchTap,
                      icon: Icon(Icons.search_outlined, size: 20, color: c.inkMuted),
                    ),
                    bell,
                    const ThemeModeButton(size: 20),
                  ],
                ),
                if (cash != null || newSale != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    children: [
                      if (cash != null) Expanded(child: Align(alignment: Alignment.centerLeft, child: cash)) else const Spacer(),
                      if (newSale != null) ...[const SizedBox(width: AppSpace.sm), newSale],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl + 4, vertical: AppSpace.md),
      decoration: BoxDecoration(color: c.paper, border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.page(context)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small(context)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.lg),
          if (cash != null) ...[cash, const SizedBox(width: AppSpace.md - 2)],
          Flexible(flex: 2, child: _SearchBox(onTap: onSearchTap)),
          const SizedBox(width: AppSpace.md - 2),
          bell,
          const SizedBox(width: AppSpace.xs),
          const ThemeModeButton(size: 20),
          if (newSale != null) ...[const SizedBox(width: AppSpace.md - 2), newSale],
        ],
      ),
    );
  }
}

/// El buscador del encabezado (abre la paleta: productos, clientes y funciones)
class _SearchBox extends StatelessWidget {
  final VoidCallback? onTap;

  const _SearchBox({this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.control);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Semantics(
        button: true,
        label: 'Buscar producto, cliente o función. Atajo Control K',
        excludeSemantics: true,
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.lineStrong)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: Row(
                  children: [
                    Icon(Icons.search_outlined, size: 18, color: c.inkMuted),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text('Busca producto, cliente o función',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(context, color: c.inkFaint)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.small - 2),
                        border: Border.all(color: c.line),
                      ),
                      child: Text('Ctrl K', style: AppText.caption(context, weight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La caja, siempre a la vista: «● Caja abierta desde 8:05» o «● Caja cerrada».
/// No se muestra si el negocio no usa caja. Se actualiza sola al abrirla,
/// cerrarla o vender.
class CashPill extends StatefulWidget {
  final Business business;
  final VoidCallback? onTap;

  const CashPill({super.key, required this.business, this.onTap});

  @override
  State<CashPill> createState() => _CashPillState();
}

class _CashPillState extends State<CashPill> {
  CashSession? _open;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    DataEvents.instance.cashVersion.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(CashPill old) {
    super.didUpdateWidget(old);
    if (old.business.id != widget.business.id) _load();
  }

  @override
  void dispose() {
    DataEvents.instance.cashVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!widget.business.cashRegisterEnabled) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    final open = await CashRegisterRepository.instance.getOpenSession(widget.business.id);
    if (mounted) {
      setState(() {
        _open = open;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || !widget.business.cashRegisterEnabled) return const SizedBox.shrink();
    final open = _open;
    final label = open == null ? 'Caja cerrada' : 'Caja abierta desde ${TimeOfDay.fromDateTime(open.openedAt).format(context)}';
    return Semantics(
      button: widget.onTap != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: StatusPill(label, tone: open == null ? AppTone.warning : AppTone.success, dot: true),
      ),
    );
  }
}
