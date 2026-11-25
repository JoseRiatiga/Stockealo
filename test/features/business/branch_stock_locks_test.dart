import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Candado de sedes (0.18.0): el stock de products y product_variants es el de la sede
/// Principal. Cada lugar que lo escribe tiene que saber qué hacer en una sede extra
/// (BranchRepository.addStock / setStock). Si este número cambia, revisa que la
/// escritura nueva no descuente la Principal cuando hay otra sede elegida, y luego
/// actualiza la cuenta.
void main() {
  test('las escrituras de stock de la Principal están contadas', () {
    final pattern = RegExp(r"UPDATE products SET stock|UPDATE product_variants SET stock|'stock': (newStock|newTotal|stock\b|v\.stock|r\.stock|branch)");
    const expected = {
      'lib/core/services/supabase_service.dart': 2,
      'lib/features/business/data/branch_repository.dart': 2,
      // Traslados (0.18.5): solo cuando la nube ya movió el stock de la Principal
      'lib/features/business/data/transfer_repository.dart': 2,
      'lib/features/products/data/lots_repository.dart': 2,
      'lib/features/products/data/product_repository.dart': 3,
      'lib/features/products/models/product.dart': 1,
      'lib/features/products/models/product_variant.dart': 1,
      'lib/features/reports/data/guided_import.dart': 2,
      'lib/features/sales/data/sales_repository.dart': 7,
      'lib/features/suppliers/data/supplier_repository.dart': 2,
    };
    final found = <String, int>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final n = pattern.allMatches(f.readAsStringSync()).length;
      if (n > 0) found[f.path.replaceAll(r'\', '/')] = n;
    }
    expect(found, expected);
  });
}
