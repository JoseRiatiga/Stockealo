import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/sales/models/sale.dart';
import 'package:stockealo/features/sales/presentation/widgets/digital_ticket_modal.dart';
import 'package:stockealo/features/sales/presentation/widgets/sale_document.dart';

Sale _sale(String id, String name, int qty, double price, {String method = 'EFECTIVO'}) => Sale(
      id: id,
      productId: 'p-$id',
      productName: name,
      quantity: qty,
      unitPrice: price,
      unitCost: price / 2,
      totalAmount: qty * price,
      netProfit: qty * price / 2,
      paymentMethod: method,
      customerName: 'Olinda',
      date: DateTime(2026, 10, 30, 15, 20),
    );

void main() {
  setUpAll(() => initializeDateFormatting('es_CO', null));

  group('comprobante', () {
    final sales = [_sale('abcdef123456', 'Arroz', 2, 3000), _sale('x2', 'Panela', 1, 2500, method: 'FIADO')];

    test('suma el total y toma el número de la primera venta', () {
      final doc = DigitalTicketModal.buildReceipt(sales, discount: 500);
      expect(doc.number, 'ABCDEF12');
      expect(doc.total, 8500);
      expect(doc.subtotal, 9000);
      expect(doc.paymentMethod, 'Efectivo');
      expect(doc.isQuotation, isFalse);
    });

    test('el fiado lleva aviso', () {
      final doc = DigitalTicketModal.buildReceipt([sales[1]]);
      expect(doc.paymentMethod, 'Fiado');
      expect(doc.notice, contains('fiado'));
    });

    test('el texto trae negocio, líneas, descuento, total y el pie', () {
      final text = DigitalTicketModal.buildReceipt(sales, discount: 500).toText('Tienda Olinda');
      expect(text, contains('*Tienda Olinda*'));
      expect(text, contains('2 x Arroz'));
      expect(text, contains('Descuento: -'));
      expect(text, contains('Cliente: Olinda'));
      expect(text.trim().endsWith('Hecho con Stockealo'), isTrue);
    });
  });

  test('la cotización muestra la validez y "Total estimado"', () {
    final doc = SaleDocument(
      title: 'Cotización',
      number: 'COT-0001',
      date: DateTime(2026, 10, 30),
      validUntil: DateTime(2026, 11, 6),
      lines: const [SaleDocumentLine(quantity: 3, name: 'Cuaderno', unitPrice: 4000, total: 12000)],
      total: 12000,
      closing: 'Para confirmar tu pedido, responde a este mensaje.',
    );
    expect(doc.isQuotation, isTrue);
    expect(doc.toText('Papelería'), contains('Válida hasta el 06/11/2026'));
  });

  testWidgets('la tarjeta se dibuja con el nombre, el título y el total', (tester) async {
    final business = Business(id: 'b1', userId: 'u1', name: 'Tienda Olinda', color: '#BE185D', createdAt: DateTime(2026));
    final doc = DigitalTicketModal.buildReceipt([_sale('abcdef123456', 'Arroz', 2, 3000)]);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SaleDocumentCard(business: business, businessName: business.name, doc: doc),
        ),
      ),
    ));
    expect(find.text('Tienda Olinda'), findsOneWidget);
    expect(find.text('Comprobante de venta'), findsOneWidget);
    expect(find.text('T'), findsOneWidget); // inicial en lugar del logo
    expect(find.text('Hecho con Stockealo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
