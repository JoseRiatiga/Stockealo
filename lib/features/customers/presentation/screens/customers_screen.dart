import '../../../../core/theme/app_tokens.dart';
import '../../../business/presentation/active_business_scope.dart';
import '../../data/debt_reminder.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../data/customer_repository.dart';
import '../../models/customer.dart';
import '../widgets/new_customer_sheet.dart';
import '../widgets/record_payment_modal.dart';
import '../../../../core/design/pro_crown.dart';
import '../../../../core/design/app_time_picker.dart';
import '../../../../core/services/phone_alerts_service.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../pro/data/pro_service.dart';
import '../../../pro/presentation/widgets/pro_upsell_sheet.dart';
import '../../data/account_statement.dart';
import '../../data/debt_reminder_schedule.dart';
import '../widgets/debt_reminder_schedule_sheet.dart';

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

  /// Recordatorios de cobro programados, por cliente (Stockealo Pro)
  Map<String, DebtReminderSchedule> _reminders = {};
  bool _pro = false;
  String? _sharingId;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    ProService.instance.status.addListener(_onProChanged);
    ProService.instance.refresh(widget.businessId);
    // refresh limpia al instante el estado si era de otro negocio
    _pro = ProService.instance.status.value.active;
  }

  void _onProChanged() {
    if (mounted) setState(() => _pro = ProService.instance.status.value.active);
  }

  @override
  void dispose() {
    ProService.instance.status.removeListener(_onProChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    final list = await _customerRepo.getCustomers(widget.businessId);
    final reminders = await DebtReminderStore.instance.load();
    if (mounted) {
      setState(() {
        _customers = list;
        _reminders = reminders;
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
    final saved = await NewCustomerSheet.show(context, businessId: widget.businessId);
    if (saved == true) _loadCustomers();
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
                      Text('Historial de abonos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: context.colors.ink)),
                      Text(customer.name, style: TextStyle(fontSize: 13, color: context.colors.inkMuted)),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(height: 20),
              if (payments.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No hay registros de abonos para este cliente todavía.', style: TextStyle(color: context.colors.inkMuted)),
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
                          backgroundColor: p.paymentMethod == 'EFECTIVO' ? context.colors.successSoft : context.colors.infoSoft,
                          child: Icon(
                            p.paymentMethod == 'EFECTIVO' ? Icons.payments_outlined : Icons.account_balance_wallet_outlined,
                            color: p.paymentMethod == 'EFECTIVO' ? context.colors.accent : context.colors.info,
                            size: 18,
                          ),
                        ),
                        title: Text(CurrencyFormatter.formatCOP(p.amount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text('$dateStr • ${p.paymentMethod}${p.notes != null ? " • ${p.notes}" : ""}', style: TextStyle(fontSize: 11, color: context.colors.inkMuted)),
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
    DebtReminder.send(
      customerName: customer.name,
      debtAmount: customer.debtBalance,
      businessName: ActiveBusinessScope.read(context)?.name ?? 'Mi negocio',
      phone: customer.phone,
    );
  }

  void _onPaymentRecorded() {
    _loadCustomers();
    // El aviso programado lleva la deuda nueva (o se quita si ya quedó al día)
    PhoneAlertsService.instance.refreshDebtReminders();
  }

  /// Las funciones de cobro son de Stockealo Pro: sin Pro se abre la ventana de Pro
  Future<bool> _ensurePro({required String title, required String message}) async {
    if (_pro) return true;
    final business = ActiveBusinessScope.read(context);
    if (business == null) return false;
    final result = await ProUpsellSheet.show(
      context,
      business: business,
      title: title,
      message: message,
      highlight: ProBenefit.debtCollection,
    );
    return result == ProUpsellResult.pro;
  }

  Future<void> _shareStatement(Customer customer) async {
    final pro = await _ensurePro(
      title: 'Estado de cuenta en PDF',
      message: 'Envíale a ${customer.name} un PDF con su saldo, lo que fió y lo que abonó, '
          'con el logo y el color de tu negocio.',
    );
    if (!pro || !mounted) return;
    final business = ActiveBusinessScope.read(context);
    if (business == null) return;
    setState(() => _sharingId = customer.id);
    try {
      await AccountStatementService.instance.share(business: business, customer: customer);
    } catch (e) {
      if (mounted) AppToast.show(context, message: 'No se pudo crear el estado de cuenta: $e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _sharingId = null);
    }
  }

  Future<void> _scheduleReminder(Customer customer) async {
    if (!PhoneAlertsService.instance.isSupported) {
      AppToast.show(context, message: 'Los recordatorios llegan al celular Android.', type: ToastType.info);
      return;
    }
    final pro = await _ensurePro(
      title: 'Recordatorios de cobro',
      message: 'Tu celular te avisa "Hoy toca cobrarle a ${customer.name}" cada cuánto quieras, '
          'con el mensaje de WhatsApp listo para enviar.',
    );
    if (!pro || !mounted) return;
    final changed = await DebtReminderScheduleSheet.show(context, customer: customer, current: _reminders[customer.id]);
    if (changed == true) _loadCustomers();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredCustomers;

    return Scaffold(
      backgroundColor: context.colors.surfaceMuted,
      appBar: AppBar(
        title: const Text('Clientes y fiados', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: context.colors.surface,
        foregroundColor: context.colors.ink,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
          // Banner de resumen de cartera/deuda
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF78350F).withOpacity(0.4) : context.colors.warningSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? context.colors.warning : const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.colors.warning.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.receipt_long, color: isDark ? const Color(0xFFFDE68A) : context.colors.warning, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fiados por cobrar',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFFFDE68A) : context.colors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.formatCOP(_totalDebt),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFFDE68A) : context.colors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _debtorsCount == 1 ? '1 cliente debe' : '$_debtorsCount clientes deben',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFDE68A) : context.colors.warning,
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
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre o teléfono',
                    prefixIcon: Icon(Icons.search, color: context.colors.inkMuted),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _searchController.clear()))
                        : null,
                    filled: true,
                    fillColor: context.colors.surfaceMuted,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildFilterChip('TODOS', 'Todos (${_customers.length})', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('DEUDA', 'Con deuda ($_debtorsCount)', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('AL_DIA', 'Al día (${_customers.length - _debtorsCount})', isDark),
                  ],
                ),
              ],
            ),
          ),

          // Lista de Clientes
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: context.colors.accent))
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 54, color: context.colors.lineStrong),
                            const SizedBox(height: 12),
                            Text(
                              _customers.isEmpty ? 'Aún no tienes clientes registrados' : 'No se encontraron clientes con este filtro',
                              style: TextStyle(
                                color: context.colors.inkMuted,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          MediaQuery.of(context).padding.bottom + 80,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final c = filtered[index];
                          return _buildCustomerCard(c, isDark);
                        },
                      ),
          ),
        ],
      ),
      ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        child: FloatingActionButton.extended(
          onPressed: _openCreateCustomerDialog,
          backgroundColor: context.colors.accent,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.person_add),
          label: const Text('Nuevo cliente'),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, bool isDark) {
    final selected = _filter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: isDark ? const Color(0xFF064E3B) : context.colors.successSoft,
      backgroundColor: context.colors.surfaceMuted,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: selected
            ? (isDark ? const Color(0xFFA7F3D0) : context.colors.accent)
            : (context.colors.inkMuted),
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
              ? (isDark ? context.colors.warning : const Color(0xFFFDE68A))
              : (context.colors.line),
        ),
      ),
      color: context.colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: customer.hasDebt
                      ? (isDark ? const Color(0xFF78350F) : context.colors.warningSoft)
                      : (isDark ? const Color(0xFF064E3B) : context.colors.successSoft),
                  child: Text(
                    customer.name.isNotEmpty ? customer.name[0].toUpperCase() : 'C',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: customer.hasDebt
                          ? (isDark ? const Color(0xFFFDE68A) : context.colors.warning)
                          : context.colors.accent,
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
                          color: context.colors.ink,
                        ),
                      ),
                      if (_reminders[customer.id] != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              Icon(Icons.notifications_active_outlined, size: 12, color: context.colors.accent),
                              const SizedBox(width: AppSpace.xs),
                              Flexible(
                                child: Text(
                                  '${_reminders[customer.id]!.frequencyLabel} · '
                                  '${formatAppTime(TimeOfDay(hour: _reminders[customer.id]!.hour, minute: _reminders[customer.id]!.minute))}',
                                  style: TextStyle(fontSize: 12, color: context.colors.accent),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (customer.phone?.isNotEmpty == true)
                        Row(
                          children: [
                            Icon(
                              Icons.phone_outlined,
                              size: 11,
                              color: context.colors.inkMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              customer.phone!,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.colors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                // Badge de saldo
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: customer.hasDebt
                        ? (isDark ? const Color(0xFF78350F) : context.colors.warningSoft)
                        : (isDark ? const Color(0xFF064E3B) : context.colors.successSoft),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: customer.hasDebt
                          ? (isDark ? context.colors.warning : const Color(0xFFFDE68A))
                          : (isDark ? context.colors.accent : const Color(0xFFA7F3D0)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        customer.hasDebt ? 'Deuda' : 'Al día',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: customer.hasDebt
                              ? (isDark ? const Color(0xFFFDE68A) : context.colors.warning)
                              : context.colors.accent,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.formatCOP(customer.debtBalance),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: customer.hasDebt
                              ? (isDark ? const Color(0xFFFDE68A) : context.colors.warning)
                              : context.colors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Divider(height: 20, color: context.colors.line),
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
                        onPaymentRecorded: _onPaymentRecorded,
                      );
                    },
                    icon: const Icon(Icons.attach_money, size: 16),
                    label: const Text('Abonar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _sharingId == customer.id
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpace.md),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : PopupMenuButton<String>(
                        tooltip: 'Cobro y estado de cuenta',
                        icon: Icon(Icons.more_vert_rounded, color: context.colors.inkMuted),
                        onSelected: (v) => v == 'statement' ? _shareStatement(customer) : _scheduleReminder(customer),
                        itemBuilder: (_) => [
                          _proMenuItem('statement', Icons.picture_as_pdf_outlined, 'Estado de cuenta (PDF)'),
                          _proMenuItem(
                            'reminder',
                            Icons.notifications_active_outlined,
                            _reminders[customer.id] == null ? 'Programar recordatorio' : 'Editar recordatorio',
                          ),
                        ],
                      ),
                OutlinedButton.icon(
                  onPressed: () => _showCustomerPaymentsHistory(customer),
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('Historial', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.ink,
                    side: BorderSide(color: context.colors.lineStrong),
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

  PopupMenuItem<String> _proMenuItem(String value, IconData icon, String label) {
    final c = context.colors;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: c.ink),
          const SizedBox(width: AppSpace.md),
          Expanded(child: Text(label, style: TextStyle(color: c.ink))),
          if (!_pro) ...[
            const SizedBox(width: AppSpace.sm),
            const ProCrown(),
          ],
        ],
      ),
    );
  }
}
