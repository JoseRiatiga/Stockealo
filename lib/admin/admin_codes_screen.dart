import 'package:flutter/material.dart';

import '../core/design/primary_action_button.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/app_toast.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_widgets.dart';

/// Duraciones que se ofrecen; null = permanente
const _durations = <int?>[1, 7, 30, 90, 365, null];

/// Plazos para canjear; null = sin vencimiento
const _validities = <int?>[null, 7, 30, 90];

/// Códigos Pro: crear, buscar, copiar el mensaje para el cliente y desactivar
class AdminCodesPage extends StatefulWidget {
  const AdminCodesPage({super.key});

  @override
  State<AdminCodesPage> createState() => _AdminCodesPageState();
}

class _AdminCodesPageState extends State<AdminCodesPage> {
  final _admin = ProAdminService.instance;
  final _noteController = TextEditingController();

  String _kind = 'business';
  int? _days = 30;
  int? _validDays;
  int _count = 1;
  int _maxUses = 1;
  bool _creating = false;
  List<ProCode> _created = const [];

  List<ProCode> _codes = const [];
  String _search = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCodes();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadCodes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final codes = await _admin.listCodes(search: _search);
      if (mounted) setState(() => _codes = codes);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    setState(() => _creating = true);
    try {
      final codes = await _admin.createCodes(
        kind: _kind,
        days: _days,
        count: _count,
        maxUses: _maxUses,
        note: _noteController.text.trim(),
        validDays: _validDays,
      );
      if (!mounted) return;
      final now = DateTime.now();
      setState(() => _created = [
            for (final code in codes)
              ProCode(
                code: code,
                kind: _kind,
                days: _days,
                maxUses: _maxUses,
                uses: 0,
                note: null,
                createdAt: now,
                expiresAt: _validDays == null ? null : now.add(Duration(days: _validDays!)),
              ),
          ]);
      _noteController.clear();
      _loadCodes();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _disable(ProCode code) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Desactivar ${code.code}?'),
        content: const Text('Nadie más podrá canjearlo. Quien ya lo canjeó conserva su Pro.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desactivar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _admin.disableCode(code.code);
      if (mounted) AppToast.show(context, message: 'Código desactivado', type: ToastType.success);
      _loadCodes();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    }
  }

  static String durationText(int? days) => switch (days) {
        null => 'Permanente',
        1 => '1 día',
        7 => '1 semana',
        30 => '1 mes',
        90 => '3 meses',
        365 => '1 año',
        _ => '$days días',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AdminLoadState(
      loading: _loading,
      error: _error,
      empty: _codes.isEmpty,
      emptyText: _search.isEmpty ? 'Todavía no hay códigos.' : 'No hay códigos con "$_search".',
      onRetry: _loadCodes,
    );
    return AdminPage(
      title: 'Códigos',
      subtitle: 'Crea códigos Pro para entregar después de cada pago',
      onRefresh: _loadCodes,
      children: [
        AdminCard(child: _form(c)),
        if (_created.isNotEmpty) _createdCard(c),
        const SizedBox(height: AppSpace.lg),
        Text('Últimos códigos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: AppSpace.sm),
        AdminSearchField(
          hint: 'Buscar por código, nota o correo',
          onSubmitted: (v) {
            _search = v;
            _loadCodes();
          },
        ),
        if (state.blocking) state else for (final code in _codes) _codeRow(c, code),
      ],
    );
  }

  Widget _label(StockealoColors c, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Text(text, style: TextStyle(fontSize: 13, color: c.inkMuted)),
      );

  Widget _chips<T>(List<T> values, T selected, String Function(T) label, ValueChanged<T> onSelect) => Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        children: [
          for (final v in values)
            ChoiceChip(label: Text(label(v)), selected: selected == v, onSelected: (_) => setState(() => onSelect(v))),
        ],
      );

  Widget _form(StockealoColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Crear códigos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: AppSpace.md),
        _label(c, 'Plan'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'business', label: Text('Pro Negocio')),
            ButtonSegment(value: 'global', label: Text('Pro Global')),
            ButtonSegment(value: 'services', label: Text('Pro Servicios')),
          ],
          selected: {_kind},
          onSelectionChanged: (v) => setState(() => _kind = v.first),
        ),
        const SizedBox(height: AppSpace.lg),
        _label(c, 'Duración de Pro'),
        _chips<int?>(_durations, _days, durationText, (v) => _days = v),
        const SizedBox(height: AppSpace.lg),
        _label(c, 'Plazo para canjearlo'),
        _chips<int?>(_validities, _validDays, (v) => v == null ? 'Sin vencimiento' : '$v días', (v) => _validDays = v),
        const SizedBox(height: AppSpace.lg),
        Row(
          children: [
            Expanded(child: _stepper(c, 'Cantidad', _count, 1, 50, (v) => setState(() => _count = v))),
            const SizedBox(width: AppSpace.md),
            Expanded(child: _stepper(c, 'Usos por código', _maxUses, 1, 1000, (v) => setState(() => _maxUses = v))),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        TextField(
          controller: _noteController,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nota (opcional)',
            hintText: 'Ej.: Pago Nequi de Ana, prueba',
            prefixIcon: Icon(Icons.sticky_note_2_outlined),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        PrimaryActionButton(
          label: _creating ? 'Creando…' : (_count == 1 ? 'Crear código' : 'Crear $_count códigos'),
          icon: Icons.add_rounded,
          onPressed: _creating ? null : _create,
        ),
      ],
    );
  }

  Widget _stepper(StockealoColors c, String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(c, label),
        Container(
          decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.control)),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Menos',
                onPressed: value > min ? () => onChanged(value - 1) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Text('$value',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
              ),
              IconButton(
                tooltip: 'Más',
                onPressed: value < max ? () => onChanged(value + 1) : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _createdCard(StockealoColors c) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(color: c.successSoft, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: c.success),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  _created.length == 1 ? 'Código creado' : '${_created.length} códigos creados',
                  style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
                ),
              ),
              if (_created.length > 1)
                TextButton(
                  onPressed: () => adminCopy(context, _created.map((e) => e.code).join('\n'), 'Códigos'),
                  child: const Text('Copiar todos'),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          for (final code in _created)
            Row(
              children: [
                Expanded(
                  child: SelectableText(code.code,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: c.ink)),
                ),
                TextButton.icon(
                  onPressed: () => adminCopy(context, code.shareMessage(), 'Mensaje'),
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: const Text('Mensaje'),
                ),
                IconButton(
                  tooltip: 'Copiar código',
                  onPressed: () => adminCopy(context, code.code, 'Código'),
                  icon: Icon(Icons.copy_rounded, size: 20, color: c.inkMuted),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _codeRow(StockealoColors c, ProCode code) {
    final status = code.statusLabel();
    final tone = code.exhausted || code.isExpired()
        ? AdminTone.neutral
        : (code.uses > 0 ? AdminTone.warn : AdminTone.good);
    return AdminCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(code.code,
                          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1, color: c.ink)),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    AdminBadge(status, tone: tone),
                  ],
                ),
                Text(
                  [
                    code.kindLabel,
                    code.durationLabel,
                    'Creado ${adminDate(code.createdAt)}',
                    if (code.expiresAt != null) 'Canjear antes del ${adminDate(code.expiresAt)}',
                    if (code.note?.isNotEmpty == true) code.note!,
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: c.inkMuted),
                ),
                if (code.redeemedBy != null)
                  Text('Canjeado por ${code.redeemedBy}', style: TextStyle(fontSize: 12, color: c.inkMuted)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar código',
            onPressed: () => adminCopy(context, code.code, 'Código'),
            icon: Icon(Icons.copy_rounded, size: 20, color: c.inkMuted),
          ),
          PopupMenuButton<String>(
            tooltip: 'Más',
            onSelected: (v) => v == 'message' ? adminCopy(context, code.shareMessage(), 'Mensaje') : _disable(code),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'message', child: Text('Copiar mensaje para WhatsApp')),
              if (code.canDisable()) const PopupMenuItem(value: 'disable', child: Text('Desactivar')),
            ],
          ),
        ],
      ),
    );
  }
}
