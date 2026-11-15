import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/business/models/ticket_info.dart';
import 'package:stockealo/features/sales/presentation/widgets/sale_document.dart';

/// 0.15.0: tiquete con NIT, dirección, teléfono y despedida propia
void main() {
  test('los datos del tiquete se guardan y se leen; vacío vuelve al de siempre', () {
    const info = TicketInfo(taxId: '900.123.456-7', address: 'Cra. 7 # 12-34', phone: '3001234567', footer: '¡Vuelve pronto!');
    final back = TicketInfo.decode(info.encode());
    expect(back.headerLines, ['NIT 900.123.456-7', 'Cra. 7 # 12-34', 'Tel. 3001234567']);
    expect(back.footer, '¡Vuelve pronto!');
    expect(const TicketInfo().encode(), isNull);
    expect(TicketInfo.decode('no es json').isEmpty, isTrue);
  });

  test('la despedida propia reemplaza la de siempre, no las que dicen algo útil', () {
    const info = TicketInfo(footer: '¡Vuelve pronto!');
    expect(info.closingFor('¡Gracias por tu compra!'), '¡Vuelve pronto!');
    expect(info.closingFor('Cierre del turno'), 'Cierre del turno');
    expect(TicketInfo.empty.closingFor('¡Gracias por tu compra!'), '¡Gracias por tu compra!');
  });

  test('el texto para WhatsApp lleva el NIT y la despedida', () async {
    await initializeDateFormatting('es_CO');
    final business = Business(
      id: 'b1',
      userId: 'u1',
      name: 'Variedades Rosita',
      createdAt: DateTime(2026, 11, 15),
      ticketInfo: const TicketInfo(taxId: '900.123.456-7', footer: '¡Vuelve pronto!').encode(),
    );
    final doc = SaleDocument(
      title: 'Venta',
      number: 'V-0001',
      date: DateTime(2026, 11, 15, 10),
      lines: const [SaleDocumentLine(quantity: 1, name: 'Arroz', unitPrice: 5000, total: 5000)],
      total: 5000,
      closing: '¡Gracias por tu compra!',
    );
    final text = doc.toText(business.name, TicketInfo.of(business));
    expect(text, contains('NIT 900.123.456-7'));
    expect(text, contains('¡Vuelve pronto!'));
    expect(text, isNot(contains('¡Gracias por tu compra!')));
  });
}
