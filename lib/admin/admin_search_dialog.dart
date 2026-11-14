import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../core/utils/currency_formatter.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_shell.dart';
import 'admin_user_detail.dart';
import 'admin_widgets.dart';
import '../features/pro/data/pro_service.dart' show proKindLabel;
import '../core/design/app_dialog.dart';

/// Búsqueda global del panel: cuentas, negocios, códigos Pro y pagos en un solo lugar
class AdminSearchDialog extends StatefulWidget {
  final ValueChanged<AdminSection> onOpenSection;
  const AdminSearchDialog({super.key, required this.onOpenSection});

  static Future<void> show(BuildContext context, {required ValueChanged<AdminSection> onOpenSection}) =>
      showDialog<void>(context: context, builder: (_) => AdminSearchDialog(onOpenSection: onOpenSection));

  @override
  State<AdminSearchDialog> createState() => _AdminSearchDialogState();
}

class _AdminSearchDialogState extends State<AdminSearchDialog> {
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;
  String _query = '';
  Timer? _debounce;
  int _id = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _query = q.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _run);
  }

  Future<void> _run() async {
    final id = ++_id;
    if (_query.length < 2) {
      setState(() => _result = null);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ProAdminService.instance.search(_query);
      if (mounted && id == _id) setState(() => _result = r);
    } catch (e) {
      if (mounted && id == _id) setState(() => _error = '$e');
    } finally {
      if (mounted && id == _id) setState(() => _loading = false);
    }
  }

  void _openUser(String email) {
    Navigator.pop(context);
    AdminUserDetailDialog.show(context, email);
  }

  void _openSection(AdminSection s) {
    Navigator.pop(context);
    widget.onOpenSection(s);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = _result;
    List<Map<String, dynamic>> list(String key) =>
        [for (final x in (r?[key] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    final users = list('users'), businesses = list('businesses'), codes = list('codes'), payments = list('payments');
    final empty = r != null && users.isEmpty && businesses.isEmpty && codes.isEmpty && payments.isEmpty;

    Widget header(String text) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.md, bottom: 4),
          child: Text(text, style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w700, color: c.inkMuted)),
        );
    Widget item(IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: c.inkMuted),
          title: Text(title, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle, overflow: TextOverflow.ellipsis),
          onTap: onTap,
        );

    return AppDialog(
      title: 'Buscar',
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText: 'Correo, nombre, negocio, código Pro o referencia de pago',
                prefixIcon: Icon(Icons.search_outlined),
              ),
            ),
            SizedBox(height: 3, child: _loading ? const LinearProgressIndicator() : null),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.md),
                        child: Text(_error!, style: TextStyle(color: c.danger)),
                      ),
                    if (r == null && _error == null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.md),
                        child: Text('Escribe al menos 2 letras.', style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkFaint)),
                      ),
                    if (empty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.md),
                        child: Text('Nada coincide con "$_query".', style: TextStyle(color: c.inkMuted)),
                      ),
                    if (users.isNotEmpty) header('Cuentas'),
                    for (final u in users)
                      item(Icons.person_outline_outlined, '${u['name'] ?? u['email']}', '${u['email']}',
                          () => _openUser('${u['email']}')),
                    if (businesses.isNotEmpty) header('Negocios'),
                    for (final b in businesses)
                      item(Icons.store_mall_directory_outlined, '${b['name']}', '${b['owner_email'] ?? 'sin dueño'}',
                          () => b['owner_email'] == null ? _openSection(AdminSection.businesses) : _openUser('${b['owner_email']}')),
                    if (codes.isNotEmpty) header('Códigos Pro'),
                    for (final k in codes)
                      item(
                        Icons.confirmation_number_outlined,
                        '${k['code']}',
                        '${proKindLabel(k['kind'] as String?)} · '
                            '${k['days'] == null ? 'permanente' : '${k['days']} días'} · ${k['uses']}/${k['max_uses']} usos'
                            '${(k['note'] ?? '').toString().isEmpty ? '' : ' · ${k['note']}'}',
                        () => adminCopy(context, '${k['code']}', 'Código'),
                      ),
                    if (payments.isNotEmpty) header('Pagos'),
                    for (final p in payments)
                      item(
                        Icons.payments_outlined,
                        '${p['reference']}',
                        '${p['user_email']} · ${CurrencyFormatter.formatIn(((p['amount_in_cents'] as num?) ?? 0) / 100, 'COP')} · '
                            '${p['status']} · ${adminDate(DateTime.tryParse('${p['created_at']}'))}',
                        () => _openUser('${p['user_email']}'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}
