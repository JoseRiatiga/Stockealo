import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../business/data/business_repository.dart';
import '../../data/customer_repository.dart';
import '../../models/customer.dart';

class RecordPaymentModal extends StatefulWidget {
  final Customer customer;
  final VoidCallback onPaymentRecorded;

  const RecordPaymentModal({
    super.key,
    required this.customer,
    required this.onPaymentRecorded,
  });

  static Future<void> show(
    BuildContext context, {
    required Customer customer,
    required VoidCallback onPaymentRecorded,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecordPaymentModal(
        customer: customer,
        onPaymentRecorded: onPaymentRecorded,
      ),
    );
  }

  @override
  State<RecordPaymentModal> createState() => _RecordPaymentModalState();
}

class _RecordPaymentModalState extends State<RecordPaymentModal> {
  final _customerRepo = CustomerRepository.instance;
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  String _paymentMethod = 'EFECTIVO';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _setAmount(double amount) {
    setState(() {
      _amountController.text = amount.toStringAsFixed(0);
      _errorMessage = null;
    });
  }

  Future<void> _submitPayment() async {
    final rawAmount = _amountController.text.trim().replaceAll('\$', '').replaceAll('.', '').replaceAll(',', '');
    final amount = double.tryParse(rawAmount);

    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = 'Ingresa un monto válido mayor a 0');
      return;
    }

    if (amount > widget.customer.debtBalance) {
      setState(() => _errorMessage = 'El abono no puede superar la deuda total (${CurrencyFormatter.formatCOP(widget.customer.debtBalance)})');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _customerRepo.recordPayment(
        customerId: widget.customer.id,
        businessId: widget.customer.businessId,
        amount: amount,
        paymentMethod: _paymentMethod,
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onPaymentRecorded();

      // Mostrar diálogo para compartir recibo por WhatsApp
      _showPaymentReceiptDialog(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _showPaymentReceiptDialog(BuildContext context, PaymentResult result) {
    final storeName = BusinessRepository.instance.currentActiveBusiness?.name ?? 'Mi Negocio';
    final dateFormat = DateFormat('dd/MM/yyyy hh:mm a');
    final formattedDate = dateFormat.format(result.payment.date);

    final buffer = StringBuffer();
    buffer.writeln('🧾 *RECIBO DE ABONO A CUENTA*');
    buffer.writeln('🏪 *$storeName*');
    buffer.writeln('👤 Cliente: ${result.customer.name}');
    buffer.writeln('📅 Fecha: $formattedDate');
    buffer.writeln('--------------------------------');
    buffer.writeln('💰 Saldo anterior: ${CurrencyFormatter.formatCOP(result.previousDebt)}');
    buffer.writeln('✅ *MONTO ABONADO:* ${CurrencyFormatter.formatCOP(result.payment.amount)}');
    buffer.writeln('💳 Medio de pago: ${result.payment.paymentMethod}');
    buffer.writeln('--------------------------------');
    buffer.writeln('📝 *SALDO RESTANTE:* ${CurrencyFormatter.formatCOP(result.remainingDebt)}');
    if (result.remainingDebt <= 0.01) {
      buffer.writeln('🎉 *¡Cuenta saldada en su totalidad!*');
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('¡Muchas gracias por su pago puntual!');
    buffer.writeln('Comprobante emitido con Stockealo 📦');

    final receiptText = buffer.toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF059669), size: 24),
            SizedBox(width: 10),
            Text('Abono Registrado', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Se descontaron ${CurrencyFormatter.formatCOP(result.payment.amount)} de la cuenta de ${result.customer.name}.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Nuevo saldo deudor:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatCOP(result.remainingDebt),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: result.remainingDebt > 0 ? const Color(0xFFD97706) : const Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Share.share(receiptText, subject: 'Recibo de Abono - $storeName');
            },
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Enviar WhatsApp'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textMain = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 20,
        top: 24,
        left: 20,
        right: 20,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabecera
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Registrar Abono a Fiado',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textMain),
                      ),
                      Text(
                        'Cliente: ${customer.name}',
                        style: TextStyle(fontSize: 13, color: textMuted, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 20),

              // Tarjeta de Deuda Actual
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF78350F).withOpacity(0.4) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? const Color(0xFF92400E) : const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Deuda Pendiente Actual',
                          style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E)),
                        ),
                        Text(
                          'Saldo por cobrar',
                          style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309)),
                        ),
                      ],
                    ),
                    Text(
                      CurrencyFormatter.formatCOP(customer.debtBalance),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF7F1D1D).withOpacity(0.4) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? const Color(0xFFB91C1C) : const Color(0xFFFECACA),
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626), fontSize: 12),
                  ),
                ),
              ],

              // Campo de Monto a Abonar
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Monto a Abonar (\$)',
                  hintText: 'Ej. 20000',
                  prefixIcon: Icon(Icons.attach_money, color: Color(0xFF059669)),
                ),
              ),
              const SizedBox(height: 10),

              // Chips de Acceso Rápido al monto
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.done_all, size: 16, color: Color(0xFF059669)),
                    label: const Text('Pagar Todo', style: TextStyle(fontSize: 12)),
                    onPressed: () => _setAmount(customer.debtBalance),
                  ),
                  if (customer.debtBalance > 2000)
                    ActionChip(
                      label: const Text('50%', style: TextStyle(fontSize: 12)),
                      onPressed: () => _setAmount(customer.debtBalance / 2),
                    ),
                  if (customer.debtBalance >= 10000)
                    ActionChip(
                      label: const Text('\$10.000', style: TextStyle(fontSize: 12)),
                      onPressed: () => _setAmount(10000),
                    ),
                  if (customer.debtBalance >= 20000)
                    ActionChip(
                      label: const Text('\$20.000', style: TextStyle(fontSize: 12)),
                      onPressed: () => _setAmount(20000),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Medio de Pago
              Text('Medio de Pago:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textMain)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.payments_outlined,
                            size: 14,
                            color: _paymentMethod == 'EFECTIVO' ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669)) : textMuted,
                          ),
                          const SizedBox(width: 4),
                          const Text('Efectivo'),
                        ],
                      ),
                      selected: _paymentMethod == 'EFECTIVO',
                      selectedColor: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _paymentMethod == 'EFECTIVO' ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669)) : textMuted,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _paymentMethod = 'EFECTIVO');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ChoiceChip(
                      label: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.account_balance_outlined,
                            size: 14,
                            color: _paymentMethod == 'TRANSFERENCIA' ? (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB)) : textMuted,
                          ),
                          const SizedBox(width: 4),
                          const Text('Transferencia'),
                        ],
                      ),
                      selected: _paymentMethod == 'TRANSFERENCIA',
                      selectedColor: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _paymentMethod == 'TRANSFERENCIA' ? (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB)) : textMuted,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _paymentMethod = 'TRANSFERENCIA');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Notas opcionales
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notas / Observaciones (Opcional)',
                  hintText: 'Ej. Pagó por Nequi / Dejó abono en efectivo',
                  prefixIcon: Icon(Icons.note_alt_outlined),
                ),
              ),
              const SizedBox(height: 20),

              // Botón Guardar Abono
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _submitPayment,
                  icon: _isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text('Registrar Abono y Generar Recibo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
