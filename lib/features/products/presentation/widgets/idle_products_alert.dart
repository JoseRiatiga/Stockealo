import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/stat_card.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/services/data_events.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../business/models/business.dart';
import '../../../home/navigation/app_places.dart';
import '../../../sales/presentation/screens/promotions_screen.dart';
import 'catalog_generator_modal.dart';

/// Un producto quieto: con stock y sin ventas en [IdleProducts.days] días
class IdleProduct {
  final String id;
  final String name;
  final int stock;
  final double cost;
  final DateTime? lastSale;
  const IdleProduct({required this.id, required this.name, required this.stock, required this.cost, this.lastSale});
  double get value => stock * cost;
}

/// Productos quietos (0.16.0, fase 5): tienen stock y no se venden hace 30 días
abstract final class IdleProducts {
  static const days = 30;

  /// Los productos nuevos (de menos de [days] días) no cuentan: no han tenido tiempo
  static Future<List<IdleProduct>> find(String businessId, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final since = at.subtract(const Duration(days: days)).toIso8601String();
    final rows = await (await AppDatabase.instance.database).rawQuery('''
      SELECT p.id, p.name, p.stock, p.purchase_price AS cost, p.created_at,
             (SELECT MAX(s.date) FROM sales_ok s WHERE s.product_id = p.id) AS last_sale
      FROM products p
      WHERE p.business_id = ? AND COALESCE(p.is_active, 1) = 1 AND p.stock > 0 AND p.created_at < ?
        AND NOT EXISTS (SELECT 1 FROM sales_ok s WHERE s.product_id = p.id AND s.date >= ? AND s.quantity > 0)
    ''', [businessId, since, since]);
    final list = [
      for (final r in rows)
        IdleProduct(
          id: r['id'] as String,
          name: r['name'] as String? ?? 'Producto',
          stock: (r['stock'] as num?)?.toInt() ?? 0,
          cost: (r['cost'] as num?)?.toDouble() ?? 0,
          lastSale: DateTime.tryParse('${r['last_sale'] ?? ''}'),
        ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }
}

/// El aviso de Inicio y Stock: «8 productos sin ventas en 30 días · $420.000 quietos»
class IdleProductsAlert extends StatefulWidget {
  final Business business;
  final DateTime? now;
  const IdleProductsAlert({super.key, required this.business, this.now});

  @override
  State<IdleProductsAlert> createState() => _IdleProductsAlertState();
}

class _IdleProductsAlertState extends State<IdleProductsAlert> {
  List<IdleProduct> _idle = const [];

  @override
  void initState() {
    super.initState();
    DataEvents.instance.salesVersion.addListener(_load);
    DataEvents.instance.productsVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    DataEvents.instance.salesVersion.removeListener(_load);
    DataEvents.instance.productsVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    // Inicio no se cae si la base se cerró mientras cargaba (cerrar sesión, cambiar de cuenta)
    try {
      await _loadNow();
    } catch (e) {
      debugPrint('Inicio: no se pudo cargar: $e');
    }
  }

  Future<void> _loadNow() async {
    try {
      final idle = await IdleProducts.find(widget.business.id, now: widget.now);
      if (mounted) setState(() => _idle = idle);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_idle.isEmpty) return const SizedBox.shrink();
    final value = _idle.fold<double>(0, (s, p) => s + p.value);
    final n = _idle.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AttentionRow(
        icon: Icons.inventory_outlined,
        tone: AppTone.warning,
        title: '$n ${n == 1 ? 'producto' : 'productos'} sin ventas en ${IdleProducts.days} días',
        detail: value > 0 ? '${CurrencyFormatter.format(value.round())} quietos a costo' : null,
        pill: 'Ver',
        onTap: () => _sheet(context),
      ),
    );
  }

  Future<void> _sheet(BuildContext context) => AppSheet.show<void>(
        context: context,
        title: 'Productos quietos',
        subtitle: 'Tienen stock y no se venden hace ${IdleProducts.days} días. Prueba moverlos así:',
        builder: (ctx) {
          final c = ctx.colors;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.local_offer_outlined, size: 18),
                    label: const Text('Ponerlos en promoción'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      PromotionsScreen.open(context, business: widget.business);
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.star_outline, size: 18),
                    label: const Text('Destacarlos en la tienda'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      AppPlace.go(AppPlace.tienda);
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Sacarlos en el catálogo'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      CatalogGeneratorModal.show(context: context, business: widget.business);
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              for (final p in _idle.take(40))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(p.lastSale == null ? 'Nunca se ha vendido' : 'Última venta hace ${DateTime.now().difference(p.lastSale!).inDays} días',
                      style: AppText.small(ctx, color: c.inkMuted)),
                  trailing: StatusPill('${p.stock} und.', compact: true),
                ),
              if (_idle.length > 40)
                Text('…y ${_idle.length - 40} más.', style: AppText.small(ctx, color: c.inkMuted)),
            ],
          );
        },
      );
}
