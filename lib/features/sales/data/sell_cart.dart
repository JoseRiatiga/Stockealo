import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../products/data/product_repository.dart';

import '../../products/models/product.dart';
import '../../products/models/product_variant.dart';
import '../models/cart_item.dart';
import '../models/promotion.dart';

/// Una venta que se dejó «para después» (el cliente fue por algo y se atiende a otro)
class HeldSale {
  final List<CartItem> lines;
  final double discount;
  final String customer;
  final DateTime at;

  HeldSale({required this.lines, required this.discount, required this.customer, required this.at});

  double get total => (lines.fold<double>(0, (s, l) => s + l.netSubtotal) - discount).clamp(0, double.infinity);
  int get units => lines.fold<int>(0, (s, l) => s + l.quantity);
}

/// LA cuenta que se está cobrando en Vender. Vive mientras la app está abierta: si
/// la persona va a otro lugar y vuelve, la venta sigue ahí. Desde otras pantallas
/// (detalle de un producto, buscador) se agregan productos con [add].
class SellCart extends ChangeNotifier {
  SellCart._();
  static final SellCart instance = SellCart._();

  final List<CartItem> lines = [];
  final List<HeldSale> held = [];

  /// Negocio de las ventas en espera cargadas (0.15.0: se guardan en el celular)
  String? businessId;

  /// Descuento a toda la venta, en dinero
  double discount = 0;

  /// Promociones vigentes del negocio: se aplican solas a cada línea (0.13.4)
  List<Promotion> promotions = const [];

  void setPromotions(List<Promotion> list) {
    promotions = list;
    _applyPromotions();
    notifyListeners();
  }

  void _applyPromotions() {
    final now = DateTime.now();
    for (final l in lines) {
      l.promotion = Promotion.best(promotions,
          productId: l.product.id, category: l.product.category, unitPrice: l.unitPrice, quantity: l.quantity, at: now);
    }
  }

  /// Lo que descuentan las promociones en toda la cuenta
  double get promoDiscount => lines.fold<double>(0, (s, l) => s + l.promoDiscount);
  String customer = '';

  bool get isEmpty => lines.isEmpty;
  int get units => lines.fold<int>(0, (s, l) => s + l.quantity);
  double get subtotal => lines.fold<double>(0, (s, l) => s + l.subtotal);
  /// Descuentos de cada línea (0.15.0)
  double get lineDiscounts => lines.fold<double>(0, (s, l) => s + l.lineDiscount);

  /// Todo lo descontado a mano: por línea y a toda la venta (las promociones no cuentan)
  double get manualDiscount => lineDiscounts + discount;

  double get total => (subtotal - promoDiscount - lineDiscounts - discount).clamp(0, double.infinity);
  double get cost => lines.fold<double>(0, (s, l) => s + l.totalCost);

  /// El descuento más alto sin vender por debajo del costo
  double get maxSafeDiscount => (subtotal - promoDiscount - lineDiscounts - cost).clamp(0, double.infinity);

  /// Descuento de una línea, en dinero (0.15.0); 0 lo quita
  void setLineDiscount(int index, double amount) {
    if (index < 0 || index >= lines.length) return;
    final l = lines[index];
    final max = (l.subtotal - l.promoDiscount).clamp(0, double.infinity).toDouble();
    l.lineDiscount = amount.clamp(0, max).toDouble();
    _fitDiscount();
    notifyListeners();
  }

  /// Con ese descuento la venta deja pérdida
  bool get hasLoss => lines.isNotEmpty && total < cost - 0.5;
  double get loss => (cost - total).clamp(0, double.infinity);

  /// Agrega una unidad. Devuelve el aviso si no se puede (sin stock o ya están todas).
  String? add(Product product, [ProductVariant? variant]) {
    final available = variant?.stock ?? product.stock;
    final i = lines.indexWhere((l) => l.product.id == product.id && l.variant?.id == variant?.id);
    final name = variant == null ? product.name : '${product.name} (${variant.label})';
    if (available <= 0) return '$name no tiene stock';
    if (i >= 0) {
      if (lines[i].quantity >= available) return 'Solo hay $available de $name';
      lines[i].quantity++;
    } else {
      lines.add(CartItem(product: product, variant: variant));
    }
    _fitDiscount();
    notifyListeners();
    return null;
  }

  /// Cambia la cantidad de una línea (0 la quita). Devuelve el aviso si no hay tantas.
  String? setQuantity(int index, int quantity) {
    if (index < 0 || index >= lines.length) return null;
    final line = lines[index];
    if (quantity <= 0) {
      lines.removeAt(index);
    } else if (quantity > line.availableStock) {
      return 'Solo hay ${line.availableStock} de ${line.displayName}';
    } else {
      line.quantity = quantity;
    }
    _fitDiscount();
    notifyListeners();
    return null;
  }

  void setDiscount(double value) {
    // Tope: lo que queda después de promociones y descuentos de línea (0.16.6, hallazgo 8)
    discount = value.clamp(0, math.max(0, subtotal - promoDiscount - lineDiscounts)).toDouble();
    notifyListeners();
  }

  void setCustomer(String value) {
    customer = value;
    notifyListeners();
  }

  /// El descuento nunca supera lo que se está vendiendo (y las promociones se recalculan)
  void _fitDiscount() {
    _applyPromotions();
    for (final l in lines) {
      final lineMax = l.subtotal - l.promoDiscount;
      if (l.lineDiscount > lineMax) l.lineDiscount = lineMax < 0 ? 0 : lineMax;
    }
    final max = subtotal - promoDiscount - lineDiscounts;
    if (discount > max) discount = max < 0 ? 0 : max;
  }

  void clear() {
    lines.clear();
    discount = 0;
    customer = '';
    notifyListeners();
  }

  /// «Guardar para después»: la cuenta pasa a En espera y Vender queda libre
  void hold() {
    if (lines.isEmpty) return;
    held.add(HeldSale(lines: List.of(lines), discount: discount, customer: customer, at: DateTime.now()));
    lines.clear();
    discount = 0;
    customer = '';
    _saveHeld();
    notifyListeners();
  }

  static String _key(String businessId) => 'held_sales_$businessId';

  /// Guarda las ventas en espera en el celular: no se pierden al cerrar la app (0.15.0)
  void _saveHeld() {
    final b = businessId;
    if (b == null) return;
    final data = [
      for (final h in held)
        {
          'at': h.at.toIso8601String(),
          'discount': h.discount,
          'customer': h.customer,
          'lines': [
            for (final l in h.lines)
              {
                'product_id': l.product.id,
                'variant_id': l.variant?.id,
                'quantity': l.quantity,
                'unit_price': l.customUnitPrice,
                'discount_percent': l.discountPercent,
                'line_discount': l.lineDiscount,
              },
          ],
        },
    ];
    AppDatabase.instance.setSetting(_key(b), data.isEmpty ? null : jsonEncode(data)).catchError((Object e) {
      debugPrint('Ventas en espera sin guardar: $e');
    });
  }

  /// Carga las ventas en espera guardadas del negocio. Un producto que ya no existe se
  /// salta; si la venta se queda sin productos, no se carga.
  Future<void> restore(String forBusiness) async {
    businessId = forBusiness;
    held.clear();
    try {
      final raw = await AppDatabase.instance.getSetting(_key(forBusiness));
      if (raw != null) {
        final repo = ProductRepository.instance;
        for (final h in jsonDecode(raw) as List) {
          final saved = <CartItem>[];
          for (final l in (h['lines'] as List)) {
            final product = await repo.getProductById(l['product_id'] as String, forBusiness);
            if (product == null) continue;
            ProductVariant? variant;
            final variantId = l['variant_id'] as String?;
            if (variantId != null) {
              variant = (await repo.getVariantsForProduct(product.id)).where((v) => v.id == variantId).firstOrNull;
              if (variant == null) continue;
            }
            saved.add(CartItem(
              product: product,
              variant: variant,
              quantity: (l['quantity'] as num).toInt(),
              customUnitPrice: (l['unit_price'] as num?)?.toDouble(),
              discountPercent: (l['discount_percent'] as num?)?.toDouble(),
            )..lineDiscount = (l['line_discount'] as num?)?.toDouble() ?? 0);
          }
          if (saved.isEmpty) continue;
          held.add(HeldSale(
            lines: saved,
            discount: (h['discount'] as num?)?.toDouble() ?? 0,
            customer: h['customer'] as String? ?? '',
            at: DateTime.tryParse('${h['at']}') ?? DateTime.now(),
          ));
        }
      }
    } catch (e) {
      debugPrint('Ventas en espera sin cargar: $e');
    }
    if (businessId == forBusiness) notifyListeners();
  }

  /// Retoma una venta en espera. Si había algo en la cuenta, eso pasa a En espera.
  void resume(int index) {
    if (index < 0 || index >= held.length) return;
    final h = held.removeAt(index);
    if (lines.isNotEmpty) {
      held.add(HeldSale(lines: List.of(lines), discount: discount, customer: customer, at: DateTime.now()));
    }
    lines
      ..clear()
      ..addAll(h.lines);
    _applyPromotions();
    discount = h.discount;
    customer = h.customer;
    _saveHeld();
    notifyListeners();
  }

  /// Al cambiar de negocio la cuenta y lo que estaba en espera ya no aplican (lo guardado
  /// de cada negocio sigue en el celular y vuelve al volver a ese negocio)
  void reset() {
    lines.clear();
    held.clear();
    businessId = null;
    discount = 0;
    customer = '';
    notifyListeners();
  }
}
