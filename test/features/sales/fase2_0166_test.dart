import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/permissions/permissions.dart';
import 'package:stockealo/features/customers/models/customer.dart';
import 'package:stockealo/features/home/data/app_functions.dart';
import 'package:stockealo/features/home/presentation/widgets/global_search_dialog.dart';
import 'package:stockealo/features/sales/models/sale.dart';
import 'package:stockealo/features/sales/presentation/screens/sales_history_screen.dart';

/// 0.16.6: «Ventas registradas» cuenta comprobantes y las devoluciones aparte (N3)
void main() {
  Sale line(String id, {String? invoice, String? returnOf, int qty = 1}) => Sale(
        id: id,
        productId: 'p1',
        productName: 'Camiseta',
        quantity: qty,
        unitPrice: 10000,
        unitCost: 6000,
        totalAmount: 10000.0 * qty,
        netProfit: 4000.0 * qty,
        paymentMethod: 'EFECTIVO',
        date: DateTime(2026, 11, 17, 10),
        invoiceNumber: invoice,
        returnOf: returnOf,
      );

  test('4 ventas y 1 devolución: la devolución no suma como venta', () {
    final groups = SalesHistoryScreen.groupByInvoice([
      line('a1', invoice: '#A1'),
      line('a2', invoice: '#A1'),
      line('b1', invoice: '#B2'),
      line('c1', invoice: '#C3'),
      line('d1'),
      line('r1', invoice: '#A1', returnOf: 'a1', qty: -1),
    ]);
    expect(groups.length, 5);
    expect(SalesHistoryScreen.countLabel(groups), '4 ventas · 1 devolución');
  });

  test('Singular y sin devoluciones', () {
    final one = SalesHistoryScreen.groupByInvoice([line('a1', invoice: '#A1')]);
    expect(SalesHistoryScreen.countLabel(one), '1 venta');
    expect(SalesHistoryScreen.countLabel(const []), '0 ventas');
  });

  test('Buscador: «caja» trae abrir, cerrar, entrada y salida de dinero (hallazgo 47)', () {
    final titles = findFunctions('caja', role: Permissions.owner, services: false).map((f) => f.title).toList();
    expect(titles, containsAll(['Caja', 'Cerrar caja', 'Entrada de dinero', 'Salida de dinero']));
    final devol = findFunctions('devolución', role: Permissions.owner, services: false).map((f) => f.title);
    expect(devol, contains('Devoluciones'));
  });

  test('Buscador: clientes por nombre sin tildes o por teléfono (hallazgo 45)', () {
    Customer cu(String name, String? phone) =>
        Customer(id: name, businessId: 'b', name: name, phone: phone, createdAt: DateTime(2026));
    final all = [cu('Cliente Prueba', '300 123 4567'), cu('Andrés Gómez', null), cu('Lucía', '3109998877')];
    expect(matchCustomers(all, 'prueba').map((c) => c.name), ['Cliente Prueba']);
    expect(matchCustomers(all, 'andres').map((c) => c.name), ['Andrés Gómez']);
    expect(matchCustomers(all, '1234').map((c) => c.name), ['Cliente Prueba']);
    expect(matchCustomers(all, ''), isEmpty);
  });
}
