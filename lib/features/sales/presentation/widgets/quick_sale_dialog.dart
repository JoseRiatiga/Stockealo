import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../customers/data/customer_repository.dart';
import '../../../customers/models/customer.dart';
import '../../../products/models/product.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../data/sales_repository.dart';
import 'digital_ticket_modal.dart';

class QuickSaleDialog extends StatefulWidget {
  final Product product;

  const QuickSaleDialog({super.key, required this.product});

  static Future<bool?> show(BuildContext context, Product product) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickSaleDialog(product: product),
    );
  }

  @override
  State<QuickSaleDialog> createState() => _QuickSaleDialogState();
}

class _QuickSaleDialogState extends State<QuickSaleDialog> {
  final _salesRepo = SalesRepository();
  final _customerController = TextEditingController();

  int _quantity = 1;
  String _paymentMethod = 'EFECTIVO'; // 'EFECTIVO' | 'TRANSFERENCIA' | 'FIADO'
  bool _isLoading = false;
  List<Customer> _existingCustomers = [];

  @override
  void initState() {
    super.initState();
    if (widget.product.stock <= 0) {
      _quantity = 0;
    }
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    try {
      final list = await CustomerRepository.instance.getCustomers(widget.product.businessId);
      if (mounted) {
        setState(() => _existingCustomers = list);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _customerController.dispose();
    super.dispose();
  }

  void _increment() {
    if (_quantity < widget.product.stock) {
      setState(() => _quantity++);
    }
  }

  void _decrement() {
    if (_quantity > 1) {
      setState(() => _quantity--);
    }
  }

  Future<void> _submitSale() async {
    if (_quantity <= 0 || _quantity > widget.product.stock) return;

    if (_paymentMethod == 'FIADO' && _customerController.text.trim().isEmpty) {
      AppToast.showWarning(
        context,
        'Por favor escribe o selecciona el nombre del cliente para el fiado.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final sale = await _salesRepo.recordSale(
        product: widget.product,
        quantity: _quantity,
        paymentMethod: _paymentMethod,
        customerName: _paymentMethod == 'FIADO' ? _customerController.text.trim() : null,
      );

      if (mounted) {
        final remainingStock = widget.product.stock - _quantity;
        final nav = Navigator.of(context);
        nav.pop(true);

        AppToast.showSuccess(
          nav.context,
          'Descontadas $_quantity unid. del inventario (Quedan: $remainingStock)',
          title: 'Venta Registrada',
        );

        // Abrir el comprobante digital listo para WhatsApp
        DigitalTicketModal.show(nav.context, sale: sale);
      }
    } catch (e) {
      if (mounted) {
        AppToast.showError(
          context,
          e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = widget.product;
    final isOutOfStock = p.isOutOfStock;
    final totalAmount = p.salePrice * _quantity;
    final netProfit = (p.salePrice - p.purchasePrice) * _quantity;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
        left: 20,
        right: 20,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barra superior de agarre
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF475569) : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Encabezado del producto
          Row(
            children: [
              ProductImageView(
                imagePath: p.photoPath,
                width: 60,
                height: 60,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.code} • ${CurrencyFormatter.format(p.salePrice)} / unid.',
                      style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isOutOfStock
                            ? (isDark ? const Color(0xFF7F1D1D).withOpacity(0.4) : const Color(0xFFFEE2E8))
                            : (isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isOutOfStock ? 'Agotado (0)' : 'Stock disponible: ${p.stock}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isOutOfStock
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Si está agotado, bloquear
          if (isOutOfStock) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF7F1D1D).withOpacity(0.3) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? const Color(0xFF991B1B) : const Color(0xFFFECACA)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.block, color: Color(0xFFDC2626)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No es posible registrar ventas porque el stock físico es 0. Repón inventario primero.',
                      style: TextStyle(fontSize: 13, color: Color(0xFFEF4444)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ] else ...[
            // Selector de Cantidad a Descontar
            Text(
              'Cantidad a descontar por venta:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
            ),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: _decrement,
                  icon: const Icon(Icons.remove),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                    foregroundColor: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                    padding: const EdgeInsets.all(12),
                  ),
                ),
                Container(
                  width: 80,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '$_quantity',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _increment,
                  icon: const Icon(Icons.add),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                    foregroundColor: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Resumen financiero de la venta en segundo plano
            Center(
              child: Text(
                'Total: ${CurrencyFormatter.format(totalAmount)}  •  Ganancia: ${CurrencyFormatter.format(netProfit)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF059669),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Selector de Método de Pago
            Text(
              'Método de pago utilizado:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                _buildPaymentMethodChip('EFECTIVO', '💵 Efectivo', isDark),
                const SizedBox(width: 8),
                _buildPaymentMethodChip('TRANSFERENCIA', '📱 Transf.', isDark),
                const SizedBox(width: 8),
                _buildPaymentMethodChip('FIADO', '📝 Fiado', isDark),
              ],
            ),

            // Input para nombre de cliente si es FIADO
            if (_paymentMethod == 'FIADO') ...[
              const SizedBox(height: 14),
              // Chips de clientes rápidos si hay registrados
              if (_existingCustomers.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Clientes registrados:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                    Text(
                      '${_existingCustomers.length} disponibles',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _existingCustomers.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final c = _existingCustomers[i];
                      final isSelected = _customerController.text.trim().toLowerCase() == c.name.toLowerCase();
                      return ActionChip(
                        avatar: CircleAvatar(
                          backgroundColor: isSelected ? Colors.white : const Color(0xFF2563EB).withOpacity(0.2),
                          child: Text(
                            c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF2563EB),
                            ),
                          ),
                        ),
                        label: Text(
                          c.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B)),
                          ),
                        ),
                        backgroundColor: isSelected
                            ? const Color(0xFF2563EB)
                            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                        side: BorderSide(
                          color: isSelected
                              ? const Color(0xFF2563EB)
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                        ),
                        onPressed: () {
                          setState(() {
                            _customerController.text = c.name;
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],

              RawAutocomplete<Customer>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return _existingCustomers.take(5);
                  }
                  return _existingCustomers.where((Customer option) {
                    return option.name.toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
                        (option.phone != null && option.phone!.contains(textEditingValue.text));
                  });
                },
                displayStringForOption: (Customer option) => option.name,
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  if (_customerController.text.isNotEmpty && controller.text.isEmpty) {
                    controller.text = _customerController.text;
                  }
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Nombre del Cliente para el Fiado *',
                      hintText: 'Escribe o busca cliente...',
                      prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF059669)),
                      suffixIcon: controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                controller.clear();
                                _customerController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (val) {
                      _customerController.text = val;
                      setState(() {});
                    },
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(14),
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      child: Container(
                        width: MediaQuery.of(context).size.width - 48,
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          shrinkWrap: true,
                          itemCount: options.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                          ),
                          itemBuilder: (context, index) {
                            final Customer option = options.elementAt(index);
                            return ListTile(
                              dense: true,
                              leading: const CircleAvatar(
                                radius: 14,
                                backgroundColor: Color(0xFFEFF6FF),
                                child: Icon(Icons.person, size: 16, color: Color(0xFF2563EB)),
                              ),
                              title: Text(
                                option.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              subtitle: option.debtBalance > 0
                                  ? Text(
                                      'Deuda pendiente: ${CurrencyFormatter.format(option.debtBalance)}',
                                      style: const TextStyle(fontSize: 11, color: Colors.orange),
                                    )
                                  : (option.phone != null
                                      ? Text(option.phone!, style: const TextStyle(fontSize: 11))
                                      : null),
                              onTap: () {
                                onSelected(option);
                                _customerController.text = option.name;
                                setState(() {});
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 24),

            // Botón de Confirmación
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _submitSale,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _isLoading ? 'Guardando...' : 'Registrar Venta ($_quantity unid.)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentMethodChip(String method, String label, bool isDark) {
    final isSelected = _paymentMethod == method;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _paymentMethod = method),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF059669)
                : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF059669)
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? Colors.white
                  : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
            ),
          ),
        ),
      ),
    );
  }
}
