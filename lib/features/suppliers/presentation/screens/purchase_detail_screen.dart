import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/image_source_picker_modal.dart';
import '../../../products/data/product_image_service.dart';
import '../../data/invoice_photo_service.dart';
import '../../data/supplier_repository.dart';
import '../../models/purchase.dart';
import '../../../../core/design/app_dialog.dart';

String purchaseDateLabel(DateTime d) {
  const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// Una entrada de mercancía: lo que llegó, la factura y, si es a crédito, los abonos
class PurchaseDetailScreen extends StatefulWidget {
  final Purchase purchase;
  const PurchaseDetailScreen({super.key, required this.purchase});

  /// true si cambió algo (abono, pago o foto)
  static Future<bool?> open(BuildContext context, Purchase purchase) =>
      Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PurchaseDetailScreen(purchase: purchase)));

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  final _repo = SupplierRepository.instance;
  late Purchase _p = widget.purchase;
  bool _changed = false;
  bool _busy = false;
  String? _photoUrl;
  bool _loadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final path = _p.photoPath;
    if (path == null) return;
    setState(() => _loadingPhoto = true);
    final url = await InvoicePhotoService.instance.viewUrl(path);
    if (mounted) {
      setState(() {
        _photoUrl = url;
        _loadingPhoto = false;
      });
    }
  }

  Future<void> _addPayment() async {
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        return AppDialog(
title: 'Registrar abono',
content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Falta pagar ${CurrencyFormatter.format(_p.balance)}', style: TextStyle(color: c.inkMuted)),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Valor del abono', prefixText: '\$ '),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'Ej. Nequi, efectivo'),
              ),
            ],
          ),
actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar abono')),
          ],
);
      },
    );
    final value = double.tryParse(amount.text.trim()) ?? 0;
    final text = note.text.trim();
    amount.dispose();
    note.dispose();
    if (ok != true || value <= 0) return;
    setState(() => _busy = true);
    final updated = await _repo.addPayment(_p, value, note: text.isEmpty ? null : text);
    if (!mounted) return;
    setState(() {
      _p = updated;
      _busy = false;
      _changed = true;
    });
    AppToast.showSuccess(context, updated.isPaid ? 'Entrada pagada por completo.' : 'Abono guardado.');
  }

  Future<void> _markPaid() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
title: '¿Marcar como pagada?',
content: Text('Se registra un pago de ${CurrencyFormatter.format(_p.balance)}, lo que faltaba.'),
actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Marcar pagada')),
        ],
),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final updated = await _repo.markPaid(_p);
    if (!mounted) return;
    setState(() {
      _p = updated;
      _busy = false;
      _changed = true;
    });
  }

  void _addPhoto() {
    ImageSourcePickerModal.show(
      context,
      title: 'Foto de la factura',
      subtitle: 'Queda guardada en privado: solo la ve el equipo del negocio',
      hasExistingImage: _p.photoPath != null,
      onSelected: (source) async {
        final picked = await ImageHelper.pickBytes(source);
        if (picked == null || !mounted) return;
        setState(() => _busy = true);
        try {
          final path = await InvoicePhotoService.instance.upload(
            businessId: _p.businessId,
            purchaseId: _p.id,
            bytes: picked.bytes,
            mimeType: picked.mimeType,
          );
          final updated = await _repo.setPhoto(_p, path);
          if (!mounted) return;
          setState(() {
            _p = updated;
            _changed = true;
          });
          await _loadPhoto();
        } on ProductImageException catch (e) {
          if (mounted) AppToast.showError(context, e.message);
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      },
    );
  }

  void _viewPhoto() {
    final url = _photoUrl;
    if (url == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpace.lg),
        child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = _p;
    final overdue = p.isOverdue();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: c.paper,
        appBar: AppBar(title: Text('Entrada del ${purchaseDateLabel(p.date)}')),
        body: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.lg),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((p.supplierName ?? '').isNotEmpty) _info(Icons.storefront_outlined, p.supplierName!),
                    if ((p.invoiceNumber ?? '').isNotEmpty) _info(Icons.receipt_outlined, 'Factura ${p.invoiceNumber}'),
                    _info(
                      Icons.payments_outlined,
                      p.isCredit
                          ? 'A crédito${p.dueDate != null ? ', pagar a más tardar el ${purchaseDateLabel(p.dueDate!)}' : ''}'
                          : 'De contado',
                    ),
                    if ((p.createdBy ?? '').isNotEmpty) _info(Icons.person_outline_outlined, 'Registró ${p.createdBy}'),
                  ],
                ),
              ),
              if (p.isCredit) ...[
                const SizedBox(height: AppSpace.md),
                AppCard(
                  color: p.isPaid ? c.successSoft : (overdue ? c.dangerSoft : c.warningSoft),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.isPaid
                            ? 'Pagada'
                            : (overdue
                                ? 'Vencida: faltan ${CurrencyFormatter.format(p.balance)}'
                                : 'Faltan ${CurrencyFormatter.format(p.balance)}'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: p.isPaid ? c.success : (overdue ? c.danger : c.warning),
                        ),
                      ),
                      Text(
                        'Abonado ${CurrencyFormatter.format(p.paidAmount)} de ${CurrencyFormatter.format(p.total)}',
                        style: TextStyle(color: c.ink, fontSize: AppText.sizeSmall),
                      ),
                      for (final pay in p.payments)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${purchaseDateLabel(pay.date)} · ${CurrencyFormatter.format(pay.amount)}'
                            '${(pay.note ?? '').isEmpty ? '' : ' · ${pay.note}'}',
                            style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeSmall),
                          ),
                        ),
                      if (!p.isPaid) ...[
                        const SizedBox(height: AppSpace.md),
                        Wrap(
                          spacing: AppSpace.sm,
                          runSpacing: AppSpace.sm,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy ? null : _addPayment,
                              icon: const Icon(Icons.add_outlined, size: 18),
                              label: const Text('Registrar abono'),
                            ),
                            OutlinedButton(
                              onPressed: _busy ? null : _markPaid,
                              child: const Text('Marcar pagada'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Lo que llegó', style: TextStyle(color: c.ink, fontWeight: FontWeight.bold)),
                    const SizedBox(height: AppSpace.sm),
                    for (final i in p.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(child: Text('${i.quantity} × ${i.label}', style: TextStyle(color: c.ink, fontSize: AppText.sizeSmall))),
                            Text(CurrencyFormatter.format(i.subtotal), style: TextStyle(color: c.ink, fontSize: AppText.sizeSmall)),
                          ],
                        ),
                      ),
                    Divider(color: c.line),
                    Row(
                      children: [
                        Expanded(child: Text('Total · ${p.units} unidades', style: TextStyle(color: c.ink, fontWeight: FontWeight.bold))),
                        Text(CurrencyFormatter.format(p.total), style: TextStyle(color: c.ink, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    if ((p.notes ?? '').isNotEmpty) ...[
                      const SizedBox(height: AppSpace.md),
                      Text(p.notes!, style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeSmall)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Foto de la factura', style: TextStyle(color: c.ink, fontWeight: FontWeight.bold)),
                    const SizedBox(height: AppSpace.sm),
                    if (p.photoPath == null)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _addPhoto,
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: const Text('Agregar foto'),
                      )
                    else if (_loadingPhoto)
                      const Center(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: CircularProgressIndicator()))
                    else if (_photoUrl == null)
                      Text('No se pudo cargar la foto. Revisa tu conexión.', style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeSmall))
                    else
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _viewPhoto,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(_photoUrl!, width: 72, height: 72, fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(width: AppSpace.md),
                          TextButton(onPressed: _viewPhoto, child: const Text('Ver')),
                          TextButton(onPressed: _busy ? null : _addPhoto, child: const Text('Cambiar')),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(IconData icon, String text) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.inkMuted),
          const SizedBox(width: AppSpace.md),
          Expanded(child: Text(text, style: TextStyle(color: c.ink, fontSize: AppText.sizeBody))),
        ],
      ),
    );
  }
}

/// Cuentas por pagar a proveedores: entradas a crédito sin pagar
class PayablesScreen extends StatefulWidget {
  final String businessId;
  const PayablesScreen({super.key, required this.businessId});

  static Future<void> open(BuildContext context, {required String businessId}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PayablesScreen(businessId: businessId)));

  @override
  State<PayablesScreen> createState() => _PayablesScreenState();
}

class _PayablesScreenState extends State<PayablesScreen> {
  List<Purchase>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await SupplierRepository.instance.getPayables(widget.businessId);
    if (mounted) setState(() => _list = list);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = _list;
    final total = list?.fold(0.0, (s, p) => s + p.balance) ?? 0;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(title: const Text('Por pagar a proveedores')),
      body: ContentWidth(
        child: list == null
            ? const Center(child: CircularProgressIndicator())
            : list.isEmpty
                ? Center(child: Text('No le debes nada a tus proveedores.', style: TextStyle(color: c.inkMuted)))
                : ListView(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    children: [
                      Text('Total por pagar', style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeSmall)),
                      Text(CurrencyFormatter.format(total),
                          style: TextStyle(color: c.ink, fontSize: AppText.sizePage, fontWeight: FontWeight.bold)),
                      const SizedBox(height: AppSpace.lg),
                      for (final p in list) ...[
                        AppCard(
                          onTap: () async {
                            final changed = await PurchaseDetailScreen.open(context, p);
                            if (changed == true) _load();
                          },
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.supplierName ?? 'Sin proveedor',
                                        style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                                    Text(
                                      p.dueDate == null
                                          ? 'Entrada del ${purchaseDateLabel(p.date)}'
                                          : (p.isOverdue()
                                              ? 'Venció el ${purchaseDateLabel(p.dueDate!)}'
                                              : 'Vence el ${purchaseDateLabel(p.dueDate!)}'),
                                      style: TextStyle(color: p.isOverdue() ? c.danger : c.inkMuted, fontSize: AppText.sizeCaption),
                                    ),
                                  ],
                                ),
                              ),
                              Text(CurrencyFormatter.format(p.balance),
                                  style: TextStyle(color: c.ink, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpace.sm),
                      ],
                    ],
                  ),
      ),
    );
  }
}
