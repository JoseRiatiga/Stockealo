import '../../../../core/theme/app_tokens.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/stocky_empty_state.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/models/product_variant.dart';
import '../../data/sales_repository.dart';
import '../../models/cart_item.dart';
import '../../models/quotation.dart';
import '../../../business/presentation/active_business_scope.dart';
import 'digital_ticket_modal.dart';
import 'sale_document.dart';

class QuotationsListModal extends StatefulWidget {
  final String businessId;

  const QuotationsListModal({super.key, required this.businessId});

  static Future<void> show(BuildContext context, {required String businessId}) {
    return showModalBottomSheet(
      showDragHandle: false,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuotationsListModal(businessId: businessId),
    );
  }

  @override
  State<QuotationsListModal> createState() => _QuotationsListModalState();
}

class _QuotationsListModalState extends State<QuotationsListModal> {
  final _salesRepo = SalesRepository();
  final _productRepo = ProductRepository();
  List<Quotation> _quotations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuotations();
  }

  Future<void> _loadQuotations() async {
    setState(() => _isLoading = true);
    try {
      final list = await _salesRepo.getQuotations(businessId: widget.businessId);
      if (mounted) {
        setState(() {
          _quotations = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Abre la cotización con el logo del negocio para compartirla
  void _shareQuotation(Quotation q) {
    final business = ActiveBusinessScope.read(context);
    SaleDocumentSheet.show(
      context,
      business: business,
      businessName: business?.name ?? 'Mi negocio',
      doc: SaleDocument(
        title: 'Cotización',
        number: q.quotationNumber,
        date: q.createdAt,
        validUntil: q.validUntil,
        lines: [
          for (final i in q.items)
            SaleDocumentLine(
              quantity: i.quantity,
              name: i.variantName?.isNotEmpty == true ? '${i.productName} (${i.variantName})' : i.productName,
              unitPrice: i.unitPrice,
              total: i.subtotal,
            ),
        ],
        discount: q.discountAmount,
        total: q.totalAmount,
        customerName: q.customerName,
        sellerName: q.sellerName,
        notes: q.notes,
        closing: 'Para confirmar tu pedido, responde a este mensaje.',
      ),
    );
  }

  Future<void> _convertQuotationToSale(Quotation q) async {
    if (q.status == 'FACTURADA') {
      AppToast.show(context, message: 'Esta cotización ya fue facturada.', type: ToastType.warning);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Facturar Cotización?'),
        content: Text(
          'Se descontarán las unidades del inventario y se registrará la venta formal por ${CurrencyFormatter.formatCOP(q.totalAmount)}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.colors.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar y Facturar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      // Reconstruir CartItems con productos frescos de la base de datos
      final List<CartItem> cartItems = [];
      for (final qItem in q.items) {
        final prod = await _productRepo.getProductById(qItem.productId, widget.businessId);
        if (prod == null) {
          throw Exception('El producto "${qItem.productName}" ya no existe en el catálogo.');
        }

        ProductVariant? matchedVariant;
        if (qItem.variantId != null && prod.hasVariants) {
          for (final v in prod.variants) {
            if (v.id == qItem.variantId) {
              matchedVariant = v;
              break;
            }
          }
        }

        final available = matchedVariant != null ? matchedVariant.stock : prod.stock;
        if (available < qItem.quantity) {
          throw Exception('Stock insuficiente para "${qItem.productName}". Quedan $available y la cotización pide ${qItem.quantity}.');
        }

        cartItems.add(CartItem(
          product: prod,
          variant: matchedVariant,
          quantity: qItem.quantity,
          customUnitPrice: qItem.unitPrice,
        ));
      }

      final sales = await _salesRepo.recordMultiProductSale(
        businessId: widget.businessId,
        items: cartItems,
        paymentMethod: 'EFECTIVO',
        customerName: q.customerName,
        discountAmount: q.discountAmount,
        notes: 'Facturada desde Cotización ${q.quotationNumber}',
      );

      await _salesRepo.markQuotationAsBilled(q.id);

      if (mounted) {
        AppToast.show(
          context,
          message: '¡Cotización ${q.quotationNumber} facturada con éxito!',
          type: ToastType.success,
        );
        _loadQuotations();
        DigitalTicketModal.show(
          context,
          salesList: sales,
          discountAmount: q.discountAmount,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, message: '$e', type: ToastType.error);
      }
    }
  }

  Future<void> _deleteQuotation(Quotation q) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar Cotización?'),
        content: Text('Se eliminará ${q.quotationNumber}. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _salesRepo.deleteQuotation(q.id);
      _loadQuotations();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = context.colors.surface;
    final borderColor = context.colors.line;
    final cardBg = context.colors.surfaceMuted;
    final textMain = context.colors.ink;
    final textMuted = context.colors.inkMuted;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: context.colors.lineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.colors.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.description_outlined, color: context.colors.accent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cotizaciones y Presupuestos',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textMain),
                      ),
                      Text(
                        '${_quotations.length} registradas (no descuentan stock)',
                        style: TextStyle(fontSize: 11, color: textMuted),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: context.colors.accent))
                : _quotations.isEmpty
                    ? const StockyEmptyState(
                        title: 'No hay cotizaciones pendientes',
                        message: 'Cuando guardes una venta como proforma o cotización, aparecerá aquí lista para enviar o facturar en 1 clic.',
                        mascotSize: 72,
                      )
                    : ListView.separated(
                        itemCount: _quotations.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, idx) {
                          final q = _quotations[idx];
                          final isBilled = q.status == 'FACTURADA';

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isBilled
                                    ? context.colors.accent.withOpacity(0.3)
                                    : borderColor,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          q.quotationNumber,
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: textMain),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isBilled
                                                ? context.colors.accent.withOpacity(0.15)
                                                : context.colors.warning.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            q.status,
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: isBilled ? context.colors.accent : context.colors.warning,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      CurrencyFormatter.formatCOP(q.totalAmount),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: context.colors.accent,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),

                                if (q.customerName?.isNotEmpty == true)
                                  Text(
                                    'Cliente: ${q.customerName}',
                                    style: TextStyle(fontSize: 12, color: textMuted),
                                  ),

                                const SizedBox(height: 6),
                                // Resumen de ítems
                                Text(
                                  q.items.map((i) => '${i.quantity}x ${i.productName}').join(' • '),
                                  style: TextStyle(fontSize: 11.5, color: textMain.withOpacity(0.85)),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 10),

                                // Botones de acción
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.delete_outline, size: 18, color: context.colors.danger),
                                      tooltip: 'Eliminar',
                                      onPressed: () => _deleteQuotation(q),
                                    ),
                                    const SizedBox(width: 4),
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.share, size: 14),
                                      label: const Text('WhatsApp', style: TextStyle(fontSize: 11.5)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: context.colors.accent,
                                        side: BorderSide(color: context.colors.accent),
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                      onPressed: () => _shareQuotation(q),
                                    ),
                                    if (!isBilled) ...[
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.point_of_sale_rounded, size: 14),
                                        label: const Text('Facturar', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: context.colors.accent,
                                          foregroundColor: Colors.white,
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        ),
                                        onPressed: () => _convertQuotationToSale(q),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
