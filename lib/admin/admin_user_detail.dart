import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/design/app_dialog.dart';
import '../core/design/country_flag.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/currency_formatter.dart';
import '../core/widgets/app_toast.dart';
import '../features/pro/data/pro_admin_service.dart';
import '../features/pro/data/pro_service.dart' show proKindLabel, proPlanIdLabel;
import 'admin_widgets.dart';

/// Ficha de soporte de una cuenta: sus datos, sus negocios, su Pro, los códigos que
/// canjeó y sus pagos. Nunca productos, ventas, clientes ni ganancias.
///
/// Re-diseño del panel (boceto aprobado el 24 nov): cabecera con iniciales, datos con
/// ícono, negocios como tarjetas (plan, vencimiento, sedes) e historial de Pro con un
/// punto de color por estado y nombres legibles.
class AdminUserDetailDialog extends StatefulWidget {
  final String email;
  const AdminUserDetailDialog({super.key, required this.email});

  /// La ficha entra por la derecha (en el celular sube desde abajo)
  static Future<void> show(BuildContext context, String email) => AppSidePanel.show<void>(
        context: context,
        title: 'Ficha del cliente',
        subtitle: email,
        width: 560,
        builder: (_) => AdminUserDetailDialog(email: email),
      );

  @override
  State<AdminUserDetailDialog> createState() => _AdminUserDetailDialogState();
}

class _AdminUserDetailDialogState extends State<AdminUserDetailDialog> {
  AdminUserDetail? _detail;
  String? _error;
  List<Map<String, dynamic>> _notes = const [];
  Map<String, dynamic>? _contacted;
  bool _notesAvailable = true;
  final _noteInput = TextEditingController();
  bool _savingNote = false;

  /// Cupos de sede de cada negocio del que es dueño (sedes «0 de 3»)
  Map<String, AdminBranchSlots?> _slots = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteInput.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    try {
      final r = await ProAdminService.instance.notes(widget.email);
      if (!mounted) return;
      setState(() {
        _notes = [for (final n in (r['notes'] as List? ?? const [])) Map<String, dynamic>.from(n as Map)];
        _contacted = r['contacted'] == null ? null : Map<String, dynamic>.from(r['contacted'] as Map);
        _notesAvailable = true;
      });
    } catch (_) {
      if (mounted) setState(() => _notesAvailable = false);
    }
  }

  Future<void> _load() async {
    _loadNotes();
    setState(() => _error = null);
    try {
      final d = await ProAdminService.instance.userDetail(widget.email);
      if (!mounted) return;
      setState(() => _detail = d);
      _loadSlots(d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadSlots(AdminUserDetail d) async {
    final out = <String, AdminBranchSlots?>{};
    for (final b in d.businesses.where((b) => b.role == 'OWNER')) {
      out[b.id] = await ProAdminService.instance.branchSlots(b.id);
    }
    if (mounted) setState(() => _slots = out);
  }

  Future<void> _addNote() async {
    final text = _noteInput.text.trim();
    if (text.isEmpty) return;
    setState(() => _savingNote = true);
    try {
      await ProAdminService.instance.addNote(widget.email, text);
      _noteInput.clear();
      await _loadNotes();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  Future<void> _deleteNote(int id) async {
    try {
      await ProAdminService.instance.deleteNote(id);
      await _loadNotes();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    }
  }

  Future<void> _toggleContacted() async {
    try {
      await ProAdminService.instance.setContacted(widget.email, _contacted == null);
      await _loadNotes();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    }
  }

  /// Sedes (0.18.0): cupos de sedes extra para un negocio. 0.18.1: dice cuántos tiene ya
  /// y hasta cuándo, y no da más tiempo del que le queda al plan (el cupo vence con él).
  Future<void> _giveSlotsTo(AdminUserBusiness b) async {
    final info = _slots[b.id] ?? await ProAdminService.instance.branchSlots(b.id);
    if (!mounted) return;
    final planEnd = b.pro ? b.proUntil : null;
    // Redondeado hacia arriba: con .inDays el cupo vencía unas horas antes que el plan
    final daysLeft = planEnd == null ? null : (planEnd.difference(DateTime.now()).inHours / 24).ceil().clamp(1, 366);
    int cap(int days) => daysLeft == null ? days : (days < daysLeft ? days : daysLeft);
    String length(int days) =>
        daysLeft != null && days >= daysLeft ? 'Hasta el fin de su plan (${adminDate(planEnd)})' : (days >= 365 ? 'Por 1 año' : 'Por 1 mes');
    final options = <(int, int)>{for (final (slots, days) in const [(1, 30), (2, 30), (3, 30), (1, 365)]) (slots, cap(days))}.toList();
    final c = context.colors;
    final choice = await adminChoose<(int, int)>(
      context,
      title: 'Cupos de sede',
      subtitle: b.name,
      icon: Icons.place_outlined,
      info: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!b.pro)
            Text('Sin Pro activo: los cupos no cuentan hasta que tenga Pro.',
                style: AppText.small(context, weight: FontWeight.w600, color: c.warning)),
          Text(
            info == null
                ? 'No se pudo leer cuántos cupos tiene.'
                : 'Puede tener ${info.allowance} ${info.allowance == 1 ? 'sede extra' : 'sedes extra'} '
                    'y tiene ${info.open} ${info.open == 1 ? 'abierta' : 'abiertas'}.',
            style: AppText.small(context, color: c.inkMuted),
          ),
          for (final s in info?.slots ?? const <({int slots, DateTime endsAt})>[])
            Text('${s.slots} ${s.slots == 1 ? 'cupo' : 'cupos'} hasta el ${adminDate(s.endsAt)}',
                style: AppText.small(context, color: c.inkMuted)),
        ],
      ),
      options: [
        for (final (slots, days) in options)
          AdminChoice((slots, days), 'Dar $slots ${slots == 1 ? 'sede' : 'sedes'}', detail: length(days)),
      ],
    );
    if (choice == null || !mounted) return;
    try {
      final allowed = await ProAdminService.instance.grantBranchSlots(b.id, choice.$1, choice.$2);
      if (!mounted) return;
      AppToast.show(context, message: '${b.name} puede tener $allowed sedes extra', type: ToastType.success);
      if (_detail != null) _loadSlots(_detail!);
    } catch (e) {
      if (mounted) AppToast.show(context, message: 'No se pudo: $e', type: ToastType.error);
    }
  }

  /// Dar Pro (prueba del 24 nov): antes siempre daba Pro normal, y a un negocio con Pro
  /// Servicios le creaba un Pro aparte que no le sumaba nada. Ahora se elige el plan
  /// (por defecto el que tiene) y se dice claro que es un periodo desde hoy, no que se suma.
  Future<void> _giveProTo(AdminUserBusiness b) async {
    final kind = await adminChoose<String>(
      context,
      title: 'Dar Pro',
      subtitle: b.name,
      icon: Icons.workspace_premium_outlined,
      info: Text(
        b.pro
            ? 'Hoy tiene ${b.planLabel}${b.proUntil == null ? '' : ' hasta el ${adminDate(b.proUntil)}'}. '
                'Lo que des empieza hoy y corre aparte; no se suma al final del plan actual.'
            : 'Hoy no tiene Pro.',
        style: AppText.small(context, color: context.colors.inkMuted),
      ),
      options: [
        if (b.services) ...const [
          AdminChoice('services', 'Pro Servicios', detail: 'El plan que tiene ahora'),
          AdminChoice('business', 'Pro', detail: 'Sin el módulo de Servicios'),
        ] else ...const [
          AdminChoice('business', 'Pro', detail: 'Inventario, ventas y tienda'),
          AdminChoice('services', 'Pro Servicios', detail: 'Pro más el módulo de Servicios y 2 sedes'),
        ],
      ],
    );
    if (kind == null || !mounted) return;
    final days = await adminChoose<int>(
      context,
      title: kind == 'services' ? 'Pro Servicios por…' : 'Pro por…',
      subtitle: b.name,
      icon: Icons.schedule_outlined,
      // Sin permanente (0.17.0): lo más largo es 1 año
      options: const [
        AdminChoice(7, '1 semana'),
        AdminChoice(30, '1 mes'),
        AdminChoice(90, '3 meses'),
        AdminChoice(365, '1 año'),
      ],
    );
    if (days == null || !mounted) return;
    try {
      await ProAdminService.instance.grantPro(b.id, days, kind: kind);
      if (!mounted) return;
      AppToast.show(context, message: '${b.name} ahora tiene ${kind == 'services' ? 'Pro Servicios' : 'Pro'}', type: ToastType.success);
      _load();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    if (_error != null) {
      return AdminLoadState(loading: false, error: _error, empty: false, emptyText: '', onRetry: _load);
    }
    if (d == null) return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
    return _content(context.colors, d);
  }

  Widget _content(StockealoColors c, AdminUserDetail d) {
    final wa = whatsappDigits(d.phone);
    final support = ProAdminService.instance.canSupport;
    final name = (d.name ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabecera: iniciales, nombre y desde cuándo es cliente
        Row(
          children: [
            AdminAvatar(adminInitials(d.name, d.email)),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? d.email : name, style: AppText.title(context)),
                  Text(
                    [
                      if (d.createdAt != null) 'Cliente desde ${adminDate(d.createdAt)}',
                      if (d.lastSignInAt != null) 'entró ${adminWhen(d.lastSignInAt)}',
                    ].join(' · '),
                    style: AppText.small(context, color: c.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            if (wa != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('WhatsApp'),
                onPressed: () => launchUrl(Uri.parse('https://wa.me/$wa'), webOnlyWindowName: '_blank'),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copiar correo'),
              onPressed: () => adminCopy(context, d.email, 'Correo'),
            ),
            if (_notesAvailable && support)
              FilterChip(
                avatar: Icon(_contacted == null ? Icons.mark_chat_unread_outlined : Icons.mark_chat_read_outlined, size: 18),
                label: Text(_contacted == null
                    ? 'Marcar como contactado'
                    : 'Contactado ${adminDate(DateTime.tryParse('${_contacted!['at']}')?.toLocal())}'),
                selected: _contacted != null,
                onSelected: (_) => _toggleContacted(),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Divider(height: 1, color: c.line),
        const SizedBox(height: AppSpace.sm),
        AdminInfoRow(
          icon: Icons.mail_outline,
          label: 'Correo',
          value: '${d.email} · ${d.emailConfirmedAt == null ? 'SIN confirmar' : 'confirmado'}',
          valueColor: d.emailConfirmedAt == null ? c.warning : null,
        ),
        if (d.phone?.isNotEmpty == true) AdminInfoRow(icon: Icons.phone_outlined, label: 'Celular', value: d.phone!),
        AdminInfoRow(icon: Icons.login_outlined, label: 'Entra con', value: d.providerLabel),
        AdminInfoRow(icon: Icons.schedule_outlined, label: 'Última entrada', value: adminDateTime(d.lastSignInAt)),

        // Negocios
        AdminBlock(
          title: 'Negocios',
          count: d.businesses.length,
          children: [
            if (d.businesses.isEmpty)
              Text(
                'No tiene ningún negocio en la nube. Si ya usa la app, sus datos están solo en su '
                'celular o navegador: conviene escribirle para que active la sincronización.',
                style: AppText.small(context, color: c.warning),
              ),
            for (final b in d.businesses) _businessCard(c, b),
          ],
        ),

        // Historial de Pro
        AdminBlock(
          title: 'Historial de Pro',
          children: [
            if (d.subscriptions.isEmpty && d.redemptions.isEmpty && d.payments.isEmpty)
              Text('Nunca ha tenido Pro.', style: AppText.small(context, color: c.inkMuted)),
            for (final e in _history(d)) e,
          ],
        ),

        // Notas internas
        if (_notesAvailable)
          AdminBlock(
            title: 'Notas internas',
            note: 'Solo las ve el equipo del panel.',
            children: [
              if (support)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _noteInput,
                        maxLength: 2000,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Ej. Le escribí el 8/11, va a activar la nube',
                          isDense: true,
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    FilledButton(onPressed: _savingNote ? null : _addNote, child: const Text('Agregar')),
                  ],
                ),
              for (final n in _notes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${n['note']}'),
                  subtitle: Text('${n['author_email']} · ${adminWhen(DateTime.tryParse('${n['created_at']}')?.toLocal())}'),
                  trailing: support
                      ? IconButton(
                          tooltip: 'Borrar nota',
                          icon: Icon(Icons.delete_outline_outlined, size: 18, color: c.inkMuted),
                          onPressed: () => _deleteNote((n['id'] as num).toInt()),
                        )
                      : null,
                ),
            ],
          ),

        Padding(
          padding: const EdgeInsets.only(top: AppSpace.lg),
          child: Text(
            'Por privacidad, aquí no se ven productos, ventas, clientes ni ganancias de los negocios.',
            style: AppText.caption(context, color: c.inkFaint),
          ),
        ),
      ],
    );
  }

  /// Un negocio: nombre, rol, plan, vencimiento, tienda y sedes, con sus acciones
  Widget _businessCard(StockealoColors c, AdminUserBusiness b) {
    final owner = b.role == 'OWNER';
    // Dar Pro y cupos: solo el dueño del panel, y solo a negocios de los que la cuenta es dueña
    final canGrant = owner && ProAdminService.instance.isOwner;
    final slots = _slots[b.id];
    final facts = [
      if (b.pro) b.proUntil == null ? 'Sin vencimiento' : 'Vence ${adminDate(b.proUntil)}' else 'Sin Pro',
      if (slots != null && (slots.allowance > 0 || slots.open > 0)) 'Sedes ${slots.open} de ${slots.allowance}',
      b.storeSlug == null ? 'sin tienda' : 'tienda ${b.storeEnabled ? 'publicada' : 'apagada'}',
    ];
    return AdminCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (b.country != null) ...[CountryFlag(code: b.country!, width: 22), const SizedBox(width: AppSpace.sm)],
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: b.name, style: AppText.body(context, weight: FontWeight.w600)),
                    TextSpan(text: '  · ${b.roleLabel}', style: AppText.small(context, color: c.inkMuted)),
                  ]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (b.pro) AdminBadge(b.planLabel, tone: AdminTone.good),
            ],
          ),
          const SizedBox(height: 2),
          Text(facts.join(' · '), style: AppText.small(context, color: c.inkMuted)),
          if (canGrant)
            Wrap(
              spacing: AppSpace.sm,
              children: [
                TextButton(onPressed: () => _giveProTo(b), child: const Text('Dar Pro')),
                TextButton(onPressed: () => _giveSlotsTo(b), child: const Text('Cupos de sede')),
              ],
            ),
        ],
      ),
    );
  }

  /// Suscripciones, canjes y pagos juntos, lo más nuevo arriba
  List<Widget> _history(AdminUserDetail d) {
    final now = DateTime.now();
    final items = <(DateTime, Widget)>[];
    DateTime? date(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal();
    for (final s in d.subscriptions) {
      final start = date(s['starts_at']) ?? DateTime(2000);
      final end = date(s['ends_at']);
      final active = s['active'] == true;
      final how = switch (s['source']) { 'manual' => 'a mano', 'code' => 'con código', _ => 'pagado' };
      items.add((
        start,
        AdminTimelineRow(
          tone: active ? AdminTone.good : AdminTone.neutral,
          text: '${s['business'] ?? 'Pro Global'} · ${proKindLabel(s['kind'] as String?)} $how',
          trailing: end == null ? 'sin vencimiento' : (active ? 'hasta ${adminDate(end)}' : 'terminó ${adminDate(end)}'),
        ),
      ));
    }
    for (final r in d.redemptions) {
      final at = date(r['redeemed_at']) ?? DateTime(2000);
      items.add((
        at,
        AdminTimelineRow(
          tone: AdminTone.neutral,
          text: 'Canjeó ${r['code']}${r['business'] == null ? '' : ' en ${r['business']}'}',
          trailing: adminDate(at),
        ),
      ));
    }
    for (final p in d.payments) {
      final at = date(p['created_at']);
      final state = adminPaymentState('${p['status']}', at, now: now);
      final amount = CurrencyFormatter.formatIn(((p['amount_in_cents'] as num?) ?? 0) / 100, '${p['currency'] ?? 'COP'}');
      items.add((
        at ?? DateTime(2000),
        AdminTimelineRow(
          tone: state.tone,
          text: 'Pago $amount · ${proPlanIdLabel(p['plan_id'] as String?)} · ${state.label.toLowerCase()}',
          trailing: adminDate(at),
        ),
      ));
    }
    items.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final i in items) i.$2];
  }
}
