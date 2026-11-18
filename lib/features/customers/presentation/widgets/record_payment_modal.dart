import '../../../../core/design/app_dialog.dart';
import '../../../../core/utils/money_input.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../business/presentation/active_business_scope.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/countries.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../data/customer_repository.dart';
import '../../models/customer.dart';
import '../../../../core/design/status_pill.dart';
import '../../../sales/models/payment_method.dart';
import '../../../sales/presentation/widgets/sale_document.dart';

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
    // La hoja del diseño nuevo (0.16.7, hallazgo 33)
    return AppSheet.show<void>(
      context: context,
      title: 'Registrar abono',
      subtitle: customer.name,
      builder: (_) => RecordPaymentModal(customer: customer, onPaymentRecorded: onPaymentRecorded),
    );
  }

  @override
  State<RecordPaymentModal> createState() => _RecordPaymentModalState();
}

class _RecordPaymentModalState extends State<RecordPaymentModal> {
  final _customerRepo = CustomerRepository.instance;
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  String _paymentMethod = PaymentMethod.cash;
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
      _amountController.text = MoneyInput.text(amount);
      _errorMessage = null;
    });
  }

  Future<void> _submitPayment() async {
    final amount = _amountController.text.trim().isEmpty ? null : MoneyInput.parse(_amountController.text);

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
    final storeName = ActiveBusinessScope.read(context)?.name ?? 'Mi Negocio';
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
    final business = ActiveBusinessScope.read(context);
    final paidOff = result.remainingDebt <= 0.01;

    // El abono como tiquete (bloque 5): sello ABONO con lo que queda, o CUENTA AL DÍA
    TicketViewer.show(
      context,
      business: business,
      businessName: storeName,
      headline: 'Abono registrado',
      headlineTone: AppTone.success,
      subline: '${CurrencyFormatter.format(result.payment.amount)} de ${result.customer.name}',
      text: receiptText,
      doc: SaleDocument(
        title: 'Abono',
        number: 'AB-${DateFormat('yyMMdd-HHmm').format(result.payment.date)}',
        date: result.payment.date,
        lines: const [],
        total: result.payment.amount,
        totalLabel: 'Abonado',
        paymentMethod: PaymentMethod.label(result.payment.paymentMethod),
        customerName: result.customer.name,
        before: [TicketRow('Saldo anterior', CurrencyFormatter.format(result.previousDebt))],
        after: [TicketRow('Saldo pendiente', CurrencyFormatter.format(result.remainingDebt), bold: true)],
        closing: '¡Muchas gracias por tu pago!',
        stamp: paidOff
            ? const TicketStamp('CUENTA AL DÍA', tone: AppTone.success)
            : TicketStamp('ABONO', detail: 'Debe ${CurrencyFormatter.format(result.remainingDebt)}', tone: AppTone.accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    final c = context.colors;
    final debt = customer.debtBalance;
    final quick = <(String, double)>[
      ('Todo (${CurrencyFormatter.format(debt)})', debt),
      if (debt > 2000) ('La mitad', (debt / 2).roundToDouble()),
      for (final v in const [10000.0, 20000.0, 50000.0])
        if (v < debt) (CurrencyFormatter.format(v), v),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Lo que debe
        Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(color: c.warningSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
          child: Row(
            children: [
              Expanded(child: Text('Debe', style: AppText.body(context, weight: FontWeight.w600, color: c.ink))),
              Text(CurrencyFormatter.format(debt), style: AppText.amount(context, size: AppText.sizeHeading, weight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (_errorMessage != null) ...[
          Text(_errorMessage!, style: AppText.small(context, weight: FontWeight.w600, color: c.danger)),
          const SizedBox(height: AppSpace.sm),
        ],
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: MoneyInput.formatters,
          decoration: InputDecoration(
            labelText: 'Cuánto abona',
            prefixText: '\$ ',
            // El ejemplo nunca pasa la deuda (antes decía «Ej. 20000» aunque debiera menos)
            hintText: CurrencyFormatter.format(debt).replaceAll(RegExp(r'[^0-9.]'), ''),
          ),
          onChanged: (_) {
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [for (final (label, value) in quick) ActionChip(label: Text(label), onPressed: () => _setAmount(value))],
        ),
        const SizedBox(height: AppSpace.lg),
        Text('Cómo pagó', style: AppText.small(context, weight: FontWeight.w600)),
        const SizedBox(height: AppSpace.sm),
        // Los mismos medios que Vender (Nequi y Tarjeta incluidos)
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final m in PaymentMethod.forMixed)
              ChoiceChip(
                avatar: Icon(PaymentMethod.icon(m), size: 16),
                label: Text(PaymentMethod.label(m)),
                selected: _paymentMethod == m,
                showCheckmark: false,
                onSelected: (_) => setState(() => _paymentMethod = m),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        TextField(
          controller: _notesController,
          decoration: InputDecoration(
            labelText: 'Nota (opcional)',
            hintText: 'Ej. pagó por ${_firstPaymentApp(context)}',
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _isLoading ? null : _submitPayment,
            child: Text(_isLoading ? 'Registrando…' : 'Registrar abono'),
          ),
        ),
      ],
    );
  }
}

/// Primera app de pago del país del negocio activo, para el ejemplo de las notas
String _firstPaymentApp(BuildContext context) =>
    countryByCode(ActiveBusinessScope.read(context)?.country).paymentApps.split(' o ').first;
