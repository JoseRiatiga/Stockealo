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
import '../../../../core/design/stat_card.dart';
import '../../../../core/design/filter_tabs.dart';
import '../../../../core/design/status_pill.dart';

class CustomersScreen extends StatefulWidget {
  final String businessId;
  /// Dentro del marco de la app (lugar del menú): sin barra propia, el encabezado único pone el título
  final bool embedded;

  const CustomersScreen({
    super.key,
    required this.businessId,
    this.embedded = false,
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
                      Text('Historial de abonos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppText.sizeTitle, color: context.colors.ink)),
                      Text(customer.name, style: TextStyle(fontSize: AppText.sizeSmall, color: context.colors.inkMuted)),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close_outlined), onPressed: () => Navigator.pop(ctx)),
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
                        title: Text(CurrencyFormatter.formatCOP(p.amount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppText.sizeBody)),
                        subtitle: Text('$dateStr • ${p.paymentMethod}${p.notes != null ? " • ${p.notes}" : ""}', style: TextStyle(fontSize: AppText.sizeCaption, color: context.colors.inkMuted)),
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
    final filtered = _filteredCustomers;

    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 640;
    final kpis = [
      StatCard(
        title: 'Fiados por cobrar',
        value: CurrencyFormatter.formatCOP(_totalDebt),
        detail: _totalDebt > 0 ? 'Lo que te deben tus clientes' : 'Nadie te debe',
        compact: !wide,
      ),
      StatCard(
        title: 'Clientes que deben',
        value: '$_debtorsCount',
        detail: _debtorsCount == 0 ? 'Todos al día' : 'Toca «Con deuda» para verlos',
        onTap: _debtorsCount == 0 ? null : () => setState(() => _filter = 'DEUDA'),
        compact: !wide,
      ),
      StatCard(
        title: 'Clientes',
        value: '${_customers.length}',
        detail: '${_customers.length - _debtorsCount} al día',
        compact: !wide,
      ),
    ];

    // Re-diseño 0.13.4 (segunda pasada): encabezado con la acción, cifras en tarjetas,
    // buscador y pestañas; sin botón flotante (ya no se cruza con Stocky)
    return Scaffold(
      backgroundColor: c.paper,
      appBar: widget.embedded ? null : AppBar(title: const Text('Clientes y fiados')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Clientes y fiados', style: AppText.title(context)),
                          Text('Quién te debe, cuánto y desde cuándo', style: AppText.small(context)),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _openCreateCustomerDialog,
                      icon: const Icon(Icons.person_add_outlined, size: 18),
                      label: Text(wide ? 'Nuevo cliente' : 'Nuevo'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < kpis.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpace.md),
                        Expanded(child: kpis[i]),
                      ],
                    ],
                  )
                else ...[
                  kpis[0],
                  const SizedBox(height: AppSpace.sm),
                  Row(children: [Expanded(child: kpis[1]), const SizedBox(width: AppSpace.sm), Expanded(child: kpis[2])]),
                ],
                const SizedBox(height: AppSpace.md),
                Flex(
                  direction: wide ? Axis.horizontal : Axis.vertical,
                  crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      flex: wide ? 1 : 0,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre o teléfono',
                          prefixIcon: Icon(Icons.search_outlined, color: c.inkMuted),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  tooltip: 'Borrar búsqueda',
                                  icon: const Icon(Icons.clear_outlined, size: 18),
                                  onPressed: () => setState(() => _searchController.clear()),
                                )
                              : null,
                          isDense: true,
                        ),
                      ),
                    ),
                    SizedBox(width: wide ? AppSpace.md : 0, height: wide ? 0 : AppSpace.sm),
                    FilterTabs<String>(
                      options: {
                        'TODOS': 'Todos (${_customers.length})',
                        'DEUDA': 'Con deuda ($_debtorsCount)',
                        'AL_DIA': 'Al día (${_customers.length - _debtorsCount})',
                      },
                      value: _filter,
                      onChanged: (v) => setState(() => _filter = v),
                    ),
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
                            Icon(Icons.people_outline_outlined, size: 54, color: context.colors.lineStrong),
                            const SizedBox(height: 12),
                            Text(
                              _customers.isEmpty ? 'Aún no tienes clientes registrados' : 'No se encontraron clientes con este filtro',
                              style: TextStyle(
                                color: context.colors.inkMuted,
                                fontSize: AppText.sizeBody,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          AppSpace.lg,
                          AppSpace.sm,
                          AppSpace.lg,
                          MediaQuery.of(context).padding.bottom + 96,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final c = filtered[index];
                          return _buildCustomerCard(c);
                        },
                      ),
          ),
        ],
      ),
      ),
      ),
    );
  }

  Widget _buildCustomerCard(Customer customer) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: customer.hasDebt
              ? (context.colors.warningSoft)
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
                      ? (context.colors.warningSoft)
                      : (context.colors.successSoft),
                  child: Text(
                    customer.name.isNotEmpty ? customer.name[0].toUpperCase() : 'C',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: customer.hasDebt
                          ? (context.colors.warning)
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyLarge(context, weight: FontWeight.w700),
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
                                  style: TextStyle(fontSize: AppText.sizeCaption, color: context.colors.accent),
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
                            Flexible(
                              child: Text(
                                customer.phone!,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption(context),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                // Saldo: lo que debe en grande y su estado
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormatter.formatCOP(customer.debtBalance),
                      style: AppText.amount(context, size: AppText.sizeBodyLarge, color: customer.hasDebt ? context.colors.warning : context.colors.ink),
                    ),
                    const SizedBox(height: 2),
                    StatusPill(customer.hasDebt ? 'Debe' : 'Al día', tone: customer.hasDebt ? AppTone.warning : AppTone.success, compact: true),
                  ],
                ),
              ],
            ),
            Divider(height: 20, color: context.colors.line),
            // Acciones: se acomodan en varias líneas si no caben (celular)
            SizedBox(width: double.infinity, child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                if (customer.hasDebt) ...[
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline_outlined, size: 20, color: AppPalette.whatsapp),
                    tooltip: 'Recordar pago por WhatsApp',
                    onPressed: () => _sendFriendlyReminderWhatsApp(customer),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      RecordPaymentModal.show(
                        context,
                        customer: customer,
                        onPaymentRecorded: _onPaymentRecorded,
                      );
                    },
                    icon: const Icon(Icons.attach_money_outlined, size: 16),
                    label: const Text('Abonar'),
                  ),
                ],
                _sharingId == customer.id
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpace.md),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : PopupMenuButton<String>(
                        tooltip: 'Cobro y estado de cuenta',
                        icon: Icon(Icons.more_vert_outlined, color: context.colors.inkMuted),
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
                  icon: const Icon(Icons.history_outlined, size: 16),
                  label: const Text('Historial'),
                ),
              ],
            )),
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
