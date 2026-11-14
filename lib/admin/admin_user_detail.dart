import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/design/country_flag.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/currency_formatter.dart';
import '../core/widgets/app_toast.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_widgets.dart';
import '../core/design/app_dialog.dart';

/// Ficha de soporte de una cuenta: sus datos, sus negocios, su Pro, los códigos que
/// canjeó y sus pagos. Nunca productos, ventas, clientes ni ganancias.
class AdminUserDetailDialog extends StatefulWidget {
  final String email;
  const AdminUserDetailDialog({super.key, required this.email});

  static Future<void> show(BuildContext context, String email) =>
      showDialog<void>(context: context, builder: (_) => AdminUserDetailDialog(email: email));

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loadNotes();
    setState(() => _error = null);
    try {
      final d = await ProAdminService.instance.userDetail(widget.email);
      if (mounted) setState(() => _detail = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _giveProTo(AdminUserBusiness b) async {
    final days = await showDialog<int?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Dar Pro a ${b.name}'),
        children: [
          for (final d in const <int?>[7, 30, 90, 365, -1])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Text(switch (d) { 7 => '1 semana', 30 => '1 mes', 90 => '3 meses', 365 => '1 año', _ => 'Permanente' }),
            ),
        ],
      ),
    );
    if (days == null || !mounted) return;
    try {
      await ProAdminService.instance.grantPro(b.id, days == -1 ? null : days);
      if (!mounted) return;
      AppToast.show(context, message: '${b.name} ahora tiene Pro', type: ToastType.success);
      _load();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = _detail;
    Widget body;
    if (_error != null) {
      body = Text(_error!, style: TextStyle(color: c.danger));
    } else if (d == null) {
      body = const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
    } else {
      body = _content(c, d);
    }
    return AppDialog(
      title: d?.name?.trim().isNotEmpty == true ? d!.name!.trim() : widget.email,
      content: SizedBox(width: 560, child: SingleChildScrollView(child: body)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }

  Widget _section(StockealoColors c, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: AppText.sizeSmall, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: AppSpace.sm),
            ...children,
          ],
        ),
      );

  Widget _line(StockealoColors c, String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: TextStyle(fontSize: AppText.sizeSmall, color: color ?? c.inkMuted)),
      );

  Widget _content(StockealoColors c, AdminUserDetail d) {
    final wa = whatsappDigits(d.phone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cuenta
        _line(c, d.email, color: c.ink),
        if (d.phone?.isNotEmpty == true) _line(c, 'Celular: ${d.phone}'),
        _line(c, 'Entra con: ${d.providerLabel} · '
            '${d.emailConfirmedAt == null ? 'correo SIN confirmar' : 'correo confirmado'}'),
        _line(c, 'Registro ${adminDate(d.createdAt)} · Último inicio de sesión ${adminDateTime(d.lastSignInAt)}'),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            if (wa != null)
              ActionChip(
                avatar: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('WhatsApp'),
                onPressed: () => launchUrl(Uri.parse('https://wa.me/$wa'), webOnlyWindowName: '_blank'),
              ),
            ActionChip(
              avatar: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copiar correo'),
              onPressed: () => adminCopy(context, d.email, 'Correo'),
            ),
            if (_notesAvailable && ProAdminService.instance.canSupport)
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

        if (_notesAvailable)
          _section(c, 'Notas internas', [
            Text('Solo las ve el equipo del panel.', style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint)),
            const SizedBox(height: AppSpace.sm),
            if (ProAdminService.instance.canSupport)
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
                subtitle: Text('${n['author_email']} · ${adminDateTime(DateTime.tryParse('${n['created_at']}')?.toLocal())}'),
                trailing: ProAdminService.instance.canSupport
                    ? IconButton(
                        tooltip: 'Borrar nota',
                        icon: Icon(Icons.delete_outline_outlined, size: 18, color: c.inkMuted),
                        onPressed: () => _deleteNote((n['id'] as num).toInt()),
                      )
                    : null,
              ),
          ]),

        _section(c, 'Negocios', [
          if (d.businesses.isEmpty)
            _line(c, 'No tiene ningún negocio en la nube. Si ya usa la app, sus datos están solo en su '
                'celular o navegador: conviene escribirle para que active la sincronización.',
                color: c.warning),
          for (final b in d.businesses)
            AdminCard(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                children: [
                  if (b.country != null) ...[CountryFlag(code: b.country!, width: 22), const SizedBox(width: AppSpace.sm)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(b.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          AdminBadge(b.roleLabel),
                          if (b.pro) ...[const SizedBox(width: 4), const AdminBadge('Pro', tone: AdminTone.good)],
                        ]),
                        Text(
                          [
                            b.pro ? (b.proUntil == null ? 'Pro permanente' : 'Pro hasta ${adminDate(b.proUntil)}') : 'Sin Pro',
                            if (b.storeSlug != null) 'tienda ${b.storeEnabled ? 'publicada' : 'apagada'}',
                          ].join(' · '),
                          style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint),
                        ),
                      ],
                    ),
                  ),
                  if (b.role == 'OWNER' && ProAdminService.instance.isOwner)
                    TextButton(onPressed: () => _giveProTo(b), child: const Text('Dar Pro')),
                ],
              ),
            ),
        ]),

        _section(c, 'Historial de Pro', [
          if (d.subscriptions.isEmpty && d.redemptions.isEmpty && d.payments.isEmpty)
            _line(c, 'Nunca ha tenido Pro.'),
          for (final s in d.subscriptions)
            _line(
              c,
              '${s['business'] ?? 'Pro Global'} · ${s['source'] == 'manual' ? 'dado a mano' : s['source'] == 'code' ? 'código' : 'pago'} · '
              'desde ${adminDate(DateTime.tryParse('${s['starts_at']}'))} · '
              '${s['ends_at'] == null ? 'permanente' : 'hasta ${adminDate(DateTime.tryParse('${s['ends_at']}'))}'}'
              '${s['active'] == true ? ' · activa' : ''}',
            ),
          for (final r in d.redemptions)
            _line(c, 'Canjeó ${r['code']} ${r['business'] == null ? '' : 'en ${r['business']} '}'
                'el ${adminDate(DateTime.tryParse('${r['redeemed_at']}'))}'),
          for (final p in d.payments)
            _line(
              c,
              'Pago ${CurrencyFormatter.formatIn(((p['amount_in_cents'] as num?) ?? 0) / 100, '${p['currency'] ?? 'COP'}')} · '
              '${p['plan_id']} · ${_statusLabel('${p['status']}')} · ${adminDate(DateTime.tryParse('${p['created_at']}'))}',
              color: p['status'] == 'APPROVED' ? c.inkMuted : c.warning,
            ),
        ]),

        Padding(
          padding: const EdgeInsets.only(top: AppSpace.lg),
          child: Text(
            'Por privacidad, aquí no se ven productos, ventas, clientes ni ganancias de los negocios.',
            style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint),
          ),
        ),
      ],
    );
  }

  static String _statusLabel(String s) => switch (s) {
        'APPROVED' => 'aprobado',
        'DECLINED' => 'rechazado',
        'VOIDED' => 'anulado',
        'ERROR' => 'con error',
        _ => 'pendiente',
      };
}
