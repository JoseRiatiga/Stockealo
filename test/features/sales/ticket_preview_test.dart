import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:stockealo/core/design/status_pill.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/core/theme/app_tokens.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/cash/models/cash_session.dart';
import 'package:stockealo/features/cash/presentation/screens/cash_register_screen.dart';
import 'package:stockealo/features/sales/models/sale.dart';
import 'package:stockealo/features/sales/presentation/widgets/digital_ticket_modal.dart';
import 'package:stockealo/features/sales/presentation/widgets/sale_document.dart';

/// El tiquete único (bloque 5) en sus casos: venta pagada, fiada, anulada,
/// cotización y cierre de caja, y el visor con la impresora en el celular.
/// Con PREVIEW_OUT=<carpeta> guarda imágenes.
Sale _sale(String name, int qty, double price, {String method = 'EFECTIVO', DateTime? voided}) => Sale(
      id: 'id-$name',
      productId: 'p-$name',
      productName: name,
      quantity: qty,
      unitPrice: price,
      unitCost: price * 0.7,
      totalAmount: qty * price,
      netProfit: qty * price * 0.3,
      paymentMethod: method,
      customerName: method == 'FIADO' ? 'Juan Gómez' : null,
      sellerName: 'Carlos M.',
      invoiceNumber: '#INV-0231',
      date: DateTime(2026, 11, 11, 10, 42),
      voidedAt: voided,
      voidReason: voided == null ? null : 'Cobro repetido',
    );

final _business = Business(id: 'b1', userId: 'u1', name: 'Variedades Rosita', color: '#1E6B4E', createdAt: DateTime(2026));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    // En las pruebas no hay letra de máquina: se usa Inter en su lugar
    for (final family in ['Inter', 'monospace']) {
      final loader = FontLoader(family);
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
      }
      await loader.load();
    }
  });

  final sale = [_sale('Huevos AA x30', 1, 18900), _sale('Gaseosa 1,5 L', 2, 5600), _sale('Café molido 250 g', 1, 11400)];
  final closed = CashSession(
    id: 's',
    businessId: 'b1',
    openedBy: 'Carlos',
    openedAt: DateTime(2026, 11, 11, 8, 5),
    openingAmount: 100000,
    closedAt: DateTime(2026, 11, 11, 20, 6),
    closedBy: 'Rosa',
    expectedAmount: 512400,
    countedAmount: 510400,
  );
  const summary = CashSummary(
    openingAmount: 100000,
    cashSales: 412400,
    cashSalesCount: 14,
    cashPayments: 0,
    tipsIn: 0,
    tipsOut: 0,
    entries: 0,
    exits: 0,
    cashPurchases: 0,
    byMethod: {'EFECTIVO': 412400, 'NEQUI': 233000},
  );
  late final cases = <String, SaleDocument>{
    'pagado': DigitalTicketModal.buildReceipt(sale, received: 50000, change: 8500),
    'fiado': DigitalTicketModal.buildReceipt([_sale('Arroz Diana 500 g', 3, 4200, method: 'FIADO')], debtAfter: 45000),
    'anulada': DigitalTicketModal.buildReceipt([_sale('Aceite Premier 1 L', 1, 12900, voided: DateTime(2026, 11, 11, 11))]),
    'cotizacion': SaleDocument(
      title: 'Cotización',
      number: 'COT-0012',
      date: DateTime(2026, 11, 11),
      validUntil: DateTime(2026, 11, 18),
      lines: const [SaleDocumentLine(quantity: 12, name: 'Cuaderno 100 h', unitPrice: 4500, total: 54000)],
      total: 54000,
      customerName: 'Colegio San José',
      closing: 'Para confirmar tu pedido, responde a este mensaje.',
      stamp: const TicketStamp('COTIZACIÓN', detail: 'Hasta 18 NOV', tone: AppTone.info),
    ),
    'caja': cashTicket(closed, summary),
  };

  Future<void> save(GlobalKey key, String name, {double ratio = 1}) async {
    final out = Platform.environment['PREVIEW_OUT'];
    if (out == null) return;
    final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  for (final name in ['pagado', 'fiado', 'anulada', 'cotizacion', 'caja']) {
    testWidgets('tiquete: $name', (tester) async {
      final e = MapEntry(name, cases[name]!);
      tester.view.physicalSize = const Size(380, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(
          backgroundColor: AppPalette.surfaceDark,
          body: SingleChildScrollView(
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: TicketPaper(business: _business, businessName: _business.name, doc: e.value),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(e.value.stamp!.label), findsWidgets);
      await tester.runAsync(() => save(key, 'tiquete_${e.key}', ratio: 1.5));
    });
  }

  testWidgets('el visor: la impresora, el papel saliendo y los botones', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: RepaintBoundary(
        key: key,
        child: TicketViewer(
          business: _business,
          businessName: _business.name,
          doc: cases['pagado']!,
          headline: 'Venta registrada',
          subline: '\$ 41.500 en efectivo',
          closeLabel: 'Nueva venta',
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Enviar por WhatsApp como imagen'), findsOneWidget);
    expect(find.text('Nueva venta'), findsOneWidget);
    await tester.runAsync(() => save(key, 'tiquete_visor'));
  });
}
