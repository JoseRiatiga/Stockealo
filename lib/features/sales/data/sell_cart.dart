import 'package:flutter/foundation.dart';

import '../../products/models/product.dart';
import '../../products/models/product_variant.dart';
import '../models/cart_item.dart';

/// Una venta que se dejó «para después» (el cliente fue por algo y se atiende a otro)
class HeldSale {
  final List<CartItem> lines;
  final double discount;
  final String customer;
  final DateTime at;

  HeldSale({required this.lines, required this.discount, required this.customer, required this.at});

  double get total => (lines.fold<double>(0, (s, l) => s + l.subtotal) - discount).clamp(0, double.infinity);
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

  /// Descuento a toda la venta, en dinero
  double discount = 0;
  String customer = '';

  bool get isEmpty => lines.isEmpty;
  int get units => lines.fold<int>(0, (s, l) => s + l.quantity);
  double get subtotal => lines.fold<double>(0, (s, l) => s + l.subtotal);
  double get total => (subtotal - discount).clamp(0, double.infinity);
  double get cost => lines.fold<double>(0, (s, l) => s + l.totalCost);

  /// El descuento más alto sin vender por debajo del costo
  double get maxSafeDiscount => (subtotal - cost).clamp(0, double.infinity);

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
    discount = value.clamp(0, subtotal).toDouble();
    notifyListeners();
  }

  void setCustomer(String value) {
    customer = value;
    notifyListeners();
  }

  /// El descuento nunca supera lo que se está vendiendo
  void _fitDiscount() {
    if (discount > subtotal) discount = subtotal;
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
    notifyListeners();
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
    discount = h.discount;
    customer = h.customer;
    notifyListeners();
  }

  /// Al cambiar de negocio la cuenta y lo que estaba en espera ya no aplican
  void reset() {
    lines.clear();
    held.clear();
    discount = 0;
    customer = '';
    notifyListeners();
  }
}
