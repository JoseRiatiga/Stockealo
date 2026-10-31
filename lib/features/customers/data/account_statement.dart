import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../business/models/business.dart';
import '../../reports/data/catalog_pdf_service.dart';
import '../models/customer.dart';

/// Un renglón del estado de cuenta: una venta fiada (cargo) o un abono
class StatementEntry {
  final DateTime date;
  final String description;
  final double charge;
  final double payment;

  /// Saldo después de este movimiento
  final double balance;

  const StatementEntry({
    required this.date,
    required this.description,
    this.charge = 0,
    this.payment = 0,
    this.balance = 0,
  });
}

/// Estado de cuenta de un cliente: lo que compró fiado, lo que abonó y lo que debe
class AccountStatement {
  /// Saldo que ya traía antes del primer movimiento registrado (deudas viejas o
  /// ajustes a mano); 0 si todo cuadra con los movimientos
  final double openingBalance;
  final List<StatementEntry> entries;

  /// Saldo actual: el del cliente, que es la verdad
  final double balance;

  const AccountStatement({required this.openingBalance, required this.entries, required this.balance});

  double get totalCharges => entries.fold(0.0, (s, e) => s + e.charge);
  double get totalPayments => entries.fold(0.0, (s, e) => s + e.payment);

  /// Arma el estado con las filas de `sales` (fiadas) y `customer_payments`.
  /// Los movimientos van del más viejo al más nuevo con el saldo acumulado.
  static AccountStatement fromRows({
    required List<Map<String, dynamic>> fiadoSales,
    required List<Map<String, dynamic>> payments,
    required double currentBalance,
  }) {
    final raw = <StatementEntry>[
      for (final s in fiadoSales)
        StatementEntry(
          date: DateTime.tryParse(s['date'] as String? ?? '') ?? DateTime.now(),
          description: _saleDescription(s),
          charge: (s['total'] as num?)?.toDouble() ?? 0,
        ),
      for (final p in payments)
        StatementEntry(
          date: DateTime.tryParse(p['date'] as String? ?? '') ?? DateTime.now(),
          description: _paymentDescription(p),
          payment: (p['amount'] as num?)?.toDouble() ?? 0,
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));

    final movements = raw.fold(0.0, (s, e) => s + e.charge - e.payment);
    final opening = _round(currentBalance - movements);
    var running = opening;
    final entries = [
      for (final e in raw)
        StatementEntry(
          date: e.date,
          description: e.description,
          charge: e.charge,
          payment: e.payment,
          balance: running = _round(running + e.charge - e.payment),
        ),
    ];
    return AccountStatement(openingBalance: opening, entries: entries, balance: currentBalance);
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  static String _saleDescription(Map<String, dynamic> s) {
    final name = (s['product_name'] as String? ?? '').trim();
    final qty = (s['quantity'] as num?)?.toInt() ?? 1;
    final invoice = (s['invoice_number'] as String? ?? '').trim();
    final base = name.isEmpty ? 'Compra fiada' : (qty > 1 ? '$name ×$qty' : name);
    return invoice.isEmpty ? base : '$base · $invoice';
  }

  static String _paymentDescription(Map<String, dynamic> p) {
    final method = switch (p['payment_method']) {
      'EFECTIVO' => 'en efectivo',
      'TRANSFERENCIA' => 'por transferencia',
      _ => '',
    };
    final notes = (p['notes'] as String? ?? '').trim();
    return ['Abono${method.isEmpty ? '' : ' $method'}', if (notes.isNotEmpty) notes].join(' · ');
  }
}

/// Lee los movimientos, arma el PDF y lo comparte
class AccountStatementService {
  AccountStatementService._();
  static final AccountStatementService instance = AccountStatementService._();

  Future<AccountStatement> load(Customer customer) async {
    final db = await AppDatabase.instance.database;
    final sales = await db.query(
      'sales',
      where: 'customer_id = ? AND business_id = ? AND payment_method = ?',
      whereArgs: [customer.id, customer.businessId, 'FIADO'],
    );
    final payments = await db.query(
      'customer_payments',
      where: 'customer_id = ? AND business_id = ?',
      whereArgs: [customer.id, customer.businessId],
    );
    return AccountStatement.fromRows(fiadoSales: sales, payments: payments, currentBalance: customer.debtBalance);
  }

  /// Mensaje que acompaña el PDF al compartirlo
  static String shareMessage({required String customerName, required String businessName, required String balance}) =>
      'Hola $customerName, te compartimos tu estado de cuenta con $businessName. '
      'Tu saldo pendiente es de $balance. ¡Gracias por tu preferencia!';

  /// Arma el PDF en memoria; el nombre sugerido sirve para el archivo o la descarga
  Future<({Uint8List bytes, String fileName})> generatePdf({required Business business, required Customer customer}) async {
    final statement = await load(customer);
    final pdfs = CatalogPdfService.instance;
    final logo = await pdfs.loadImageBytes(business.logoUrl);
    final hex = business.color ?? '#1E6B4E';
    final accent = PdfColor.fromHex(RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex) ? hex : '#1E6B4E');
    final ink = PdfColor.fromHex('#1F1D18');
    final muted = PdfColor.fromHex('#6E6A60');
    final line = PdfColor.fromHex('#ECE7DC');
    String money(num v) => CurrencyFormatter.formatIn(v, business.currency);
    final dateFmt = DateFormat('dd/MM/yyyy');
    final now = DateTime.now();

    final doc = pw.Document(
      title: 'Estado de cuenta · ${customer.name}',
      author: business.name,
      theme: await pdfs.pdfTheme(),
    );

    pw.Widget cell(String text, {bool bold = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.left}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(
            text,
            textAlign: align,
            style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : null, color: color ?? ink),
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text('${business.name} · Estado de cuenta de ${customer.name}',
                    style: pw.TextStyle(fontSize: 8, color: muted)),
              ),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 8, color: muted)),
        ),
        build: (_) => [
          // Encabezado con el color y el logo del negocio
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
            ),
            child: pw.Row(
              children: [
                if (logo != null)
                  pw.ClipRRect(
                    horizontalRadius: 10,
                    verticalRadius: 10,
                    child: pw.Image(pw.MemoryImage(logo), width: 44, height: 44, fit: pw.BoxFit.cover),
                  )
                else
                  pw.Container(
                    width: 44,
                    height: 44,
                    alignment: pw.Alignment.center,
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
                    ),
                    child: pw.Text(
                      business.name.trim().isNotEmpty ? business.name.trim()[0].toUpperCase() : 'S',
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: accent),
                    ),
                  ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(business.name,
                          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                      pw.Text('Estado de cuenta', style: const pw.TextStyle(fontSize: 11, color: PdfColors.white)),
                    ],
                  ),
                ),
                pw.Text('Al ${dateFmt.format(now)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.white)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          // Cliente y saldo
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Cliente', style: pw.TextStyle(fontSize: 9, color: muted)),
                    pw.Text(customer.name,
                        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: ink)),
                    if (customer.phone?.trim().isNotEmpty == true)
                      pw.Text(customer.phone!.trim(), style: pw.TextStyle(fontSize: 9, color: muted)),
                  ],
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: accent, width: 1.2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Saldo pendiente', style: pw.TextStyle(fontSize: 9, color: muted)),
                    pw.Text(money(statement.balance),
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: accent)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Compras fiadas: ${money(statement.totalCharges)}   ·   Abonos: ${money(statement.totalPayments)}',
            style: pw.TextStyle(fontSize: 9, color: muted),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: 0.6)),
            columnWidths: const {
              0: pw.FixedColumnWidth(62),
              1: pw.FlexColumnWidth(),
              2: pw.FixedColumnWidth(72),
              3: pw.FixedColumnWidth(72),
              4: pw.FixedColumnWidth(76),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F1EDE4')),
                children: [
                  cell('Fecha', bold: true),
                  cell('Detalle', bold: true),
                  cell('Fiado', bold: true, align: pw.TextAlign.right),
                  cell('Abono', bold: true, align: pw.TextAlign.right),
                  cell('Saldo', bold: true, align: pw.TextAlign.right),
                ],
              ),
              if (statement.openingBalance.abs() >= 0.01)
                pw.TableRow(children: [
                  cell(''),
                  cell('Saldo anterior', color: muted),
                  cell(''),
                  cell(''),
                  cell(money(statement.openingBalance), align: pw.TextAlign.right),
                ]),
              for (final e in statement.entries)
                pw.TableRow(children: [
                  cell(dateFmt.format(e.date)),
                  cell(e.description),
                  cell(e.charge > 0 ? money(e.charge) : '', align: pw.TextAlign.right),
                  cell(e.payment > 0 ? money(e.payment) : '', color: accent, align: pw.TextAlign.right),
                  cell(money(e.balance), bold: true, align: pw.TextAlign.right),
                ]),
            ],
          ),
          if (statement.entries.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 12),
              child: pw.Text('Todavía no hay compras fiadas ni abonos registrados.',
                  style: pw.TextStyle(fontSize: 9, color: muted)),
            ),
          pw.SizedBox(height: 18),
          pw.Text('Gracias por tu preferencia. Si ya pagaste, ignora este mensaje.',
              style: pw.TextStyle(fontSize: 9, color: muted)),
        ],
      ),
    );

    final cleanName = customer.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return (bytes: await doc.save(), fileName: 'Estado_de_cuenta_${cleanName}_${DateFormat('yyyyMMdd').format(now)}.pdf');
  }

  /// Arma el PDF y abre el menú de compartir (WhatsApp, correo…) con un mensaje listo
  Future<void> share({required Business business, required Customer customer}) async {
    final pdf = await generatePdf(business: business, customer: customer);
    final XFile xfile;
    if (kIsWeb) {
      // En la web no hay carpetas: se comparte (o se descarga) desde la memoria
      xfile = XFile.fromData(pdf.bytes, name: pdf.fileName, mimeType: 'application/pdf');
    } else {
      final file = File('${(await getTemporaryDirectory()).path}/${pdf.fileName}');
      await file.writeAsBytes(pdf.bytes, flush: true);
      xfile = XFile(file.path, name: pdf.fileName, mimeType: 'application/pdf');
    }
    await Share.shareXFiles(
      [xfile],
      subject: 'Estado de cuenta · ${business.name}',
      text: shareMessage(
        customerName: customer.name,
        businessName: business.name,
        balance: CurrencyFormatter.formatIn(customer.debtBalance, business.currency),
      ),
    );
  }
}
