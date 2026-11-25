import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/permissions/permissions.dart';
import 'package:stockealo/features/business/data/transfer_repository.dart';
import 'package:stockealo/features/home/data/app_functions.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/team/data/shift_lead.dart';

// Traslados entre sedes y encargado de turno (0.18.5)
Product _p(String id, {int stock = 0, int min = 0}) => Product(
      id: id,
      businessId: 'b',
      code: id,
      name: 'Producto $id',
      category: 'General',
      purchasePrice: 1000,
      salePrice: 2000,
      stock: stock,
      minStock: min,
      createdAt: DateTime(2026, 11, 25),
      updatedAt: DateTime(2026, 11, 25),
    );

void main() {
  test('un traslado se lee de la nube con sus líneas y faltantes', () {
    final t = StockTransfer.fromMap({
      'id': 't1',
      'business_id': 'b',
      'from_branch_id': null,
      'to_branch_id': 'norte',
      'status': 'RECEIVED',
      'sent_by_email': 'a@b.co',
      'sent_at': '2026-11-25T15:00:00Z',
      'received_as_lead': true,
      'stock_transfer_lines': [
        {'id': 'l1', 'product_id': 'p1', 'product_name': 'Shampoo', 'sent': 5, 'received': 4},
        {'id': 'l2', 'product_id': 'p2', 'variant_key': 'v1', 'product_name': 'Camiseta', 'variant_label': 'M', 'sent': 2, 'received': 2},
      ],
    });
    expect(t.fromBranchId, isNull);
    expect(t.units, 7);
    expect(t.receivedUnits, 6);
    expect(t.missing, 1);
    expect(t.receivedAsLead, isTrue);
    expect(t.lines.last.label, 'Camiseta · M');
    expect(t.inTransit, isFalse);
  });

  test('lo que se envía no puede pasar de lo que hay', () {
    final line = TransferDraftLine(product: _p('p1', stock: 3), available: 3, quantity: 4);
    expect(line.tooMany, isTrue);
    line.quantity = 3;
    expect(line.tooMany, isFalse);
  });

  test('los errores de la nube tienen su mensaje', () {
    expect(TransferRepository.friendlyError('not_enough_stock'), contains('unidades suficientes'));
    expect(TransferRepository.friendlyError('transfer_not_in_transit'), contains('ya no está en camino'));
    expect(TransferRepository.friendlyError('perm_denied:cancel'), contains('cancelarlo'));
    expect(TransferRepository.friendlyError('SocketException: x'), TransferRepository.needsConnection);
  });

  test('sugerencia: trae lo que aquí falta y la otra sede tiene de sobra', () {
    final here = [_p('a', stock: 1, min: 5), _p('b', stock: 9, min: 2), _p('c', stock: 0, min: 1)];
    final norte = [_p('a', stock: 12, min: 2), _p('b', stock: 1, min: 0), _p('c', stock: 1, min: 1)];
    final found = TransferRepository.suggestions(here: here, others: {'norte': norte});
    expect(found, hasLength(1));
    expect(found.first.fromBranchId, 'norte');
    // «a»: le faltan 5 para pasar su mínimo; «c»: Norte no tiene de sobra
    expect(found.first.items.map((i) => (i.product.id, i.quantity)), [('a', 5)]);
  });

  test('cómo se dice hasta cuándo es encargado', () {
    final now = DateTime(2026, 11, 25, 10);
    expect(ShiftLead.describe(DateTime(2026, 11, 25, 18), now: now), 'hasta las 6:00 p. m.');
    expect(ShiftLead.describe(DateTime(2026, 11, 26, 9, 30), now: now), 'hasta mañana a las 9:30 a. m.');
    expect(ShiftLead.describe(now.add(ShiftLead.untilRemoved), now: now), 'hasta que lo quiten');
  });

  test('el encargado vigente cierra la caja de otros; al vencer, ya no', () {
    final saved = Permissions.current;
    addTearDown(() {
      Permissions.current = saved;
      Permissions.leadUntil = null;
    });
    Permissions.current = Permissions.cashier;
    expect(Permissions.mine(Perm.cashOthers), isFalse);
    Permissions.leadUntil = DateTime.now().add(const Duration(hours: 1));
    expect(Permissions.mine(Perm.cashOthers), isTrue);
    // Solo eso: sigue sin ver costos
    expect(Permissions.mine(Perm.costs), isFalse);
    Permissions.leadUntil = DateTime.now().subtract(const Duration(minutes: 1));
    expect(Permissions.mine(Perm.cashOthers), isFalse);
  });

  test('«Traslados» está en el buscador y vive en Stock', () {
    final f = findFunctions('traslado', role: Permissions.owner, services: false).first;
    expect(f.id, 'transfers');
    expect(f.tab, 8);
  });
}
