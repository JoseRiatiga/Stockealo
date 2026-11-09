import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/design/phone_field.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/countries.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../sales/data/sales_repository.dart';
import '../../../sales/presentation/widgets/quick_sale_dialog.dart';
import '../../data/order_whatsapp.dart';
import '../../data/services_repository.dart';
import '../../models/service_models.dart';
import 'services_setup_screen.dart';

String _ago(DateTime since, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(since);
  if (d.inMinutes < 1) return 'ahora';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  return 'hace ${d.inHours} h ${d.inMinutes % 60} min';
}

/// Tablero de trabajos: cada moto (o cliente) pasa por En espera, Lavando, Lista
/// y Entregada. En pantallas anchas se ven las columnas lado a lado.
class WorkBoardScreen extends StatefulWidget {
  final Business business;
  const WorkBoardScreen({super.key, required this.business});

  static Future<void> open(BuildContext context, {required Business business}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkBoardScreen(business: business)));

  @override
  State<WorkBoardScreen> createState() => _WorkBoardScreenState();
}

class _WorkBoardScreenState extends State<WorkBoardScreen> {
  final _repo = ServicesRepository.instance;
  List<WorkOrder>? _orders;
  List<ShopService> _services = [];
  List<StaffMember> _staff = [];
  String _mobileColumn = WorkOrder.waiting;

  ServiceType get _type => ServiceType.of(widget.business.serviceType);
  Map<String, String> get _staffNames => {for (final s in _staff) s.id: s.name};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final orders = await _repo.getBoard(widget.business.id);
    final services = await _repo.getServices(widget.business.id);
    final staff = await _repo.getStaff(widget.business.id, includeInactive: true);
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _services = services;
      _staff = staff;
    });
  }

  Future<void> _newOrder([WorkOrder? editing]) async {
    if (_services.isEmpty) {
      AppToast.showWarning(context, 'Primero agrega tus servicios.');
      await ServicesSetupScreen.open(context, business: widget.business);
      await _load();
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => OrderSheet(
        business: widget.business,
        services: _services,
        staff: _staff.where((s) => s.isActive).toList(),
        editing: editing,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _advance(WorkOrder o) async {
    final next = o.nextStatus;
    if (next == null) return;
    if (next == WorkOrder.delivered) return _checkout(o);
    final moved = await _repo.moveTo(o, next);
    await _load();
    if (!mounted || next != WorkOrder.ready) return;
    // Al quedar lista se ofrece avisarle al cliente
    if ((moved.customerPhone ?? '').isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${moved.title} está lista.'),
        action: SnackBarAction(label: 'Avisar por WhatsApp', onPressed: () => OrderWhatsApp.sendReady(moved, widget.business)),
      ));
    }
  }

  Future<void> _checkout(WorkOrder o) async {
    final paid = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CheckoutSheet(order: o, business: widget.business, staffNames: _staffNames),
    );
    if (paid != true) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Cobrado y entregado.'),
      action: SnackBarAction(label: 'Vender un producto', onPressed: () => QuickSaleDialog.show(context)),
    ));
  }

  Future<void> _cancel(WorkOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Cancelar ${o.title}?'),
        content: const Text('Sale del tablero sin cobrar nada.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar orden')),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.cancel(o);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final orders = _orders;
    final wide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        title: const Text('Tablero'),
        actions: [
          if (_type.usesPlate)
            IconButton(
              tooltip: 'Historial por placa',
              icon: const Icon(Icons.manage_search_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlateHistoryScreen(business: widget.business, staffNames: _staffNames),
              )),
            ),
          IconButton(
            tooltip: 'Servicios y empleados',
            icon: const Icon(Icons.room_service_outlined),
            onPressed: () async {
              await ServicesSetupScreen.open(context, business: widget.business);
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newOrder(),
        icon: const Icon(Icons.add_rounded),
        label: Text('Nueva ${_type.unit.toLowerCase()}'),
      ),
      body: orders == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: wide ? _columns(orders) : _mobile(orders),
            ),
    );
  }

  List<WorkOrder> _in(List<WorkOrder> all, String status) => all.where((o) => o.status == status).toList();

  Widget _columns(List<WorkOrder> all) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final status in WorkOrder.flow)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                padding: const EdgeInsets.all(AppSpace.sm),
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.sm),
                      child: Text(
                        '${WorkOrder.statusLabel(status, _type)} (${_in(all, status).length})',
                        style: TextStyle(color: c.ink, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final o in _in(all, status)) ...[
                            _orderCard(o),
                            const SizedBox(height: AppSpace.sm),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mobile(List<WorkOrder> all) {
    final list = _in(all, _mobileColumn);
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 96),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final status in WorkOrder.flow)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.sm),
                  child: ChoiceChip(
                    label: Text('${WorkOrder.statusLabel(status, _type)} ${_in(all, status).length}'),
                    selected: _mobileColumn == status,
                    onSelected: (_) => setState(() => _mobileColumn = status),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Text(
              _mobileColumn == WorkOrder.waiting
                  ? 'No hay nadie en espera. Toca "Nueva ${_type.unit.toLowerCase()}" cuando llegue.'
                  : 'Nada por aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkMuted),
            ),
          ),
        for (final o in list) ...[
          _orderCard(o),
          const SizedBox(height: AppSpace.sm),
        ],
      ],
    );
  }

  Widget _orderCard(WorkOrder o) {
    final c = context.colors;
    final names = _staffNames;
    final staff = [for (final id in o.staffIds) names[id] ?? 'Empleado'];
    final next = o.nextStatus;
    final nextLabel = switch (next) {
      WorkOrder.inProgress => 'Empezar',
      WorkOrder.ready => 'Lista',
      WorkOrder.delivered => 'Cobrar',
      _ => null,
    };
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.xs, AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  o.title,
                  style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.5),
                ),
              ),
              Text('#${o.number}', style: TextStyle(color: c.inkFaint, fontSize: 12)),
              PopupMenuButton<String>(
                tooltip: 'Más',
                onSelected: (v) => switch (v) {
                  'edit' => _newOrder(o),
                  'whatsapp' => OrderWhatsApp.sendReady(o, widget.business),
                  'cancel' => _cancel(o),
                  _ => null,
                },
                itemBuilder: (_) => [
                  if (o.isOpen) const PopupMenuItem(value: 'edit', child: Text('Editar')),
                  const PopupMenuItem(value: 'whatsapp', child: Text('Avisar por WhatsApp')),
                  if (o.isOpen && !o.isPaid) const PopupMenuItem(value: 'cancel', child: Text('Cancelar')),
                ],
              ),
            ],
          ),
          if ((o.vehicle ?? '').isNotEmpty || ((o.customerName ?? '').isNotEmpty && o.title != o.customerName))
            Text(
              [if ((o.vehicle ?? '').isNotEmpty) o.vehicle!, if ((o.customerName ?? '').isNotEmpty && o.title != o.customerName) o.customerName!]
                  .join(' · '),
              style: TextStyle(color: c.inkMuted, fontSize: 12.5),
            ),
          const SizedBox(height: 4),
          Text(o.lines.map((l) => l.name).join(', '), style: TextStyle(color: c.ink, fontSize: 13)),
          if (staff.isNotEmpty)
            Text('Atiende: ${staff.join(', ')}', style: TextStyle(color: c.inkMuted, fontSize: 12.5)),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: c.inkFaint),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  o.status == WorkOrder.delivered
                      ? 'Pagó ${CurrencyFormatter.format(o.total)}${o.tip > 0 ? ' + propina ${CurrencyFormatter.format(o.tip)}' : ''}'
                      : '${_ago(o.since)} · ${CurrencyFormatter.format(o.subtotal)}',
                  style: TextStyle(color: c.inkMuted, fontSize: 12),
                ),
              ),
              if (nextLabel != null)
                next == WorkOrder.delivered
                    ? FilledButton(onPressed: () => _advance(o), child: Text(nextLabel))
                    : FilledButton.tonal(onPressed: () => _advance(o), child: Text(nextLabel)),
              const SizedBox(width: AppSpace.sm),
            ],
          ),
        ],
      ),
    );
  }
}

/// Registrar o editar una orden: placa (o cliente), servicios y quién los hace
class OrderSheet extends StatefulWidget {
  final Business business;
  final List<ShopService> services;
  final List<StaffMember> staff;
  final WorkOrder? editing;

  const OrderSheet({super.key, required this.business, required this.services, required this.staff, this.editing});

  @override
  State<OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<OrderSheet> {
  final _repo = ServicesRepository.instance;
  late final WorkOrder? _e = widget.editing;
  late final _plate = TextEditingController(text: _e?.plate ?? '');
  late final _vehicle = TextEditingController(text: _e?.vehicle ?? '');
  late final _customer = TextEditingController(text: _e?.customerName ?? '');
  late final _notes = TextEditingController(text: _e?.notes ?? '');
  late PhoneValue _phone = PhoneValue(_e?.customerPhone, isValid: true);
  int _phoneKey = 0;

  /// Servicio elegido -> empleados que lo hacen
  late final Map<String, List<String>> _chosen = {for (final l in _e?.lines ?? const <WorkOrderLine>[]) l.serviceId: [...l.staffIds]};
  List<WorkOrder> _suggestions = [];
  int _visits = 0;
  bool _saving = false;

  ServiceType get _type => ServiceType.of(widget.business.serviceType);

  @override
  void dispose() {
    for (final c in [_plate, _vehicle, _customer, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _onPlate(String value) async {
    final list = await _repo.platesStartingWith(widget.business.id, value);
    final visits = (await _repo.ordersByPlate(widget.business.id, value)).length;
    if (!mounted) return;
    setState(() {
      _suggestions = list.where((o) => o.plate != WorkOrder.normalizePlate(value)).toList();
      _visits = visits;
    });
  }

  void _useSuggestion(WorkOrder o) {
    setState(() {
      _plate.text = o.plate ?? '';
      if (_vehicle.text.isEmpty) _vehicle.text = o.vehicle ?? '';
      if (_customer.text.isEmpty) _customer.text = o.customerName ?? '';
      if ((o.customerPhone ?? '').isNotEmpty && (_phone.e164 ?? '').isEmpty) {
        _phone = PhoneValue(o.customerPhone, isValid: true);
        _phoneKey++;
      }
      _suggestions = [];
    });
    _onPlate(o.plate ?? '');
  }

  bool get _valid {
    final hasWho = _type.usesPlate ? WorkOrder.normalizePlate(_plate.text).isNotEmpty : _customer.text.trim().isNotEmpty;
    return hasWho && _chosen.isNotEmpty && _phone.isValid;
  }

  List<WorkOrderLine> _lines() => [
        for (final s in widget.services)
          if (_chosen.containsKey(s.id))
            WorkOrderLine(
              serviceId: s.id,
              name: s.name,
              price: _e?.lines.where((l) => l.serviceId == s.id).firstOrNull?.price ?? s.price,
              commissionPct: s.commissionPct,
              staffIds: _chosen[s.id]!,
            ),
      ];

  Future<void> _save() async {
    setState(() => _saving = true);
    final e = _e;
    if (e == null) {
      await _repo.createOrder(
        businessId: widget.business.id,
        lines: _lines(),
        plate: _plate.text,
        vehicle: _vehicle.text,
        customerName: _customer.text,
        customerPhone: _phone.e164,
        notes: _notes.text,
      );
    } else {
      final plate = WorkOrder.normalizePlate(_plate.text);
      await _repo.updateOrder(e.copyWith(
        plate: plate,
        vehicle: _vehicle.text.trim(),
        customerName: _customer.text.trim(),
        customerPhone: _phone.e164 ?? '',
        notes: _notes.text.trim(),
        lines: _lines(),
      ));
    }
    if (mounted) Navigator.pop(context, true);
  }

  void _toggleService(ShopService s) {
    setState(() {
      if (_chosen.containsKey(s.id)) {
        _chosen.remove(s.id);
      } else {
        // Hereda los empleados del primer servicio ya elegido
        _chosen[s.id] = _chosen.values.isEmpty ? [] : [..._chosen.values.first];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = _lines().fold(0.0, (s, l) => s + l.price);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ContentWidth(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            Text(
              _e == null ? 'Nueva ${_type.unit.toLowerCase()}' : 'Editar #${_e.number}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.ink),
            ),
            const SizedBox(height: AppSpace.md),
            if (_type.usesPlate) ...[
              TextField(
                controller: _plate,
                autofocus: _e == null,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 -]')),
                  TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
                ],
                onChanged: (v) {
                  setState(() {});
                  _onPlate(v);
                },
                decoration: InputDecoration(
                  labelText: 'Placa',
                  hintText: 'ABC12D',
                  prefixIcon: const Icon(Icons.two_wheeler_outlined),
                  helperText: _visits > 0 ? 'Ya vino $_visits ${_visits == 1 ? 'vez' : 'veces'}' : null,
                ),
              ),
              if (_suggestions.isNotEmpty)
                Wrap(
                  spacing: AppSpace.sm,
                  children: [
                    for (final s in _suggestions)
                      ActionChip(
                        label: Text('${s.plate}${(s.customerName ?? '').isEmpty ? '' : ' · ${s.customerName}'}'),
                        onPressed: () => _useSuggestion(s),
                      ),
                  ],
                ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _vehicle,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Moto (opcional)', hintText: 'Ej. Pulsar negra'),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            TextField(
              controller: _customer,
              autofocus: _e == null && !_type.usesPlate,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: _type.usesPlate ? 'Cliente (opcional)' : 'Cliente'),
            ),
            const SizedBox(height: AppSpace.md),
            PhoneField(
              key: ValueKey(_phoneKey),
              initialValue: _phone.e164,
              defaultCountry: countryByCode(widget.business.country),
              label: 'WhatsApp del cliente (opcional)',
              onChanged: (v) => setState(() => _phone = v),
            ),
            const SizedBox(height: AppSpace.lg),
            Text('Servicios', style: TextStyle(color: c.ink, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final s in widget.services)
                  FilterChip(
                    label: Text('${s.name} · ${CurrencyFormatter.format(s.price)}'),
                    selected: _chosen.containsKey(s.id),
                    onSelected: (_) => _toggleService(s),
                  ),
              ],
            ),
            if (_chosen.isNotEmpty && widget.staff.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              Text('¿Quién lo hace?', style: TextStyle(color: c.ink, fontWeight: FontWeight.bold)),
              for (final s in widget.services)
                if (_chosen.containsKey(s.id)) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(s.name, style: TextStyle(color: c.inkMuted, fontSize: 12.5)),
                  Wrap(
                    spacing: AppSpace.sm,
                    children: [
                      for (final p in widget.staff)
                        FilterChip(
                          label: Text(p.name),
                          selected: _chosen[s.id]!.contains(p.id),
                          onSelected: (on) => setState(() => on ? _chosen[s.id]!.add(p.id) : _chosen[s.id]!.remove(p.id)),
                        ),
                    ],
                  ),
                ],
            ],
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notas (opcional)', hintText: 'Ej. Tiene un rayón en el tanque'),
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              onPressed: _valid && !_saving ? _save : null,
              child: Text(_e == null ? 'Agregar al tablero · ${CurrencyFormatter.format(total)}' : 'Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cobrar una orden: forma de pago, descuento y propina
class CheckoutSheet extends StatefulWidget {
  final WorkOrder order;
  final Business business;
  final Map<String, String> staffNames;

  const CheckoutSheet({super.key, required this.order, required this.business, required this.staffNames});

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  final _discount = TextEditingController();
  final _tip = TextEditingController();
  late final _customer = TextEditingController(text: widget.order.customerName ?? '');
  String _method = 'EFECTIVO';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_discount, _tip, _customer]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _sub => widget.order.subtotal;
  double get _disc => (double.tryParse(_discount.text.trim()) ?? 0).clamp(0, _sub).toDouble();
  double get _tipValue => double.tryParse(_tip.text.trim()) ?? 0;
  double get _total => _sub - _disc;

  Future<void> _pay() async {
    if (_method == 'FIADO' && _customer.text.trim().isEmpty) {
      AppToast.showWarning(context, 'Para fiar escribe el nombre del cliente.');
      return;
    }
    setState(() => _saving = true);
    try {
      final sales = await SalesRepository.instance.recordServiceSale(
        order: widget.order,
        paymentMethod: _method,
        customerName: _customer.text,
        discountAmount: _disc,
        staffNames: widget.staffNames,
      );
      await ServicesRepository.instance.markPaid(
        widget.order,
        saleIds: [for (final s in sales) s.id],
        paymentMethod: _method,
        total: _total,
        discount: _disc,
        tip: _tipValue,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.showError(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = widget.order;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ContentWidth(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            Text('Cobrar ${o.title}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.ink)),
            const SizedBox(height: AppSpace.md),
            for (final l in o.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l.name}${l.staffIds.isEmpty ? '' : ' · ${l.staffIds.map((id) => widget.staffNames[id] ?? 'Empleado').join(', ')}'}',
                        style: TextStyle(color: c.ink, fontSize: 13.5),
                      ),
                    ),
                    Text(CurrencyFormatter.format(l.price), style: TextStyle(color: c.ink)),
                  ],
                ),
              ),
            Divider(color: c.line),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _discount,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Descuento', prefixText: '\$ ', isDense: true),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: TextField(
                    controller: _tip,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Propina',
                      prefixText: '\$ ',
                      isDense: true,
                      helperText: 'Para el empleado',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              children: [
                for (final (code, label) in const [('EFECTIVO', 'Efectivo'), ('TRANSFERENCIA', 'Transferencia'), ('FIADO', 'Fiado')])
                  ChoiceChip(label: Text(label), selected: _method == code, onSelected: (_) => setState(() => _method = code)),
              ],
            ),
            if (_method == 'FIADO') ...[
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _customer,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Cliente que queda debiendo'),
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              onPressed: _saving ? null : _pay,
              child: Text(_saving
                  ? 'Cobrando...'
                  : 'Cobrar ${CurrencyFormatter.format(_total)}${_tipValue > 0 ? ' + ${CurrencyFormatter.format(_tipValue)} de propina' : ''}'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Historial de una placa: visitas, servicios, quién la atendió y cuánto ha gastado
class PlateHistoryScreen extends StatefulWidget {
  final Business business;
  final Map<String, String> staffNames;
  final String? initialPlate;

  const PlateHistoryScreen({super.key, required this.business, required this.staffNames, this.initialPlate});

  @override
  State<PlateHistoryScreen> createState() => _PlateHistoryScreenState();
}

class _PlateHistoryScreenState extends State<PlateHistoryScreen> {
  late final _plate = TextEditingController(text: widget.initialPlate ?? '');
  List<WorkOrder>? _orders;

  @override
  void initState() {
    super.initState();
    if ((widget.initialPlate ?? '').isNotEmpty) _search(widget.initialPlate!);
  }

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  Future<void> _search(String value) async {
    final list = await ServicesRepository.instance.ordersByPlate(widget.business.id, value);
    if (mounted) setState(() => _orders = list);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = _orders;
    final paid = list?.where((o) => o.status == WorkOrder.delivered).toList() ?? const <WorkOrder>[];
    final spent = paid.fold(0.0, (s, o) => s + o.total);
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    String date(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(title: const Text('Historial por placa')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            TextField(
              controller: _plate,
              autofocus: (widget.initialPlate ?? '').isEmpty,
              textCapitalization: TextCapitalization.characters,
              onChanged: _search,
              decoration: const InputDecoration(hintText: 'Escribe la placa', prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: AppSpace.lg),
            if (list != null && list.isEmpty && _plate.text.trim().isNotEmpty)
              Text('Esa placa no ha venido.', style: TextStyle(color: c.inkMuted)),
            if (list != null && list.isNotEmpty) ...[
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${paid.length} ${paid.length == 1 ? 'visita' : 'visitas'}',
                              style: TextStyle(color: c.ink, fontWeight: FontWeight.bold, fontSize: 18)),
                          Text('Última: ${date(list.first.createdAt)}', style: TextStyle(color: c.inkMuted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Ha gastado', style: TextStyle(color: c.inkMuted, fontSize: 12)),
                        Text(CurrencyFormatter.format(spent), style: TextStyle(color: c.ink, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              for (final o in list) ...[
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(date(o.createdAt), style: TextStyle(color: c.ink, fontWeight: FontWeight.w600))),
                          Text(
                            o.status == WorkOrder.delivered
                                ? CurrencyFormatter.format(o.total)
                                : WorkOrder.statusLabel(o.status, ServiceType.of(widget.business.serviceType)),
                            style: TextStyle(color: c.ink, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Text(o.lines.map((l) => l.name).join(', '), style: TextStyle(color: c.ink, fontSize: 13)),
                      if (o.staffIds.isNotEmpty)
                        Text(
                          'Atendió: ${o.staffIds.map((id) => widget.staffNames[id] ?? 'Empleado').join(', ')}',
                          style: TextStyle(color: c.inkMuted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
