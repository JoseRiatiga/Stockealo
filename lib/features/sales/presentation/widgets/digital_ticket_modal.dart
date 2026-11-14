import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/status_pill.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../business/presentation/active_business_scope.dart';
import '../../models/payment_method.dart';
import '../../models/sale.dart';
import 'sale_document.dart';

/// Comprobante de una venta (todas las líneas de una misma venta), como tiquete de
/// papel con su sello: PAGADO, FIADO (con lo que queda debiendo) o ANULADA.
class DigitalTicketModal {
  DigitalTicketModal._();

  /// [received] y [change]: lo que entregó el cliente y el vuelto (efectivo).
  /// [debtAfter]: lo que queda debiendo el cliente (fiado).
  /// [justSold]: recién cobrada en Vender («Venta registrada» y «Nueva venta»).
  static Future<void> show(
    BuildContext context, {
    Sale? sale,
    List<Sale>? salesList,
    String? businessName,
    String? invoiceNumber,
    double? discountAmount,
    double? received,
    double? change,
    double? debtAfter,
    bool justSold = false,
  }) {
    final items = salesList ?? [if (sale != null) sale];
    assert(items.isNotEmpty);
    final business = ActiveBusinessScope.read(context);
    final doc = buildReceipt(
      items,
      invoiceNumber: invoiceNumber,
      discount: discountAmount ?? 0,
      received: received,
      change: change,
      debtAfter: debtAfter,
    );
    final first = items.first;
    return TicketViewer.show(
      context,
      business: business,
      businessName: businessName ?? business?.name ?? 'Mi negocio',
      doc: doc,
      headline: first.isVoided ? 'Venta anulada' : (justSold ? 'Venta registrada' : 'Comprobante de venta'),
      headlineTone: first.isVoided ? AppTone.danger : AppTone.success,
      subline: first.isVoided ? null : '${CurrencyFormatter.format(doc.total)} ${PaymentMethod.phrase(first.paymentMethod)}',
      closeLabel: justSold ? 'Nueva venta' : 'Cerrar',
    );
  }

  /// Arma el comprobante a partir de las líneas de la venta
  static SaleDocument buildReceipt(
    List<Sale> items, {
    String? invoiceNumber,
    double discount = 0,
    double? received,
    double? change,
    double? debtAfter,
  }) {
    final first = items.first;
    final number = invoiceNumber ??
        ((first.invoiceNumber ?? '').isNotEmpty
            ? first.invoiceNumber!.replaceFirst('#', '')
            : (first.id.length >= 8 ? first.id.substring(0, 8) : first.id).toUpperCase());
    final day = DateFormat('dd MMM yyyy', 'es_CO').format(first.date).toUpperCase();
    final credit = first.paymentMethod == PaymentMethod.credit;
    final stamp = first.isVoided
        ? TicketStamp('ANULADA', detail: DateFormat('dd MMM yyyy', 'es_CO').format(first.voidedAt!).toUpperCase(), tone: AppTone.danger)
        : credit
            ? TicketStamp('FIADO', detail: debtAfter == null ? day : 'Debe ${CurrencyFormatter.format(debtAfter)}', tone: AppTone.warning)
            : TicketStamp('PAGADO', detail: day);
    final split = <String, double>{};
    for (final s in items) {
      for (final e in PaymentMethod.decodeSplit(s.paymentSplit).entries) {
        split[e.key] = (split[e.key] ?? 0) + e.value;
      }
    }
    return SaleDocument(
      title: 'Comprobante',
      number: number,
      date: first.date,
      lines: [
        for (final s in items)
          SaleDocumentLine(
            quantity: s.quantity,
            // Con promoción (0.13.4): «Camiseta · Promo Fin de mes −$5.000»
            name: s.promotionName == null || s.promotionDiscount <= 0
                ? s.productName
                : '${s.productName} · Promo ${s.promotionName} −${CurrencyFormatter.format(s.promotionDiscount)}',
            unitPrice: s.unitPrice,
            total: s.totalAmount,
          ),
      ],
      discount: discount,
      total: items.fold(0.0, (sum, s) => sum + s.totalAmount),
      paymentMethod: PaymentMethod.label(first.paymentMethod),
      customerName: first.customerName,
      sellerName: first.sellerName,
      notice: first.isVoided
          ? 'Venta anulada${(first.voidReason ?? '').isEmpty ? '' : ': ${first.voidReason}'}'
          : (credit ? 'Venta a crédito (fiado)' : null),
      closing: '¡Gracias por tu compra!',
      stamp: stamp,
      after: [
        for (final e in split.entries) TicketRow('  ${PaymentMethod.label(e.key)}', CurrencyFormatter.format(e.value)),
        if (received != null && received > 0) TicketRow('Recibido', CurrencyFormatter.format(received)),
        if (change != null && change > 0) TicketRow('Vuelto', CurrencyFormatter.format(change), bold: true),
        if (credit && debtAfter != null) TicketRow('Saldo pendiente', CurrencyFormatter.format(debtAfter), bold: true),
      ],
    );
  }
}
