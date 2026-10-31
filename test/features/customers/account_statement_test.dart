import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/customers/data/account_statement.dart';

void main() {
  group('estado de cuenta', () {
    final sales = [
      {'date': '2026-10-01T10:00:00', 'product_name': 'Arroz', 'quantity': 2, 'total': 10000, 'invoice_number': 'F-1'},
      {'date': '2026-10-10T10:00:00', 'product_name': 'Aceite', 'quantity': 1, 'total': 8000},
    ];
    final payments = [
      {'date': '2026-10-05T18:00:00', 'amount': 4000, 'payment_method': 'EFECTIVO', 'notes': null},
    ];

    test('ordena por fecha y lleva el saldo acumulado', () {
      final st = AccountStatement.fromRows(fiadoSales: sales, payments: payments, currentBalance: 14000);
      expect(st.entries.map((e) => e.description), ['Arroz ×2 · F-1', 'Abono en efectivo', 'Aceite']);
      expect(st.entries.map((e) => e.balance), [10000, 6000, 14000]);
      expect(st.openingBalance, 0);
      expect(st.totalCharges, 18000);
      expect(st.totalPayments, 4000);
      expect(st.balance, 14000);
    });

    test('una deuda que no sale de los movimientos va como saldo anterior', () {
      final st = AccountStatement.fromRows(fiadoSales: sales, payments: payments, currentBalance: 20000);
      expect(st.openingBalance, 6000);
      expect(st.entries.last.balance, 20000);
    });

    test('sin movimientos el saldo es el del cliente', () {
      final st = AccountStatement.fromRows(fiadoSales: const [], payments: const [], currentBalance: 5000);
      expect(st.entries, isEmpty);
      expect(st.openingBalance, 5000);
    });

    test('el mensaje para compartir lleva el nombre y el saldo', () {
      final text = AccountStatementService.shareMessage(customerName: 'Ana', businessName: 'Tienda', balance: r'$ 14.000');
      expect(text, contains('Ana'));
      expect(text, contains('Tienda'));
      expect(text, contains(r'$ 14.000'));
    });
  });
}
