import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/stat_card.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../suppliers/data/supplier_repository.dart';
import '../../../suppliers/models/supplier.dart';
import '../../data/lots_repository.dart';
import '../../models/product.dart';
import '../../models/product_lot.dart';

/// Lotes con vencimiento (0.16.0, fase 2b): pedir la fecha, la lista de lotes del
/// producto, el aviso de Inicio y Stock, y el cambio con el proveedor.

String _date(DateTime d) => DateFormat("d MMM y", 'es_CO').format(d);

/// La pastilla de un lote: «Vencido», «En 18 días», «Al día», «Con el proveedor»…
StatusPill lotPill(ProductLot lot, {DateTime? now}) {
  final at = now ?? DateTime.now();
  return switch (lot.status) {
    ProductLot.expired => const StatusPill('Vencido', tone: AppTone.danger, compact: true),
    ProductLot.returned => const StatusPill('Con el proveedor', tone: AppTone.info, compact: true),
    ProductLot.writtenOff => const StatusPill('Dado de baja', tone: AppTone.neutral, compact: true),
    ProductLot.used => const StatusPill('Vendido', tone: AppTone.neutral, compact: true),
    _ => lot.expiresSoon(at, days: LotsRepository.soonDays)
        ? StatusPill(lot.daysLeft(at) == 0 ? 'Vence hoy' : 'En ${lot.daysLeft(at)} días', tone: AppTone.warning, compact: true)
        : const StatusPill('Al día', tone: AppTone.success, compact: true),
  };
}

/// Pide la fecha de vencimiento (y el lote, opcional) de unas unidades
class LotDatePrompt {
  static Future<({DateTime expiresOn, String? code})?> show(BuildContext context, {required String productName, required int quantity}) async {
    DateTime? picked;
    final code = TextEditingController();
    final ok = await AppSheet.show<bool>(
      context: context,
      title: '¿Cuándo vencen?',
      subtitle: '$quantity × $productName',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined),
              label: Text(picked == null ? 'Elegir la fecha de vencimiento' : 'Vence: ${_date(picked!)}'),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: picked ?? DateTime(now.year + 1, now.month, now.day),
                  firstDate: DateTime(now.year - 2),
                  lastDate: DateTime(now.year + 10),
                  helpText: 'Fecha de vencimiento',
                );
                if (d != null) setLocal(() => picked = d);
              },
            ),
            const SizedBox(height: AppSpace.md),
            TextField(controller: code, decoration: const InputDecoration(labelText: 'Lote (opcional)', hintText: 'Ej.: A2391')),
            const SizedBox(height: AppSpace.lg),
            FilledButton(onPressed: picked == null ? null : () => Navigator.pop(ctx, true), child: const Text('Guardar')),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Después')),
          ],
        ),
      ),
    );
    final c = code.text.trim();
    code.dispose();
    if (ok != true || picked == null) return null;
    return (expiresOn: picked!, code: c.isEmpty ? null : c);
  }
}

/// Lo que se hace con un lote vencido: devolverlo para cambio o darlo de baja
class LotActions {
  static Future<bool> expired(BuildContext context, {required ProductLot lot, required String productName, String? supplierId}) async {
    final choice = await AppSheet.show<String>(
      context: context,
      title: '$productName · ${lot.quantity} vencidos',
      subtitle: 'Venció el ${_date(lot.expiresOn)}${lot.code == null ? '' : ' · lote ${lot.code}'}. Estas unidades ya no se venden.',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.swap_horiz_outlined),
            label: const Text('Devolver al proveedor para cambio'),
            onPressed: () => Navigator.pop(ctx, 'exchange'),
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Dar de baja (no lo cambian)'),
            onPressed: () => Navigator.pop(ctx, 'writeoff'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return false;
    try {
      if (choice == 'writeoff') {
        final yes = await AppDialog.confirm(
          context: context,
          title: 'Dar de baja ${lot.quantity} × $productName',
          message: 'Queda como merma en Actividad y en el reporte de ganancias.',
          confirmText: 'Dar de baja',
          destructive: true,
        );
        if (!yes) return false;
        await LotsRepository.instance.writeOff(lot, productName: productName);
        if (context.mounted) AppToast.showSuccess(context, 'Lote dado de baja.');
        return true;
      }
      final supplier = await _pickSupplier(context, lot.businessId, preferred: supplierId);
      if (!context.mounted) return false;
      final exchange = await LotsRepository.instance.sendToExchange(
        lot,
        productName: productName,
        supplierId: supplier?.id,
        supplierName: supplier?.name,
      );
      if (context.mounted) {
        AppToast.showSuccess(context, 'Quedó pendiente el cambio${supplier == null ? '' : ' con ${supplier.name}'}.');
        await shareExchange(exchange);
      }
      return true;
    } on StateError catch (e) {
      if (context.mounted) AppToast.showWarning(context, e.message);
      return false;
    }
  }

  static Future<Supplier?> _pickSupplier(BuildContext context, String businessId, {String? preferred}) async {
    final suppliers = await SupplierRepository.instance.getSuppliers(businessId);
    if (suppliers.isEmpty || !context.mounted) return null;
    suppliers.sort((a, b) => a.id == preferred ? -1 : (b.id == preferred ? 1 : a.name.compareTo(b.name)));
    return AppSheet.show<Supplier>(
      context: context,
      title: '¿A qué proveedor se lo devuelves?',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in suppliers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.local_shipping_outlined),
              title: Text(s.name),
              trailing: s.id == preferred ? const StatusPill('Su proveedor', tone: AppTone.accent, compact: true) : null,
              onTap: () => Navigator.pop(ctx, s),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Sin proveedor')),
        ],
      ),
    );
  }

  /// Texto para mandarle al proveedor por WhatsApp
  static Future<void> shareExchange(LotExchange e) async {
    try {
      await Share.share(
        'Hola${e.supplierName == null ? '' : ' ${e.supplierName}'}, tengo ${e.quantity} × ${e.productName} vencidos '
        'para cambio. ¿Cuándo pasas a cambiarlos? Gracias.',
      );
    } catch (_) {}
  }

  /// «Llegó el cambio»: pide la fecha del lote nuevo
  static Future<bool> receive(BuildContext context, LotExchange e) async {
    final date = await LotDatePrompt.show(context, productName: e.productName, quantity: e.quantity);
    if (date == null) return false;
    try {
      await LotsRepository.instance.receiveExchange(e, expiresOn: date.expiresOn, code: date.code);
      if (context.mounted) AppToast.showSuccess(context, 'Listo: ${e.quantity} × ${e.productName} volvieron al stock.');
      return true;
    } on StateError catch (err) {
      if (context.mounted) AppToast.showWarning(context, err.message);
      return false;
    }
  }

  /// El proveedor no lo cambió: merma
  static Future<bool> writeOffExchange(BuildContext context, LotExchange e) async {
    final yes = await AppDialog.confirm(
      context: context,
      title: 'El proveedor no lo cambió',
      message: 'Dar de baja ${e.quantity} × ${e.productName}: queda como merma.',
      confirmText: 'Dar de baja',
      destructive: true,
    );
    if (!yes) return false;
    final lot = (await LotsRepository.instance.lotsFor(e.productId)).where((l) => l.id == e.lotId).firstOrNull;
    if (lot == null) return false;
    try {
      await LotsRepository.instance.writeOff(lot, productName: e.productName, exchange: e);
      return true;
    } on StateError catch (err) {
      if (context.mounted) AppToast.showWarning(context, err.message);
      return false;
    }
  }
}

/// Lotes del producto, en su ficha (formulario al editar)
class ProductLotsSection extends StatefulWidget {
  final Product product;
  const ProductLotsSection({super.key, required this.product});

  @override
  State<ProductLotsSection> createState() => _ProductLotsSectionState();
}

class _ProductLotsSectionState extends State<ProductLotsSection> {
  List<ProductLot> _lots = const [];
  int _undated = 0;

  @override
  void initState() {
    super.initState();
    LotsRepository.instance.version.addListener(_load);
    _load(reconcile: true);
  }

  @override
  void dispose() {
    LotsRepository.instance.version.removeListener(_load);
    super.dispose();
  }

  Future<void> _load({bool reconcile = false}) async {
    // Inicio no se cae si la base se cerró mientras cargaba (cerrar sesión, cambiar de cuenta)
    try {
      await _loadNow(reconcile: reconcile);
    } catch (e) {
      debugPrint('Inicio: no se pudo cargar: $e');
    }
  }

  Future<void> _loadNow({bool reconcile = false}) async {
    final repo = LotsRepository.instance;
    if (reconcile) await repo.reconcile(widget.product.businessId);
    final lots = await repo.lotsFor(widget.product.id);
    final undated = await repo.undated(widget.product.id);
    if (!mounted) return;
    setState(() {
      _lots = [
        for (final l in lots)
          if (l.quantity > 0 && l.status != ProductLot.used && l.status != ProductLot.writtenOff) l,
      ];
      _undated = undated;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.product;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Lotes y vencimiento', style: AppText.title(context)),
          const SizedBox(height: AppSpace.xs),
          Text('Al vender se descuenta primero el que vence antes.', style: AppText.small(context, color: c.inkMuted)),
          if (_lots.isEmpty && _undated == 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: Text('Todavía no hay lotes. Se crean al registrar una entrada de mercancía.',
                  style: AppText.body(context, color: c.inkMuted)),
            ),
          for (final l in _lots)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${l.code == null ? 'Lote' : 'Lote ${l.code}'} · ${l.quantity} und.', style: AppText.body(context, weight: FontWeight.w600)),
              subtitle: Text(
                l.status == ProductLot.expired || l.isExpiredOn(DateTime.now())
                    ? 'Venció el ${_date(l.expiresOn)}'
                    : 'Vence el ${_date(l.expiresOn)}',
                style: AppText.small(context),
              ),
              trailing: lotPill(l),
              onTap: l.status == ProductLot.expired
                  ? () async {
                      if (await LotActions.expired(context, lot: l, productName: p.name, supplierId: p.supplierId)) _load();
                    }
                  : null,
            ),
          if (_undated > 0)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('$_undated und. sin fecha', style: AppText.body(context, weight: FontWeight.w600)),
              subtitle: Text('Se venden primero. Ponles fecha para que avisemos antes de que venzan.', style: AppText.small(context)),
              trailing: TextButton(
                onPressed: () async {
                  final d = await LotDatePrompt.show(context, productName: p.name, quantity: _undated);
                  if (d == null) return;
                  await LotsRepository.instance.dateUndated(p.businessId, p.id, quantity: _undated, expiresOn: d.expiresOn, code: d.code);
                  await LotsRepository.instance.reconcile(p.businessId);
                  _load();
                },
                child: const Text('Ponerles fecha'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Aviso de Inicio y Stock: lotes vencidos, por vencer y cambios pendientes
class ExpiryAlert extends StatefulWidget {
  final Business business;
  const ExpiryAlert({super.key, required this.business});

  @override
  State<ExpiryAlert> createState() => _ExpiryAlertState();
}

class _ExpiryAlertState extends State<ExpiryAlert> {
  ({List<ProductLot> expired, List<ProductLot> soon, List<LotExchange> pending})? _a;

  @override
  void initState() {
    super.initState();
    LotsRepository.instance.version.addListener(_load);
    _load(reconcile: true);
  }

  @override
  void dispose() {
    LotsRepository.instance.version.removeListener(_load);
    super.dispose();
  }

  Future<void> _load({bool reconcile = false}) async {
    // Inicio no se cae si la base se cerró mientras cargaba (cerrar sesión, cambiar de cuenta)
    try {
      await _loadNow(reconcile: reconcile);
    } catch (e) {
      debugPrint('Inicio: no se pudo cargar: $e');
    }
  }

  Future<void> _loadNow({bool reconcile = false}) async {
    final repo = LotsRepository.instance;
    if (reconcile) await repo.reconcile(widget.business.id);
    final a = await repo.alerts(widget.business.id);
    if (mounted) setState(() => _a = a);
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (a == null || (a.expired.isEmpty && a.soon.isEmpty && a.pending.isEmpty)) return const SizedBox.shrink();
    String n(int x, String one, String many) => '$x ${x == 1 ? one : many}';
    final title = a.soon.isNotEmpty
        ? '${n(a.soon.length, 'lote vence', 'lotes vencen')} en los próximos ${LotsRepository.soonDays} días'
        : a.expired.isNotEmpty
            ? '${n(a.expired.length, 'lote vencido', 'lotes vencidos')} por cambiar o dar de baja'
            : '${n(a.pending.length, 'cambio pendiente', 'cambios pendientes')} con proveedores';
    final detail = [
      if (a.soon.isNotEmpty && a.expired.isNotEmpty) 'y ${n(a.expired.length, 'ya venció', 'ya vencieron')}',
      if (a.pending.isNotEmpty && (a.soon.isNotEmpty || a.expired.isNotEmpty)) n(a.pending.length, 'cambio pendiente', 'cambios pendientes'),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AttentionRow(
        icon: Icons.event_busy_outlined,
        tone: a.expired.isNotEmpty ? AppTone.danger : AppTone.warning,
        title: title,
        detail: detail.isEmpty ? null : detail[0].toUpperCase() + detail.substring(1),
        pill: 'Ver',
        onTap: () async {
          await ExpirySheet.show(context, business: widget.business);
          _load();
        },
      ),
    );
  }
}

/// Todo lo de vencimientos en una hoja
class ExpirySheet {
  static Future<void> show(BuildContext context, {required Business business}) async {
    final repo = LotsRepository.instance;
    final names = <String, ({String name, String? supplierId})>{};
    Future<({List<ProductLot> expired, List<ProductLot> soon, List<LotExchange> pending})> load() async {
      final a = await repo.alerts(business.id);
      final db = await repo.productNames(business.id);
      names
        ..clear()
        ..addAll(db);
      return a;
    }

    var data = await load();
    if (!context.mounted) return;
    await AppSheet.show<void>(
      context: context,
      title: 'Vencimientos',
      subtitle: 'Lo vencido ya no se vende. Devuélvelo para cambio o dalo de baja.',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final c = ctx.colors;
          Future<void> refresh() async {
            data = await load();
            setLocal(() {});
          }

          Widget label(String t) => Padding(
                padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xs),
                child: SectionLabel(t),
              );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data.expired.isEmpty && data.soon.isEmpty && data.pending.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Text('Todo al día.', textAlign: TextAlign.center, style: AppText.body(ctx, color: c.inkMuted)),
                ),
              if (data.expired.isNotEmpty) label('VENCIDOS'),
              for (final l in data.expired)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${names[l.productId]?.name ?? 'Producto'} · ${l.quantity} und.'),
                  subtitle: Text('Venció el ${_date(l.expiresOn)}${l.code == null ? '' : ' · lote ${l.code}'}'),
                  trailing: lotPill(l),
                  onTap: () async {
                    if (await LotActions.expired(ctx, lot: l, productName: names[l.productId]?.name ?? 'Producto',
                        supplierId: names[l.productId]?.supplierId)) {
                      await refresh();
                    }
                  },
                ),
              if (data.pending.isNotEmpty) label('CAMBIOS PENDIENTES'),
              for (final e in data.pending)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSpace.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('${e.quantity} × ${e.productName}', style: AppText.body(ctx, weight: FontWeight.w600)),
                        Text(
                          '${e.supplierName == null ? 'Sin proveedor' : 'Con ${e.supplierName}'} · desde el ${_date(e.createdAt)}',
                          style: AppText.small(ctx, color: c.inkMuted),
                        ),
                        const SizedBox(height: AppSpace.sm),
                        Wrap(
                          spacing: AppSpace.sm,
                          runSpacing: AppSpace.sm,
                          children: [
                            FilledButton(
                              onPressed: () async {
                                if (await LotActions.receive(ctx, e)) await refresh();
                              },
                              child: const Text('Llegó el cambio'),
                            ),
                            OutlinedButton(onPressed: () => LotActions.shareExchange(e), child: const Text('WhatsApp')),
                            TextButton(
                              onPressed: () async {
                                if (await LotActions.writeOffExchange(ctx, e)) await refresh();
                              },
                              child: const Text('No lo cambió'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (data.soon.isNotEmpty) label('VENCEN PRONTO'),
              for (final l in data.soon)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${names[l.productId]?.name ?? 'Producto'} · ${l.quantity} und.'),
                  subtitle: Text('Vence el ${_date(l.expiresOn)}${l.code == null ? '' : ' · lote ${l.code}'}'),
                  trailing: lotPill(l),
                ),
            ],
          );
        },
      ),
    );
  }
}
