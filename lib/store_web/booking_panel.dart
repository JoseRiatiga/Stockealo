import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_tokens.dart';
import '../core/utils/currency_formatter.dart';
import '../core/widgets/app_toast.dart';
import '../features/store/data/booking_service.dart';
import '../features/store/data/online_store_service.dart';

/// «Reservar cita» en la tienda (0.14.0, Pro Servicios): servicio, con quién, día y
/// hora libre. La cita llega al negocio «Por confirmar» en Servicios › Agenda.
class BookingPanel extends StatefulWidget {
  final PublicStore store;
  final PublicBooking booking;

  const BookingPanel({super.key, required this.store, required this.booking});

  @override
  State<BookingPanel> createState() => _BookingPanelState();
}

class _BookingPanelState extends State<BookingPanel> {
  final Set<String> _services = {};
  String? _staffId;
  // Con la hora del negocio (0.16.9): «hoy» es el de allá
  late DateTime _day = widget.booking.now;
  DateTime? _slot;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _sending = false;
  bool _done = false;

  static final _hour = DateFormat('h:mm a', 'es_CO');
  static final _dayShort = DateFormat('EEE d', 'es_CO');
  static final _dayLong = DateFormat("EEEE d 'de' MMMM", 'es_CO');

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  int get _minutes {
    final m = widget.booking.services.where((s) => _services.contains(s.id)).fold<int>(0, (t, s) => t + s.durationMin);
    return m == 0 ? 30 : m;
  }

  double get _total => widget.booking.services.where((s) => _services.contains(s.id)).fold(0.0, (t, s) => t + s.price);

  Future<void> _send() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      AppToast.showWarning(context, 'Escribe tu nombre y tu celular para confirmarte la cita.');
      return;
    }
    setState(() => _sending = true);
    try {
      await BookingService.instance.create(
        slug: widget.store.slug,
        name: _name.text,
        phone: _phone.text,
        serviceIds: _services.toList(),
        staffId: _staffId,
        // La hora elegida es la del negocio: se guarda la hora real con su zona
        startsAt: widget.booking.instantOf(_slot!),
      );
      if (mounted) setState(() => _done = true);
    } on BookingException catch (e) {
      if (mounted) AppToast.showWarning(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _whatsApp() async {
    final names = widget.booking.services.where((s) => _services.contains(s.id)).map((s) => s.name).join(', ');
    final text = 'Hola ${widget.store.businessName}, pedí una cita para el ${_dayLong.format(_slot!)} '
        'a las ${_hour.format(_slot!)} ($names). Soy ${_name.text.trim()}.';
    await launchUrl(Uri.parse('https://wa.me/${widget.store.whatsapp}?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  }

  /// «Te esperamos en …» con «Cómo llegar» (0.16.9, dirección de «Datos del recibo»)
  Widget _address() {
    final address = widget.store.shownAddress;
    if (address == null) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Row(
        children: [
          Icon(Icons.place_outlined, size: 18, color: c.accent),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text('Te esperamos en $address', style: AppText.small(context, color: c.ink))),
          TextButton(
            onPressed: () => launchUrl(PublicStore.mapsUrl(address, businessName: widget.store.businessName),
                mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank'),
            child: const Text('Cómo llegar'),
          ),
        ],
      ),
    );
  }

  /// «Horas de Bogotá»: el nombre de la ciudad de la zona del negocio
  static String? cityOf(String? zone) {
    if (zone == null || !zone.contains('/')) return null;
    const names = {
      'Bogota': 'Bogotá',
      'Mexico_City': 'Ciudad de México',
      'Buenos_Aires': 'Buenos Aires',
      'New_York': 'Nueva York',
      'Los_Angeles': 'Los Ángeles',
      'Cancun': 'Cancún',
      'Merida': 'Mérida',
      'Panama': 'Panamá',
      'Asuncion': 'Asunción',
    };
    final last = zone.split('/').last;
    return names[last] ?? last.replaceAll('_', ' ');
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xs),
        child: Text(t, style: AppText.small(context, weight: FontWeight.w700, color: context.colors.ink)),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = widget.booking;
    if (_done) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_available_outlined, size: 48, color: c.accent),
          const SizedBox(height: AppSpace.sm),
          Text('¡Listo! Tu cita queda por confirmar', textAlign: TextAlign.center, style: AppText.title(context)),
          Text('${_dayLong.format(_slot!)} a las ${_hour.format(_slot!)}', textAlign: TextAlign.center, style: AppText.body(context)),
          const SizedBox(height: AppSpace.sm),
          Text('${widget.store.businessName} te confirma por WhatsApp.', textAlign: TextAlign.center, style: AppText.small(context)),
          _address(),
          const SizedBox(height: AppSpace.lg),
          FilledButton.icon(
            onPressed: _whatsApp,
            icon: const Icon(Icons.chat_outlined, size: 18),
            label: const Text('Avisar por WhatsApp'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      );
    }
    final today = b.now;
    final days = [for (var i = 0; i < 14; i++) today.add(Duration(days: i))]
        .where((d) => b.schedule == null || b.schedule!.isEmpty || b.schedule!.on(d) != null)
        .toList();
    final slots = _services.isEmpty ? const <DateTime>[] : b.freeSlots(_day, _minutes, staffId: _staffId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label('1. ¿Qué servicio?'),
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            for (final s in b.services)
              FilterChip(
                label: Text('${s.name} · ${CurrencyFormatter.formatIn(s.price, widget.store.currency)}'),
                selected: _services.contains(s.id),
                onSelected: (v) => setState(() {
                  v ? _services.add(s.id) : _services.remove(s.id);
                  _slot = null;
                }),
              ),
          ],
        ),
        if (b.staff.isNotEmpty) ...[
          _label('2. ¿Con quién?'),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              ChoiceChip(label: const Text('Con quien esté libre'), selected: _staffId == null, onSelected: (_) => setState(() {
                    _staffId = null;
                    _slot = null;
                  })),
              for (final p in b.staff)
                ChoiceChip(label: Text(p.name), selected: _staffId == p.id, onSelected: (_) => setState(() {
                      _staffId = p.id;
                      _slot = null;
                    })),
            ],
          ),
        ],
        _label('${b.staff.isNotEmpty ? 3 : 2}. ¿Qué día?'),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final d in days)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.xs),
                  child: ChoiceChip(
                    label: Text(DateUtils.isSameDay(d, today) ? 'Hoy' : _dayShort.format(d)),
                    selected: DateUtils.isSameDay(d, _day),
                    onSelected: (_) => setState(() {
                      _day = d;
                      _slot = null;
                    }),
                  ),
                ),
            ],
          ),
        ),
        _label('${b.staff.isNotEmpty ? 4 : 3}. ¿A qué hora?'
            '${cityOf(b.zone) == null ? '' : ' (horas de ${cityOf(b.zone)})'}'),
        if (_services.isEmpty)
          Text('Primero elige el servicio.', style: AppText.small(context))
        else if (slots.isEmpty)
          Text('No quedan horas libres ese día. Prueba otro.', style: AppText.small(context))
        else
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final s in slots)
                ChoiceChip(label: Text(_hour.format(s)), selected: _slot == s, onSelected: (_) => setState(() => _slot = s)),
            ],
          ),
        if (_slot != null) ...[
          _address(),
          _label('Tus datos'),
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Tu nombre')),
          const SizedBox(height: AppSpace.sm),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Tu celular')),
          const SizedBox(height: AppSpace.lg),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _sending ? null : _send,
            child: Text(_sending
                ? 'Pidiendo tu cita…'
                : 'Pedir cita · ${_hour.format(_slot!)} · ${CurrencyFormatter.formatIn(_total, widget.store.currency)}'),
          ),
        ],
      ],
    );
  }
}
