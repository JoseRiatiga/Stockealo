import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/cash_register_repository.dart';
import '../../models/cash_session.dart';

/// Arqueo de caja: abrir turno con una base, ver cuánto efectivo debería haber y
/// cerrar contando el dinero para conocer el faltante o sobrante.
class CashRegisterScreen extends StatefulWidget {
  final String businessId;
  final String userName;

  const CashRegisterScreen({super.key, required this.businessId, required this.userName});

  @override
  State<CashRegisterScreen> createState() => _CashRegisterScreenState();
}

class _CashRegisterScreenState extends State<CashRegisterScreen> {
  static const _green = Color(0xFF059669);
  static const _red = Color(0xFFDC2626);

  final _repo = CashRegisterRepository.instance;
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  CashSession? _open;
  CashSummary? _summary;
  List<CashSession> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final open = await _repo.getOpenSession(widget.businessId);
    final summary = open != null ? await _repo.summarize(open) : null;
    final history = await _repo.getClosedSessions(widget.businessId);
    if (!mounted) return;
    setState(() {
      _open = open;
      _summary = summary;
      _history = history;
      _isLoading = false;
    });
  }

  double? _parseAmount() {
    final clean = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    return clean.isEmpty ? null : double.parse(clean);
  }

  Future<void> _openSession() async {
    final amount = _parseAmount() ?? 0;
    setState(() => _isSaving = true);
    try {
      await _repo.openSession(businessId: widget.businessId, openingAmount: amount, openedBy: widget.userName);
      _amountController.clear();
      if (mounted) AppToast.show(context, message: 'Caja abierta', type: ToastType.success);
      await _load();
    } catch (e) {
      if (mounted) AppToast.show(context, message: e.toString().replaceFirst('Exception: ', ''), type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _closeSession() async {
    final counted = _parseAmount();
    final session = _open;
    final summary = _summary;
    if (session == null || summary == null) return;
    if (counted == null) {
      AppToast.show(context, message: 'Escribe cuánto efectivo contaste.', type: ToastType.error);
      return;
    }

    final difference = counted - summary.expected;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar la caja?'),
        content: Text(
          'Esperado: ${CurrencyFormatter.format(summary.expected)}\n'
          'Contado: ${CurrencyFormatter.format(counted)}\n\n'
          '${_differenceLabel(difference)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar caja'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _repo.closeSession(session: session, countedAmount: counted, notes: _notesController.text);
      _amountController.clear();
      _notesController.clear();
      if (mounted) AppToast.show(context, message: 'Caja cerrada', type: ToastType.success);
      await _load();
    } catch (e) {
      if (mounted) AppToast.show(context, message: e.toString().replaceFirst('Exception: ', ''), type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _differenceLabel(double difference) {
    if (difference.abs() < 0.5) return 'La caja cuadra exacto.';
    final amount = CurrencyFormatter.format(difference.abs());
    return difference > 0 ? 'Sobran $amount.' : 'Faltan $amount.';
  }

  Color _differenceColor(double difference) => difference.abs() < 0.5 ? _green : (difference > 0 ? Colors.orange.shade700 : _red);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Arqueo de caja')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _open == null ? _buildOpenForm() : _buildOpenSession(),
                  const SizedBox(height: 24),
                  Text('Cierres anteriores', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Todavía no has cerrado ninguna caja.'),
                    ),
                  ..._history.map(_buildHistoryTile),
                ],
              ),
            ),
    );
  }

  Widget _buildOpenForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('La caja está cerrada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Escribe el efectivo con el que empiezas el turno (la base o sencillo).'),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Base inicial', prefixText: r'$ '),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
              onPressed: _isSaving ? null : _openSession,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Abrir caja'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenSession() {
    final session = _open!;
    final summary = _summary!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Caja abierta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Desde ${DateFormat('d MMM, h:mm a', 'es_CO').format(session.openedAt)} · ${session.openedBy}'),
            const Divider(height: 24),
            _row('Base inicial', summary.openingAmount),
            _row('Ventas en efectivo (${summary.cashSalesCount})', summary.cashSales),
            _row('Abonos de fiados en efectivo', summary.cashPayments),
            const Divider(height: 24),
            _row('Debería haber en caja', summary.expected, bold: true),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Efectivo contado', prefixText: r'$ '),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
              onPressed: _isSaving ? null : _closeSession,
              icon: const Icon(Icons.lock_rounded),
              label: const Text('Cerrar caja'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, double amount, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(CurrencyFormatter.format(amount), style: style),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(CashSession s) {
    final difference = s.difference ?? 0;
    return Card(
      child: ListTile(
        title: Text(DateFormat('d MMM yyyy, h:mm a', 'es_CO').format(s.closedAt!)),
        subtitle: Text(
          'Esperado ${CurrencyFormatter.format(s.expectedAmount ?? 0)} · '
          'Contado ${CurrencyFormatter.format(s.countedAmount ?? 0)}'
          '${s.notes != null ? '\n${s.notes}' : ''}',
        ),
        trailing: Text(
          difference.abs() < 0.5 ? 'Cuadra' : '${difference > 0 ? '+' : '−'}${CurrencyFormatter.format(difference.abs())}',
          style: TextStyle(color: _differenceColor(difference), fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
