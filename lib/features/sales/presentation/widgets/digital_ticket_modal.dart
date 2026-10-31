import 'package:flutter/material.dart';

import '../../../business/presentation/active_business_scope.dart';
import '../../models/sale.dart';
import 'sale_card.dart' show paymentMethodLabel;
import 'sale_document.dart';

/// Comprobante de una venta (o de varios productos vendidos juntos), con el logo
/// y el color del negocio, para compartir como imagen o texto
class DigitalTicketModal {
  DigitalTicketModal._();

  static Future<void> show(
    BuildContext context, {
    Sale? sale,
    List<Sale>? salesList,
    String? businessName,
    String? invoiceNumber,
    double? discountAmount,
  }) {
    final items = salesList ?? [if (sale != null) sale];
    assert(items.isNotEmpty);
    final business = ActiveBusinessScope.read(context);
    return SaleDocumentSheet.show(
      context,
      business: business,
      businessName: businessName ?? business?.name ?? 'Mi negocio',
      doc: buildReceipt(items, invoiceNumber: invoiceNumber, discount: discountAmount ?? 0),
    );
  }

  /// Arma el comprobante a partir de las ventas
  static SaleDocument buildReceipt(List<Sale> items, {String? invoiceNumber, double discount = 0}) {
    final first = items.first;
    final number = invoiceNumber ?? (first.id.length >= 8 ? first.id.substring(0, 8) : first.id).toUpperCase();
    return SaleDocument(
      title: 'Comprobante de venta',
      number: number,
      date: first.date,
      lines: [
        for (final s in items)
          SaleDocumentLine(quantity: s.quantity, name: s.productName, unitPrice: s.unitPrice, total: s.totalAmount),
      ],
      discount: discount,
      total: items.fold(0.0, (sum, s) => sum + s.totalAmount),
      paymentMethod: paymentMethodLabel(first.paymentMethod),
      customerName: first.customerName,
      sellerName: first.sellerName,
      notice: first.paymentMethod == 'FIADO' ? 'Venta a crédito (fiado)' : null,
      closing: '¡Gracias por tu compra!',
    );
  }
}
