import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/design/primary_action_button.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/business_identity.dart';

/// Una línea del comprobante o la cotización
class SaleDocumentLine {
  final int quantity;
  final String name;
  final double unitPrice;
  final double total;

  const SaleDocumentLine({required this.quantity, required this.name, required this.unitPrice, required this.total});
}

/// Datos de un comprobante de venta o una cotización, listos para mostrar,
/// compartir como imagen o como texto
class SaleDocument {
  /// "Comprobante de venta" o "Cotización"
  final String title;
  final String number;
  final DateTime date;
  final DateTime? validUntil;
  final List<SaleDocumentLine> lines;
  final double discount;
  final double total;
  final String? paymentMethod;
  final String? customerName;
  final String? sellerName;
  final String? notes;

  /// Aviso destacado, por ejemplo "Venta a crédito (fiado)"
  final String? notice;
  final String closing;

  const SaleDocument({
    required this.title,
    required this.number,
    required this.date,
    this.validUntil,
    required this.lines,
    this.discount = 0,
    required this.total,
    this.paymentMethod,
    this.customerName,
    this.sellerName,
    this.notes,
    this.notice,
    required this.closing,
  });

  double get subtotal => total + discount;

  bool get isQuotation => validUntil != null || title.startsWith('Cotiz');

  /// Texto para WhatsApp (va junto a la imagen o solo, al copiarlo)
  String toText(String businessName) {
    const money = CurrencyFormatter.format;
    final date = DateFormat('dd/MM/yyyy hh:mm a');
    final day = DateFormat('dd/MM/yyyy');
    final b = StringBuffer()
      ..writeln('*${title.toUpperCase()}*')
      ..writeln('*$businessName*')
      ..writeln('N.º $number · ${isQuotation ? day.format(this.date) : date.format(this.date)}');
    if (validUntil != null) b.writeln('Válida hasta el ${day.format(validUntil!)}');
    if (customerName?.isNotEmpty == true) b.writeln('Cliente: $customerName');
    b.writeln('--------------------------------');
    for (final l in lines) {
      b.writeln('• ${l.quantity} x ${l.name}  ${money(l.total)}');
      if (l.quantity > 1) b.writeln('   ${money(l.unitPrice)} c/u');
    }
    b.writeln('--------------------------------');
    if (discount > 0) {
      b.writeln('Subtotal: ${money(subtotal)}');
      b.writeln('Descuento: -${money(discount)}');
    }
    b.writeln('*Total: ${money(total)}*');
    if (paymentMethod != null) b.writeln('Pago: $paymentMethod');
    if (notice != null) b.writeln(notice);
    if (sellerName?.isNotEmpty == true) b.writeln('Atendido por: $sellerName');
    if (notes?.isNotEmpty == true) b.writeln('Notas: $notes');
    b
      ..writeln('--------------------------------')
      ..writeln(closing)
      ..write('Hecho con Stockealo');
    return b.toString();
  }
}

/// El documento como "hoja de papel": siempre claro, con el logo y el color del
/// negocio, para que la imagen compartida se vea igual en cualquier teléfono
class SaleDocumentCard extends StatelessWidget {
  final Business? business;
  final String businessName;
  final SaleDocument doc;

  const SaleDocumentCard({super.key, required this.business, required this.businessName, required this.doc});

  @override
  Widget build(BuildContext context) {
    final accent = AppPalette.fromHex(business?.color) ?? AppPalette.brand;
    const ink = AppPalette.ink;
    const muted = AppPalette.inkMuted;
    const line = AppPalette.line;
    const money = CurrencyFormatter.format;
    final date = doc.isQuotation ? DateFormat('dd MMM yyyy', 'es_CO') : DateFormat('dd MMM yyyy · hh:mm a', 'es_CO');

    Widget row(String label, String value, {Color color = ink, bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: muted))),
              Text(value,
                  style: TextStyle(fontSize: 13, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: line),
      ),
      clipBehavior: Clip.antiAlias,
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: AppText.fontFamily, color: ink),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: accent,
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Row(
                children: [
                  if (business != null) ...[
                    CatalogLogo(business: business!, color: accent, size: 44),
                    const SizedBox(width: AppSpace.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          businessName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        Text(doc.title, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('N.º ${doc.number}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
                      ),
                      Text(date.format(doc.date), style: const TextStyle(fontSize: 12.5, color: muted)),
                    ],
                  ),
                  if (doc.validUntil != null)
                    row('Válida hasta', DateFormat('dd MMM yyyy', 'es_CO').format(doc.validUntil!)),
                  if (doc.customerName?.isNotEmpty == true) row('Cliente', doc.customerName!),
                  const Divider(height: AppSpace.xl, color: line),
                  for (final l in doc.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text('${l.quantity}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: muted)),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                if (l.quantity > 1)
                                  Text('${money(l.unitPrice)} c/u', style: const TextStyle(fontSize: 12, color: muted)),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Text(money(l.total), style: AppText.amount(context, size: 14, color: ink)),
                        ],
                      ),
                    ),
                  const Divider(height: AppSpace.lg, color: line),
                  if (doc.discount > 0) ...[
                    row('Subtotal', money(doc.subtotal)),
                    row('Descuento', '-${money(doc.discount)}', color: AppPalette.success, bold: true),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(doc.isQuotation ? 'Total estimado' : 'Total',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                        Text(money(doc.total), style: AppText.amount(context, size: 22, weight: FontWeight.w800, color: accent)),
                      ],
                    ),
                  ),
                  if (doc.paymentMethod != null) row('Pago', doc.paymentMethod!),
                  if (doc.sellerName?.isNotEmpty == true) row('Atendido por', doc.sellerName!),
                  if (doc.notice != null)
                    Container(
                      margin: const EdgeInsets.only(top: AppSpace.md),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                      decoration: BoxDecoration(
                        color: AppPalette.warningSoft,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Text(doc.notice!,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppPalette.warning)),
                    ),
                  if (doc.notes?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.md),
                      child: Text(doc.notes!, style: const TextStyle(fontSize: 12.5, color: muted)),
                    ),
                  const SizedBox(height: AppSpace.lg),
                  Text(doc.closing,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink)),
                  const SizedBox(height: 2),
                  const Text('Hecho con Stockealo',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppPalette.inkFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja con el documento y las acciones: compartir como imagen (con el texto
/// adjunto) o copiar el texto
class SaleDocumentSheet extends StatefulWidget {
  final Business? business;
  final String businessName;
  final SaleDocument doc;

  const SaleDocumentSheet({super.key, required this.business, required this.businessName, required this.doc});

  static Future<void> show(
    BuildContext context, {
    required Business? business,
    required String businessName,
    required SaleDocument doc,
  }) {
    return showModalBottomSheet(
      context: context,
      showDragHandle: false,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SaleDocumentSheet(business: business, businessName: businessName, doc: doc),
    );
  }

  @override
  State<SaleDocumentSheet> createState() => _SaleDocumentSheetState();
}

class _SaleDocumentSheetState extends State<SaleDocumentSheet> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  String get _text => widget.doc.toText(widget.businessName);

  Future<void> _shareImage() async {
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('No se pudo dibujar el documento');
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('No se pudo crear la imagen');
      final name = '${widget.doc.isQuotation ? 'Cotizacion' : 'Comprobante'}_${widget.doc.number}.png'
          .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      await Share.shareXFiles(
        [XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png', name: name)],
        text: _text,
        subject: '${widget.doc.title} · ${widget.businessName}',
      );
    } catch (e) {
      // Si la imagen falla, al menos sale el texto
      if (mounted) AppToast.show(context, message: 'No se pudo crear la imagen; se envía el texto.', type: ToastType.warning);
      await Share.share(_text, subject: '${widget.doc.title} · ${widget.businessName}');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _copyText() {
    Clipboard.setData(ClipboardData(text: _text));
    AppToast.show(context, message: 'Texto copiado', type: ToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.sm, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.doc.title,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: c.inkMuted),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
                child: RepaintBoundary(
                  key: _cardKey,
                  child: SaleDocumentCard(business: widget.business, businessName: widget.businessName, doc: widget.doc),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.lg),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyText,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copiar texto'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: PrimaryActionButton(
                      label: _sharing ? 'Preparando…' : 'Compartir',
                      icon: Icons.share_rounded,
                      onPressed: _sharing ? null : _shareImage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
