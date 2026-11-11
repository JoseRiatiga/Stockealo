import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../data/cash_register_repository.dart';
import '../../models/cash_session.dart';

/// Abrir la caja: la base con atajos ($ 50.000, $ 100.000, «Igual que ayer») y el
/// aviso si no coincide con lo que se contó al cerrar. Es LA forma de abrir la caja:
/// la usan la pantalla Caja (dentro) y Vender o el cobro de servicios (en una hoja).
class OpenCashForm extends StatefulWidget {
  final String businessId;
  final String userName;

  /// Botón de abrir: «Abrir caja» en Caja; «Abrir caja y empezar a vender» al vender
  final String actionLabel;
  final ValueChanged<CashSession> onOpened;

  const OpenCashForm({
    super.key,
    required this.businessId,
    required this.userName,
    required this.onOpened,
    this.actionLabel = 'Abrir caja',
  });

  @override
  State<OpenCashForm> createState() => _OpenCashFormState();
}

class _OpenCashFormState extends State<OpenCashForm> {
  final _repo = CashRegisterRepository.instance;
  final _base = TextEditingController();
  CashSession? _last;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repo.getClosedSessions(widget.businessId, limit: 1).then((list) {
      if (!mounted || list.isEmpty) return;
      setState(() {
        _last = list.first;
        // Por defecto se empieza con lo que quedó contado al cerrar
        if (_base.text.isEmpty && (list.first.countedAmount ?? 0) > 0) _set(list.first.countedAmount!);
      });
    });
  }

  @override
  void dispose() {
    _base.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_base.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  void _set(double v) => _base.text = NumberFormat.decimalPattern('es_CO').format(v.round());

  Future<void> _open() async {
    setState(() => _saving = true);
    try {
      final s = await _repo.openSession(businessId: widget.businessId, openingAmount: _amount, openedBy: widget.userName);
      if (mounted) widget.onOpened(s);
    } catch (e) {
      if (mounted) AppToast.showError(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final last = _last?.countedAmount;
    final diff = last == null ? 0.0 : _amount - last;
    final shortcuts = <(String, double)>[
      ('\$ 50.000', 50000),
      ('\$ 100.000', 100000),
      if (last != null && last > 0) ('Igual que ayer', last),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Efectivo inicial (base)', style: AppText.body(context, weight: FontWeight.w600)),
        const SizedBox(height: AppSpace.sm),
        TextField(
          controller: _base,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, _ThousandsFormatter()],
          style: AppText.heading(context).copyWith(fontSize: AppText.sizePage - 2),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _saving ? null : _open(),
          decoration: InputDecoration(
            prefixText: '\$ ',
            hintText: '0',
            prefixStyle: AppText.heading(context, color: c.inkMuted),
          ),
        ),
        const SizedBox(height: AppSpace.md - 2),
        Row(
          children: [
            for (var i = 0; i < shortcuts.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpace.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _set(shortcuts[i].$2)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _amount == shortcuts[i].$2 ? c.accent : c.line, width: _amount == shortcuts[i].$2 ? 2 : 1),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                  ),
                  child: Text(shortcuts[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ],
        ),
        if (last != null && diff.abs() >= 1) ...[
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.all(AppSpace.md - 2),
            decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: c.info),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    'Al cerrar, ${_last!.closedBy ?? _last!.openedBy} contó ${CurrencyFormatter.format(last)}. '
                    'Si hoy empiezas con ${CurrencyFormatter.format(_amount)}, hay ${CurrencyFormatter.format(diff.abs())} '
                    'de diferencia.',
                    style: AppText.small(context, color: c.ink),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _saving ? null : _open,
            child: Text(_saving ? 'Abriendo…' : widget.actionLabel),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Abre: ${widget.userName.isEmpty ? 'tú' : widget.userName} · ${DateFormat('h:mm a', 'es_CO').format(DateTime.now())}. '
          'Queda en la actividad del equipo.',
          textAlign: TextAlign.center,
          style: AppText.caption(context),
        ),
      ],
    );
  }
}

/// Puntos de mil mientras se escribe («100.000»)
class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final text = NumberFormat.decimalPattern('es_CO').format(int.parse(digits));
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Caja obligatoria (decisión del dueño): si el negocio usa caja y está cerrada,
/// antes de vender aparece «Abre la caja para vender» con la base ahí mismo.
class CashGate {
  CashGate._();

  /// true si se puede vender (el negocio no usa caja, ya estaba abierta o se acaba de abrir)
  static Future<bool> ensureOpen(BuildContext context, {required Business business, required String userName}) async {
    if (!await isCashClosedFor(business)) return true;
    if (!context.mounted) return false;
    final opened = await AppSheet.show<bool>(
      context: context,
      title: 'Abre la caja para vender',
      subtitle: 'Tu negocio usa caja. Escribe con cuánto efectivo empiezas, para tener con qué dar vuelto.',
      builder: (ctx) => OpenCashForm(
        businessId: business.id,
        userName: userName,
        actionLabel: 'Abrir caja y empezar a vender',
        onOpened: (_) => Navigator.pop(ctx, true),
      ),
    );
    return opened == true;
  }
}
