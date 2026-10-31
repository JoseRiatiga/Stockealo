import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/design/primary_action_button.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/app_toast.dart';
import '../features/pro/data/pro_admin_service.dart';

/// Panel web de administrador: crear códigos Pro y ver los últimos creados.
/// Solo entra una cuenta de app_admins; el servidor lo vuelve a comprobar en cada llamada.
class AdminCodesScreen extends StatefulWidget {
  final String email;
  final VoidCallback onSignOut;

  const AdminCodesScreen({super.key, required this.email, required this.onSignOut});

  @override
  State<AdminCodesScreen> createState() => _AdminCodesScreenState();
}

/// Duraciones que se ofrecen; null = permanente
const _durations = <int?>[1, 7, 30, 90, 365, null];

class _AdminCodesScreenState extends State<AdminCodesScreen> {
  final _admin = ProAdminService.instance;
  final _noteController = TextEditingController();

  String _kind = 'business';
  int? _days = 30;
  int _count = 1;
  int _maxUses = 1;
  bool _creating = false;
  List<String> _created = const [];

  List<ProCode> _codes = const [];
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
      final codes = await _admin.listCodes();
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
      );
      if (!mounted) return;
      setState(() => _created = codes);
      _noteController.clear();
      _loadCodes();
    } catch (e) {
      if (mounted) AppToast.show(context, message: '$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) AppToast.show(context, message: '$label copiado', type: ToastType.success);
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
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        title: const Text('Stockealo · Administrador'),
        actions: [
          Center(child: Text(widget.email, style: TextStyle(fontSize: 13, color: c.inkMuted))),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: widget.onSignOut,
            icon: Icon(Icons.logout_rounded, color: c.inkMuted),
          ),
          const SizedBox(width: AppSpace.sm),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCodes,
        child: ListView(
          // En pantallas anchas el contenido queda centrado y legible
          padding: EdgeInsets.fromLTRB(
            AppSpace.lg + _sideGutter(context), AppSpace.lg, AppSpace.lg + _sideGutter(context), AppSpace.xxl),
          children: [
            _card(c, title: 'Crear códigos Pro', child: _form(c)),
            if (_created.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              _createdCard(c),
            ],
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                Expanded(
                  child: Text('Últimos códigos', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
                ),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _loading ? null : _loadCodes,
                  icon: Icon(Icons.refresh_rounded, color: c.inkMuted),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            if (_loading)
              const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(_error!, style: TextStyle(color: c.danger))
            else if (_codes.isEmpty)
              Text('Todavía no hay códigos.', style: TextStyle(color: c.inkMuted))
            else
              for (final code in _codes) _codeRow(c, code),
          ],
        ),
      ),
    );
  }

  static double _sideGutter(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width > 760 ? (width - 720) / 2 : 0;
  }

  Widget _card(StockealoColors c, {required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: AppSpace.md),
          child,
        ],
      ),
    );
  }

  Widget _label(StockealoColors c, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Text(text, style: TextStyle(fontSize: 13, color: c.inkMuted)),
      );

  Widget _form(StockealoColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(c, 'Plan'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'business', label: Text('Pro Negocio')),
            ButtonSegment(value: 'global', label: Text('Pro Global')),
          ],
          selected: {_kind},
          onSelectionChanged: (v) => setState(() => _kind = v.first),
        ),
        const SizedBox(height: AppSpace.lg),
        _label(c, 'Duración'),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final d in _durations)
              ChoiceChip(
                label: Text(durationText(d)),
                selected: _days == d,
                onSelected: (_) => setState(() => _days = d),
              ),
          ],
        ),
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
          decoration: BoxDecoration(
            color: c.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Menos',
                onPressed: value > min ? () => onChanged(value - 1) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Text('$value',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
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
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: c.successSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
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
                  onPressed: () => _copy(_created.join('\n'), 'Códigos'),
                  child: const Text('Copiar todos'),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          for (final code in _created)
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    code,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: c.ink),
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar',
                  onPressed: () => _copy(code, 'Código'),
                  icon: Icon(Icons.copy_rounded, size: 20, color: c.inkMuted),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _codeRow(StockealoColors c, ProCode code) {
    final status = code.exhausted ? 'Usado' : (code.uses > 0 ? '${code.uses}/${code.maxUses} usos' : 'Sin usar');
    final statusColor = code.exhausted ? c.inkMuted : (code.uses > 0 ? c.warning : c.success);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.line),
      ),
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
                    Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor)),
                  ],
                ),
                Text(
                  [
                    code.kindLabel,
                    code.durationLabel,
                    DateFormat('dd/MM/yyyy').format(code.createdAt),
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
            tooltip: 'Copiar',
            onPressed: () => _copy(code.code, 'Código'),
            icon: Icon(Icons.copy_rounded, size: 20, color: c.inkMuted),
          ),
        ],
      ),
    );
  }
}
