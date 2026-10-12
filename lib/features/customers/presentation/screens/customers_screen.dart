import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../business/data/business_repository.dart';
import '../../data/customer_repository.dart';
import '../../models/customer.dart';
import '../widgets/record_payment_modal.dart';

class CustomersScreen extends StatefulWidget {
  final String businessId;

  const CustomersScreen({
    super.key,
    required this.businessId,
  });

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _customerRepo = CustomerRepository.instance;
  final _searchController = TextEditingController();

  List<Customer> _customers = [];
  bool _isLoading = true;
  String _filter = 'TODOS'; // 'TODOS' | 'DEUDA' | 'AL_DIA'

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    final list = await _customerRepo.getCustomers(widget.businessId);
    if (mounted) {
      setState(() {
        _customers = list;
        _isLoading = false;
      });
    }
  }

  List<Customer> get _filteredCustomers {
    final query = _searchController.text.trim().toLowerCase();
    return _customers.where((c) {
      final matchesQuery = c.name.toLowerCase().contains(query) ||
          (c.phone != null && c.phone!.contains(query));

      if (!matchesQuery) return false;

      if (_filter == 'DEUDA') return c.hasDebt;
      if (_filter == 'AL_DIA') return !c.hasDebt;
      return true;
    }).toList();
  }

  double get _totalDebt => _customers.fold(0.0, (sum, c) => sum + c.debtBalance);
  int get _debtorsCount => _customers.where((c) => c.hasDebt).length;

  Future<void> _openCreateCustomerDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final debtController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Nuevo Cliente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre del Cliente *', prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono / WhatsApp', prefixIcon: Icon(Icons.phone_outlined)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Dirección (Opcional)', prefixIcon: Icon(Icons.location_on_outlined)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: debtController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Deuda Inicial (\$) (Opcional)', prefixIcon: Icon(Icons.money_off)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final initialDebt = double.tryParse(debtController.text.trim()) ?? 0.0;

              await _customerRepo.createCustomer(
                businessId: widget.businessId,
                name: name,
                phone: phoneController.text.trim(),
                address: addressController.text.trim(),
                initialDebt: initialDebt,
              );

              if (ctx.mounted) Navigator.pop(ctx);
              _loadCustomers();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showCustomerPaymentsHistory(Customer customer) async {
    final payments = await _customerRepo.getCustomerPayments(customer.id);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Historial de Abonos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1E293B))),
                      Text(customer.name, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(height: 20),
              if (payments.isEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No hay registros de abonos para este cliente todavía.', style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: payments.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final p = payments[index];
                      final dateStr = DateFormat('dd/MM/yyyy hh:mm a').format(p.date);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: p.paymentMethod == 'EFECTIVO' ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF),
                          child: Icon(
                            p.paymentMethod == 'EFECTIVO' ? Icons.payments_outlined : Icons.account_balance_wallet_outlined,
                            color: p.paymentMethod == 'EFECTIVO' ? const Color(0xFF059669) : const Color(0xFF2563EB),
                            size: 18,
                          ),
                        ),
                        title: Text(CurrencyFormatter.formatCOP(p.amount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text('$dateStr • ${p.paymentMethod}${p.notes != null ? " • ${p.notes}" : ""}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _sendFriendlyReminderWhatsApp(Customer customer) {
    final storeName = BusinessRepository.instance.currentActiveBusiness?.name ?? 'Mi Negocio';
    final text = 'Hola ${customer.name} 👋 Te saluda $storeName. Esperamos que te encuentres muy bien. Te compartimos un recordatorio cordial de tu saldo pendiente de ${CurrencyFormatter.formatCOP(customer.debtBalance)} con nosotros. ¡Muchas gracias por tu preferencia!';
    Share.share(text, subject: 'Recordatorio cordial - $storeName');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredCustomers;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Clientes y Fiados', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
      ),
      body: Column(
        children: [
          // Banner de resumen de cartera/deuda
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF78350F).withOpacity(0.4) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? const Color(0xFFD97706) : const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.receipt_long, color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total por Cobrar (Fiados)',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.formatCOP(_totalDebt),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$_debtorsCount deudores',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Buscador y Filtros
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar cliente por nombre o teléfono...',
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _searchController.clear()))
                        : null,
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildFilterChip('TODOS', 'Todos (${_customers.length})', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('DEUDA', 'Con Deuda ($_debtorsCount)', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('AL_DIA', 'Al Día (${_customers.length - _debtorsCount})', isDark),
                  ],
                ),
              ],
            ),
          ),

          // Lista de Clientes
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.people_outline, size: 54, color: Color(0xFFCBD5E1)),
                            const SizedBox(height: 12),
                            Text(
                              _customers.isEmpty ? 'Aún no tienes clientes registrados' : 'No se encontraron clientes con este filtro',
                              style: TextStyle(
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final c = filtered[index];
                          return _buildCustomerCard(c, isDark);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateCustomerDialog,
        backgroundColor: const Color(0xFF059669),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo Cliente'),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, bool isDark) {
    final selected = _filter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: selected
            ? (isDark ? const Color(0xFFA7F3D0) : const Color(0xFF059669))
            : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
      ),
      onSelected: (_) => setState(() => _filter = key),
    );
  }

  Widget _buildCustomerCard(Customer customer, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: customer.hasDebt
              ? (isDark ? const Color(0xFFD97706) : const Color(0xFFFDE68A))
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
      ),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: customer.hasDebt
                      ? (isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7))
                      : (isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5)),
                  child: Text(
                    customer.name.isNotEmpty ? customer.name[0].toUpperCase() : 'C',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: customer.hasDebt
                          ? (isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309))
                          : const Color(0xFF059669),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                        ),
                      ),
                      if (customer.phone?.isNotEmpty == true)
                        Text(
                          '📞 ${customer.phone}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                    ],
                  ),
                ),
                // Badge de saldo
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: customer.hasDebt
                        ? (isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7))
                        : (isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: customer.hasDebt
                          ? (isDark ? const Color(0xFFD97706) : const Color(0xFFFDE68A))
                          : (isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        customer.hasDebt ? 'Deuda' : 'Al Día',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: customer.hasDebt
                              ? (isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309))
                              : const Color(0xFF059669),
                        ),
                      ),
                      Text(
                        CurrencyFormatter.formatCOP(customer.debtBalance),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: customer.hasDebt
                              ? (isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309))
                              : const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Divider(height: 20, color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (customer.hasDebt) ...[
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, size: 20, color: Color(0xFF25D366)),
                    tooltip: 'Recordar pago por WhatsApp',
                    onPressed: () => _sendFriendlyReminderWhatsApp(customer),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      RecordPaymentModal.show(
                        context,
                        customer: customer,
                        onPaymentRecorded: _loadCustomers,
                      );
                    },
                    icon: const Icon(Icons.attach_money, size: 16),
                    label: const Text('Abonar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: () => _showCustomerPaymentsHistory(customer),
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('Historial', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                    side: BorderSide(color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
