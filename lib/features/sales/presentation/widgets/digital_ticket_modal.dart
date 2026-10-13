import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../business/data/business_repository.dart';
import '../../models/sale.dart';

class DigitalTicketModal extends StatelessWidget {
  final Sale sale;
  final String? businessName;

  const DigitalTicketModal({
    super.key,
    required this.sale,
    this.businessName,
  });

  static Future<void> show(
    BuildContext context, {
    required Sale sale,
    String? businessName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DigitalTicketModal(
        sale: sale,
        businessName: businessName,
      ),
    );
  }

  String _generateTicketText(String storeName) {
    final dateFormat = DateFormat('dd/MM/yyyy hh:mm a');
    final formattedDate = dateFormat.format(sale.date);
    final shortId = sale.id.length >= 8 ? sale.id.substring(0, 8).toUpperCase() : sale.id.toUpperCase();

    final buffer = StringBuffer();
    buffer.writeln('🧾 *COMPROBANTE DE VENTA*');
    buffer.writeln('🏪 *$storeName*');
    buffer.writeln('📅 Fecha: $formattedDate');
    buffer.writeln('🔢 N° Ticket: #$shortId');
    buffer.writeln('--------------------------------');
    buffer.writeln('🛒 *Detalle:*');
    buffer.writeln('• ${sale.quantity}x ${sale.productName}');
    buffer.writeln('  Precio: ${CurrencyFormatter.formatCOP(sale.unitPrice)} c/u');
    buffer.writeln('  Subtotal: ${CurrencyFormatter.formatCOP(sale.totalAmount)}');
    buffer.writeln('--------------------------------');
    buffer.writeln('💰 *TOTAL A PAGAR:* ${CurrencyFormatter.formatCOP(sale.totalAmount)}');
    buffer.writeln('💳 *Método de pago:* ${sale.paymentMethod}');
    if (sale.customerName?.isNotEmpty == true) {
      buffer.writeln('👤 *Cliente:* ${sale.customerName}');
    }
    if (sale.sellerName?.isNotEmpty == true) {
      buffer.writeln('👤 *Atendido por:* ${sale.sellerName}');
    }
    if (sale.paymentMethod == 'FIADO') {
      buffer.writeln('⚠️ *Estado:* Venta a Crédito (Fiado)');
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('¡Muchas gracias por su compra!');
    buffer.writeln('Comprobante digital emitido con Stockealo 📦');

    return buffer.toString();
  }

  void _shareViaWhatsApp(BuildContext context, String storeName) async {
    final text = _generateTicketText(storeName);
    await Share.share(
      text,
      subject: 'Comprobante de compra - $storeName',
    );
  }

  void _copyToClipboard(BuildContext context, String storeName) {
    final text = _generateTicketText(storeName);
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📋 Ticket copiado al portapapeles.'),
        backgroundColor: Color(0xFF059669),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final ticketBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textMain = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final activeBiz = BusinessRepository.instance.currentActiveBusiness;
    final storeName = businessName ?? activeBiz?.name ?? 'Mi Negocio';
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final shortId = sale.id.length >= 8 ? sale.id.substring(0, 8).toUpperCase() : sale.id.toUpperCase();

    return Container(
      margin: const EdgeInsets.only(top: 40),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            MediaQuery.of(context).padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Indicador de arrastre
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF475569) : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),

              // Cabecera Modal
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ticket Digital de Venta',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textMain),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Recibo estilo ticket térmico
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: ticketBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Encabezado del negocio
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.receipt_long, color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669), size: 28),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            storeName,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textMain),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateFormat.format(sale.date),
                            style: TextStyle(fontSize: 12, color: textMuted),
                          ),
                          Text(
                            'Ticket #$shortId',
                            style: TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 24, thickness: 1),

                    // Detalle de ítems
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Cant. / Descripción', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted)),
                        Text('Importe', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${sale.quantity}x ${sale.productName}',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textMain),
                              ),
                              Text(
                                '${CurrencyFormatter.formatCOP(sale.unitPrice)} c/u',
                                style: TextStyle(fontSize: 12, color: textMuted),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          CurrencyFormatter.formatCOP(sale.totalAmount),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textMain),
                        ),
                      ],
                    ),
                    const Divider(height: 24, thickness: 1),

                    // Total y Pago
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textMain)),
                        Text(
                          CurrencyFormatter.formatCOP(sale.totalAmount),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Método de Pago:', style: TextStyle(fontSize: 12, color: textMuted)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: sale.paymentMethod == 'FIADO'
                                ? (isDark ? const Color(0xFF78350F).withOpacity(0.4) : const Color(0xFFFEF3C7))
                                : (isDark ? const Color(0xFF064E3B).withOpacity(0.5) : const Color(0xFFECFDF5)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            sale.paymentMethod,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: sale.paymentMethod == 'FIADO'
                                  ? (isDark ? const Color(0xFFFCD34D) : const Color(0xFFD97706))
                                  : (isDark ? const Color(0xFF34D399) : const Color(0xFF059669)),
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (sale.customerName?.isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Cliente:', style: TextStyle(fontSize: 12, color: textMuted)),
                          Text(sale.customerName!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textMain)),
                        ],
                      ),
                    ],

                    if (sale.sellerName?.isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Atendido por:', style: TextStyle(fontSize: 12, color: textMuted)),
                          Text(sale.sellerName!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textMain)),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        '¡Muchas gracias por su compra!',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textMuted),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Botones de acción
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _shareViaWhatsApp(context, storeName),
                  icon: const Icon(Icons.share, size: 20),
                  label: const Text('Enviar Comprobante por WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copyToClipboard(context, storeName),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar Texto'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                        side: BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
                        elevation: 0,
                        side: BorderSide(
                          color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Listo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
