import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';

/// Una línea del tiquete: lo vendido o cotizado
class SaleDocumentLine {
  final int quantity;
  final String name;
  final double unitPrice;
  final double total;

  const SaleDocumentLine({required this.quantity, required this.name, required this.unitPrice, required this.total});
}

/// Un renglón «ETIQUETA ...... valor» del tiquete (pago, recibido, vuelto, saldo…)
class TicketRow {
  final String label;
  final String value;
  final bool bold;

  const TicketRow(this.label, this.value, {this.bold = false});
}

/// El sello girado del tiquete: PAGADO, FIADO, ANULADA, COTIZACIÓN, CAJA JUSTA…
class TicketStamp {
  final String label;

  /// Debajo del sello: la fecha, «válida hasta…», lo que queda debiendo
  final String? detail;
  final AppTone tone;

  const TicketStamp(this.label, {this.detail, this.tone = AppTone.accent});
}

/// Datos de un comprobante (venta, cotización, cierre de caja…), listos para
/// mostrarse como tiquete de papel, compartirse como imagen o como texto.
/// Es EL comprobante de Stockealo: todos usan este diseño (re-diseño 0.13.0).
class SaleDocument {
  /// «Comprobante de venta», «Cotización», «Cierre de caja»…
  final String title;
  final String number;
  final DateTime date;
  final DateTime? validUntil;
  final List<SaleDocumentLine> lines;
  final double discount;
  final double total;

  /// «TOTAL» por defecto; «TOTAL ESTIMADO» en cotizaciones, «CONTADO» en la caja
  final String? totalLabel;
  final String? paymentMethod;
  final String? customerName;
  final String? sellerName;
  final String? notes;

  /// Aviso destacado, por ejemplo «Venta a crédito (fiado)»
  final String? notice;
  final String closing;
  final TicketStamp? stamp;

  /// Renglones después del total (forma de pago, recibido, vuelto, saldo…)
  final List<TicketRow> after;

  /// Renglones antes de las líneas (cierre de caja: base, ventas en efectivo…)
  final List<TicketRow> before;

  const SaleDocument({
    required this.title,
    required this.number,
    required this.date,
    this.validUntil,
    required this.lines,
    this.discount = 0,
    required this.total,
    this.totalLabel,
    this.paymentMethod,
    this.customerName,
    this.sellerName,
    this.notes,
    this.notice,
    required this.closing,
    this.stamp,
    this.after = const [],
    this.before = const [],
  });

  double get subtotal => total + discount;

  bool get isQuotation => validUntil != null || title.startsWith('Cotiz');

  String get _totalLabel => totalLabel ?? (isQuotation ? 'Total estimado' : 'Total');

  /// Texto para WhatsApp (va junto a la imagen, o solo al copiarlo)
  String toText(String businessName) {
    const money = CurrencyFormatter.format;
    final date = DateFormat('dd/MM/yyyy hh:mm a');
    final day = DateFormat('dd/MM/yyyy');
    final b = StringBuffer()
      ..writeln('*${title.toUpperCase()}*')
      ..writeln('*$businessName*')
      ..writeln('N.º $number · ${isQuotation ? day.format(this.date) : date.format(this.date)}');
    if (stamp != null) b.writeln('*${stamp!.label}*${stamp!.detail == null ? '' : ' · ${stamp!.detail}'}');
    if (validUntil != null) b.writeln('Válida hasta el ${day.format(validUntil!)}');
    if (customerName?.isNotEmpty == true) b.writeln('Cliente: $customerName');
    b.writeln('--------------------------------');
    for (final r in before) {
      b.writeln('${r.label}: ${r.value}');
    }
    for (final l in lines) {
      b.writeln('• ${l.quantity} x ${l.name}  ${money(l.total)}');
      if (l.quantity > 1) b.writeln('   ${money(l.unitPrice)} c/u');
    }
    b.writeln('--------------------------------');
    if (discount > 0) {
      b.writeln('Subtotal: ${money(subtotal)}');
      b.writeln('Descuento: -${money(discount)}');
    }
    b.writeln('*$_totalLabel: ${money(total)}*');
    if (paymentMethod != null) b.writeln('Pago: $paymentMethod');
    for (final r in after) {
      b.writeln('${r.label}: ${r.value}');
    }
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

/// El comprobante como tiquete de papel: siempre blanco (la imagen compartida se
/// ve igual en cualquier teléfono), letra de máquina, líneas punteadas, el sello
/// en el color que corresponde, el código de barras con el número y el borde
/// cortado. Angosto y largo, pensado para WhatsApp.
class TicketPaper extends StatelessWidget {
  final Business? business;
  final String businessName;
  final SaleDocument doc;

  static const width = 320.0;

  const TicketPaper({super.key, required this.business, required this.businessName, required this.doc});

  Color _stampColor(AppTone tone, Color accent) => switch (tone) {
        AppTone.success => AppPalette.success,
        AppTone.warning => AppPalette.warning,
        AppTone.danger => AppPalette.danger,
        AppTone.info => AppPalette.info,
        AppTone.neutral => AppPalette.inkMuted,
        AppTone.accent => accent,
      };

  @override
  Widget build(BuildContext context) {
    final accent = AppPalette.readable(AppPalette.fromHex(business?.color) ?? AppPalette.brand);
    const ink = AppPalette.ink;
    const muted = AppPalette.inkMuted;
    const money = CurrencyFormatter.format;
    final mono = AppText.mono(context, size: AppText.sizeCaption, weight: FontWeight.w500, color: ink);
    final date = doc.isQuotation
        ? DateFormat('dd MMM yyyy', 'es_CO').format(doc.date).toUpperCase()
        : DateFormat('dd MMM yyyy · HH:mm', 'es_CO').format(doc.date).toUpperCase();

    Widget pair(String a, String b, {bool bold = false, Color color = ink}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(a, style: mono.copyWith(color: color, fontWeight: bold ? FontWeight.w700 : null))),
              const SizedBox(width: AppSpace.sm),
              Text(b, textAlign: TextAlign.right, style: mono.copyWith(color: color, fontWeight: bold ? FontWeight.w700 : null)),
            ],
          ),
        );

    final stamp = doc.stamp;
    final stampColor = stamp == null ? accent : _stampColor(stamp.tone, accent);

    // Bloque del total y el pago; el sello va debajo, a la derecha, montado apenas
    final totals = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (doc.discount > 0) ...[
              pair('SUBTOTAL', money(doc.subtotal)),
              pair('DESCUENTO', '-${money(doc.discount)}'),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Text(doc._totalLabel.toUpperCase(), style: mono.copyWith(fontWeight: FontWeight.w700))),
                Text(money(doc.total), style: AppText.amount(context, size: AppText.sizePage - 2, weight: FontWeight.w800, color: ink)),
              ],
            ),
            if (doc.paymentMethod != null) pair('PAGO', doc.paymentMethod!.toUpperCase()),
            for (final r in doc.after) pair(r.label.toUpperCase(), r.value, bold: r.bold),
            if (stamp != null)
              Align(
                alignment: Alignment.centerRight,
                child: Transform.translate(offset: const Offset(-6, -4), child: _Stamp(stamp: stamp, color: stampColor)),
              ),
          ],
    );

    return SizedBox(
      width: width,
      child: DefaultTextStyle.merge(
        style: mono,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppPalette.surface,
              padding: const EdgeInsets.fromLTRB(AppSpace.lg + 2, AppSpace.lg + 4, AppSpace.lg + 2, AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    businessName.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: AppText.title(context, weight: FontWeight.w800, color: ink).copyWith(letterSpacing: 3.5),
                  ),
                  if ((business?.description ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(business!.description!.trim(),
                          textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: mono.copyWith(color: muted)),
                    ),
                  const _Dashes(),
                  pair(doc.title.toUpperCase(), doc.number),
                  pair('FECHA', date),
                  if (doc.validUntil != null) pair('VÁLIDA HASTA', DateFormat('dd MMM yyyy', 'es_CO').format(doc.validUntil!).toUpperCase()),
                  if (doc.customerName?.isNotEmpty == true) pair('CLIENTE', doc.customerName!),
                  if (doc.sellerName?.isNotEmpty == true) pair('ATENDIÓ', doc.sellerName!),
                  const _Dashes(),
                  for (final r in doc.before) pair(r.label, r.value, bold: r.bold),
                  for (final l in doc.lines)
                    pair(
                      l.quantity > 1 ? '${l.name}  ${l.quantity} x ${NumberFormat.decimalPattern('es_CO').format(l.unitPrice)}' : l.name,
                      money(l.total),
                    ),
                  if (doc.before.isNotEmpty || doc.lines.isNotEmpty) const _Dashes(),
                  totals,
                  if (doc.notice != null)
                    Container(
                      margin: const EdgeInsets.only(top: AppSpace.md),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm + 2, vertical: AppSpace.sm),
                      decoration: BoxDecoration(color: AppPalette.warningSoft, borderRadius: BorderRadius.circular(AppRadius.small)),
                      child: Text(doc.notice!, style: mono.copyWith(color: AppPalette.warning, fontWeight: FontWeight.w700)),
                    ),
                  if (doc.notes?.isNotEmpty == true)
                    Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(doc.notes!, style: mono.copyWith(color: muted))),
                  const SizedBox(height: AppSpace.md),
                  // Código de barras con el número: al escanearlo en Stockealo se abre la venta
                  ExcludeSemantics(
                    child: BarcodeWidget(
                      barcode: Barcode.code128(),
                      data: doc.number,
                      height: 38,
                      drawText: false,
                      color: ink,
                      errorBuilder: (_, __) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(doc.number, textAlign: TextAlign.center, style: mono.copyWith(color: muted, letterSpacing: 3)),
                  const SizedBox(height: AppSpace.sm),
                  Text(doc.closing,
                      textAlign: TextAlign.center,
                      style: AppText.small(context, color: AppPalette.inkMuted).copyWith(fontStyle: FontStyle.italic)),
                  const SizedBox(height: 2),
                  Text('Hecho con Stockealo', textAlign: TextAlign.center, style: AppText.caption(context, color: AppPalette.inkFaint)),
                ],
              ),
            ),
            // Borde de papel cortado
            const SizedBox(height: 10, child: CustomPaint(painter: _ZigZagPainter(AppPalette.surface))),
          ],
        ),
      ),
    );
  }
}

/// Línea punteada entre bloques
class _Dashes extends StatelessWidget {
  const _Dashes();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.sm + 2),
        child: SizedBox(height: 1, child: CustomPaint(painter: _DashPainter(AppPalette.lineStrong))),
      );
}

class _DashPainter extends CustomPainter {
  final Color color;
  const _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 4, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}

class _ZigZagPainter extends CustomPainter {
  final Color color;
  const _ZigZagPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const step = 12.0;
    final path = Path()..moveTo(0, 0);
    for (var x = 0.0; x < size.width; x += step) {
      path
        ..lineTo(x + step / 2, size.height)
        ..lineTo(math.min(x + step, size.width), 0);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ZigZagPainter old) => old.color != color;
}

/// Sello redondo y girado, como uno de tinta
class _Stamp extends StatelessWidget {
  final TicketStamp stamp;
  final Color color;

  const _Stamp({required this.stamp, required this.color});

  @override
  Widget build(BuildContext context) {
    final long = stamp.label.length > 9;
    return Transform.rotate(
      angle: -14 * math.pi / 180,
      child: Opacity(
        opacity: 0.88,
        child: Container(
          width: long ? 116 : 92,
          height: long ? 116 : 92,
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 3)),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(stamp.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: AppText.small(context, weight: FontWeight.w800, color: color).copyWith(letterSpacing: 0.8, height: 1.1)),
              if (stamp.detail != null)
                Text(stamp.detail!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: AppText.caption(context, weight: FontWeight.w600, color: color).copyWith(height: 1.1)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Muestra el tiquete «saliendo de la impresora» (menos de 1 s; sin animación si la
/// persona pidió menos movimiento) con «Enviar por WhatsApp como imagen», «Ver de
/// nuevo» y «Copiar texto». Fondo oscuro en claro y en oscuro, como el diseño.
class TicketViewer extends StatefulWidget {
  final Business? business;
  final String businessName;
  final SaleDocument doc;

  /// Arriba del papel: «Venta registrada», «Venta anulada», «Caja cerrada»…
  final String headline;
  final AppTone headlineTone;

  /// Debajo: «\$ 41.500 en efectivo»
  final String? subline;

  /// Botón secundario a la derecha (por ejemplo «Nueva venta»); por defecto «Cerrar»
  final String closeLabel;

  /// Texto que se manda con la imagen (por defecto, el del documento)
  final String? text;

  /// Botón principal propio (por ejemplo «Enviar pedido por WhatsApp»); el de la
  /// imagen pasa abajo, como «Como imagen»
  final ({String label, IconData icon, VoidCallback onTap})? primary;

  const TicketViewer({
    super.key,
    required this.business,
    required this.businessName,
    required this.doc,
    required this.headline,
    this.headlineTone = AppTone.success,
    this.subline,
    this.closeLabel = 'Cerrar',
    this.text,
    this.primary,
  });

  static Future<void> show(
    BuildContext context, {
    required Business? business,
    required String businessName,
    required SaleDocument doc,
    String headline = 'Comprobante',
    AppTone headlineTone = AppTone.neutral,
    String? subline,
    String closeLabel = 'Cerrar',
    String? text,
    ({String label, IconData icon, VoidCallback onTap})? primary,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: AppMotion.of(context, AppMotion.quick),
      pageBuilder: (ctx, _, __) => TicketViewer(
        business: business,
        businessName: businessName,
        doc: doc,
        headline: headline,
        headlineTone: headlineTone,
        subline: subline,
        closeLabel: closeLabel,
        text: text,
        primary: primary,
      ),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(opacity: anim, child: child),
    );
  }

  @override
  State<TicketViewer> createState() => _TicketViewerState();
}

class _TicketViewerState extends State<TicketViewer> with SingleTickerProviderStateMixin {
  final _paperKey = GlobalKey();
  late final AnimationController _print = AnimationController(vsync: this, duration: AppMotion.print);
  bool _sharing = false;

  String get _text => widget.text ?? widget.doc.toText(widget.businessName);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_print.status == AnimationStatus.dismissed) _reprint();
  }

  @override
  void dispose() {
    _print.dispose();
    super.dispose();
  }

  void _reprint() {
    if (AppMotion.of(context, AppMotion.print) == Duration.zero) {
      _print.value = 1;
    } else {
      _print.forward(from: 0);
    }
  }

  Future<void> _shareImage() async {
    setState(() => _sharing = true);
    _print.value = 1;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final boundary = _paperKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('No se pudo dibujar el comprobante');
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('No se pudo crear la imagen');
      final name = '${widget.doc.title}_${widget.doc.number}.png'.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      await Share.shareXFiles(
        [XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png', name: name)],
        text: _text,
        subject: '${widget.doc.title} · ${widget.businessName}',
      );
    } catch (e) {
      // Si la imagen falla, al menos sale el texto
      if (mounted) AppToast.showWarning(context, 'No se pudo crear la imagen; se envía el texto.');
      await Share.share(_text, subject: '${widget.doc.title} · ${widget.businessName}');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _copyText() {
    Clipboard.setData(ClipboardData(text: _text));
    AppToast.showSuccess(context, 'Texto copiado');
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppPalette.surfaceDark;
    const fg = AppPalette.inkDark;
    const line = AppPalette.lineStrongDark;
    final t = ToneColors.of(context, widget.headlineTone);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 600;
    final panel = Material(
      color: bg,
      borderRadius: wide ? BorderRadius.circular(AppRadius.sheet) : BorderRadius.zero,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.lg),
          child: Column(
            children: [
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_outlined, color: AppPalette.inkMutedDark),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 6),
                decoration: BoxDecoration(color: t.strong.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(widget.headline, style: AppText.small(context, weight: FontWeight.w600, color: fg)),
              ),
              if (widget.subline != null) ...[
                const SizedBox(height: AppSpace.sm),
                Text(widget.subline!, textAlign: TextAlign.center, style: AppText.heading(context, color: fg)),
              ],
              const SizedBox(height: AppSpace.md),
              // La ranura de la impresora, con su luz encendida
              ExcludeSemantics(
                child: Container(
                  width: TicketPaper.width + 30,
                  height: 14,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerRight,
                  decoration: BoxDecoration(color: AppPalette.surfaceMutedDark, borderRadius: BorderRadius.circular(8)),
                  child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppPalette.successDark, shape: BoxShape.circle)),
                ),
              ),
              // El papel sale hacia abajo desde la ranura
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, -6),
                  child: ClipRect(
                    child: SingleChildScrollView(
                      child: AnimatedBuilder(
                        animation: _print,
                        builder: (context, child) => FractionalTranslation(
                          translation: Offset(0, Curves.easeOutCubic.transform(_print.value) - 1),
                          child: child,
                        ),
                        child: Center(
                          child: Semantics(
                            label: '${widget.doc.title} ${widget.doc.number}',
                            child: RepaintBoundary(
                              key: _paperKey,
                              child: TicketPaper(business: widget.business, businessName: widget.businessName, doc: widget.doc),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: widget.primary?.onTap ?? (_sharing ? null : _shareImage),
                  icon: Icon(widget.primary?.icon ?? Icons.share_outlined, size: 18),
                  label: Text(widget.primary?.label ?? (_sharing ? 'Preparando…' : 'Enviar por WhatsApp como imagen')),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  for (final (label, action) in [
                    if (widget.primary == null) ('Ver de nuevo', _reprint) else ('Como imagen', _shareImage),
                    ('Copiar texto', _copyText),
                    (widget.closeLabel, () => Navigator.of(context).maybePop()),
                  ]) ...[
                    if (label != 'Ver de nuevo' && label != 'Como imagen') const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: action,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: fg,
                          backgroundColor: Colors.transparent,
                          side: const BorderSide(color: line),
                          minimumSize: const Size(0, 46),
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                        ),
                        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!wide) return panel;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 440, maxHeight: math.min(size.height - 48, 860)), child: panel),
      ),
    );
  }
}
