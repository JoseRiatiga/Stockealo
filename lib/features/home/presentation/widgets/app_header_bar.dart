import 'package:flutter/material.dart';
import '../../../../core/utils/clock_text.dart';

import '../../../../core/design/status_pill.dart';
import '../../../../core/services/data_events.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/theme_mode_button.dart';
import '../../../business/models/business.dart';
import '../../../cash/data/cash_register_repository.dart';
import '../../../cash/models/cash_session.dart';
import '../../../../core/widgets/sync_pill.dart';

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

  /// Número sobre ☰ en el celular (pedidos de la tienda sin ver), para que se abra el menú
  final int menuBadge;
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
    this.menuBadge = 0,
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
                      icon: Badge(
                        isLabelVisible: menuBadge > 0,
                        label: Text(menuBadge > 99 ? '99+' : '$menuBadge'),
                        child: Icon(Icons.menu_outlined, size: 20, color: c.ink),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
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
                      visualDensity: VisualDensity.compact,
                      onPressed: onSearchTap,
                      icon: Icon(Icons.search_outlined, size: 20, color: c.inkMuted),
                    ),
                    // Sin segunda fila, la nube se queda aquí
                    if (cash == null && newSale == null) const SyncPill(iconOnly: true),
                    bell,
                  ],
                ),
                // 0.16.3: la nube baja a la fila de la caja y el botón de tema vive en el
                // menú lateral, para que el nombre del negocio y el subtítulo se lean enteros
                if (cash != null || newSale != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (cash != null) Flexible(child: cash),
                            const SizedBox(width: AppSpace.xs),
                            // La nube (0.16.0): en el celular, solo el ícono con su color
                            const SyncPill(iconOnly: true),
                          ],
                        ),
                      ),
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

    // Computador: el título tiene prioridad (0.16.7, hallazgos 12 y 38: se cortaban
    // el título y el buscador). Bajo 1150 px la nube queda como ícono; bajo 820 px
    // (una ventana de 1024) también el buscador, y «Nueva venta» pasa a «+»
    return LayoutBuilder(builder: (context, box) {
      final roomy = box.maxWidth >= 1150;
      final medium = box.maxWidth >= 820;
      return Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: EdgeInsets.symmetric(horizontal: medium ? AppSpace.xl + 4 : AppSpace.lg, vertical: AppSpace.md),
        decoration: BoxDecoration(color: c.paper, border: Border(bottom: BorderSide(color: c.line))),
        child: Row(
          children: [
            // El título se lleva el doble que el buscador: se lee entero
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
            if (business != null) ...[
              CashPill(business: business!, onTap: onCashTap, short: !medium),
              const SizedBox(width: AppSpace.md - 2),
            ],
            if (medium)
              Flexible(child: _SearchBox(onTap: onSearchTap))
            else
              IconButton(
                tooltip: 'Buscar producto, cliente o función (Ctrl K)',
                onPressed: onSearchTap,
                style: IconButton.styleFrom(side: BorderSide(color: c.lineStrong)),
                icon: Icon(Icons.search_outlined, size: 20, color: c.inkMuted),
              ),
            const SizedBox(width: AppSpace.md - 2),
            SyncPill(iconOnly: !roomy),
            const SizedBox(width: AppSpace.sm),
            bell,
            const SizedBox(width: AppSpace.xs),
            const ThemeModeButton(size: 20),
            if (onNewSale != null) ...[
              const SizedBox(width: AppSpace.md - 2),
              if (medium)
                newSale!
              else
                IconButton.filled(tooltip: 'Nueva venta', onPressed: onNewSale, icon: const Icon(Icons.add_outlined)),
            ],
          ],
        ),
      );
    });
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
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 340),
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
                    // Angosto, dice solo «Buscar» en vez de cortar la frase
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => Text(
                          box.maxWidth >= 230 ? 'Busca producto, cliente o función' : 'Buscar',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(context, color: c.inkFaint),
                        ),
                      ),
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

  /// Sin la hora («Caja abierta»): para encabezados angostos
  final bool short;

  const CashPill({super.key, required this.business, this.onTap, this.short = false});

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
    final full = open == null ? 'Caja cerrada' : 'Caja abierta desde ${clockText(open.openedAt)}';
    // En el celular o con poco ancho, sin la hora para que no se corte (0.16.7, hallazgo 60)
    return LayoutBuilder(builder: (context, box) {
      final label = widget.short || box.maxWidth < 210 ? (open == null ? 'Caja cerrada' : 'Caja abierta') : full;
      return _pill(label, full, open != null);
    });
  }

  Widget _pill(String label, String full, bool isOpen) {
    return Semantics(
      button: widget.onTap != null,
      label: full,
      excludeSemantics: true,
      child: Tooltip(
        message: label == full ? '' : full,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: StatusPill(label, tone: isOpen ? AppTone.success : AppTone.warning, dot: true),
        ),
      ),
    );
  }
}
