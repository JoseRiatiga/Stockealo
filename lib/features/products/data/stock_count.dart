import 'dart:convert';

import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../business/data/branch_repository.dart';
import '../../../core/utils/business_clock.dart';
import '../models/product.dart';
import 'lots_repository.dart';
import 'product_repository.dart';

/// Lo contado de un producto o de una talla/color
class CountLine {
  final String productId;
  final String? variantId;

  /// Lo que decía la app cuando se contó (para que las ventas de mientras no se pierdan)
  final int expected;
  final int counted;

  const CountLine({required this.productId, this.variantId, required this.expected, required this.counted});

  int get diff => counted - expected;

  String get key => variantId == null ? productId : '$productId|$variantId';

  Map<String, dynamic> toJson() => {'p': productId, 'v': variantId, 'e': expected, 'c': counted};

  factory CountLine.fromJson(Map<String, dynamic> j) => CountLine(
        productId: j['p'] as String,
        variantId: j['v'] as String?,
        expected: (j['e'] as num).toInt(),
        counted: (j['c'] as num).toInt(),
      );
}

/// Cuánto sobró y cuánto faltó, en unidades y en plata a costo
class CountSummary {
  final int surplusUnits;
  final int missingUnits;
  final double surplusValue;
  final double missingValue;
  final int counted;
  final int withDifference;

  const CountSummary({
    required this.surplusUnits,
    required this.missingUnits,
    required this.surplusValue,
    required this.missingValue,
    required this.counted,
    required this.withDifference,
  });

  double get net => surplusValue - missingValue;
}

/// Conteo de inventario (0.17.0, bloque C): se cuenta por categoría, se puede dejar a
/// medias (el borrador queda en este celular) y al terminar cada diferencia queda como
/// ajuste en el historial con el motivo «Conteo del [fecha]».
///
/// Un campo vacío es «no contado», nunca cero. La diferencia se aplica sobre el stock
/// de ese momento: si se vendió algo mientras se contaba, esa venta no se pierde.
class StockCount {
  final String businessId;
  final DateTime startedAt;
  final Map<String, CountLine> lines;

  StockCount({required this.businessId, required this.startedAt, Map<String, CountLine>? lines}) : lines = lines ?? {};

  /// Un borrador por sede (0.18.0): lo contado en una sede no se aplica a otra
  static String draftKey(String businessId) {
    final branch = BranchRepository.active;
    return branch == null ? 'stock_count_$businessId' : 'stock_count_${businessId}_$branch';
  }

  /// El borrador guardado en este celular, o null
  static Future<StockCount?> load(String businessId) async {
    final raw = await AppDatabase.instance.getSetting(draftKey(businessId));
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return StockCount(
        businessId: businessId,
        startedAt: DateTime.parse(j['at'] as String),
        lines: {
          for (final l in (j['lines'] as List).map((e) => CountLine.fromJson(Map<String, dynamic>.from(e as Map)))) l.key: l,
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save() => AppDatabase.instance.setSetting(
        draftKey(businessId),
        jsonEncode({'at': startedAt.toIso8601String(), 'lines': [for (final l in lines.values) l.toJson()]}),
      );

  Future<void> discard() => AppDatabase.instance.setSetting(draftKey(businessId), null);

  /// Anota lo contado ([counted] null = no contado)
  void set(Product product, int? counted, {String? variantId}) {
    final key = variantId == null ? product.id : '${product.id}|$variantId';
    if (counted == null || counted < 0) {
      lines.remove(key);
      return;
    }
    final previous = lines[key];
    final expected = previous?.expected ??
        (variantId == null ? product.stock : product.variants.where((v) => v.id == variantId).firstOrNull?.stock ?? 0);
    lines[key] = CountLine(productId: product.id, variantId: variantId, expected: expected, counted: counted);
  }

  /// Una lectura del lector de códigos: suma 1 a lo contado
  int addOne(Product product, {String? variantId}) {
    final key = variantId == null ? product.id : '${product.id}|$variantId';
    final next = (lines[key]?.counted ?? 0) + 1;
    set(product, next, variantId: variantId);
    return next;
  }

  int? countedOf(String productId, [String? variantId]) => lines[variantId == null ? productId : '$productId|$variantId']?.counted;

  /// Resumen con el costo de cada producto
  CountSummary summary(Map<String, Product> products) {
    var surplus = 0, missing = 0, withDiff = 0;
    var surplusValue = 0.0, missingValue = 0.0;
    for (final l in lines.values) {
      final cost = products[l.productId]?.purchasePrice ?? 0;
      if (l.diff > 0) {
        surplus += l.diff;
        surplusValue += l.diff * cost;
      } else if (l.diff < 0) {
        missing -= l.diff;
        missingValue -= l.diff * cost;
      }
      if (l.diff != 0) withDiff++;
    }
    return CountSummary(
      surplusUnits: surplus,
      missingUnits: missing,
      surplusValue: surplusValue,
      missingValue: missingValue,
      counted: lines.length,
      withDifference: withDiff,
    );
  }

  /// «Conteo del 22/11/2026»
  String get reason => 'Conteo del ${DateFormat('dd/MM/yyyy').format(startedAt)}';

  /// Aplica las diferencias como ajustes (con el stock de ahora) y borra el borrador.
  /// Devuelve cuántos productos cambiaron.
  Future<int> apply({ProductRepository? repository}) async {
    final repo = repository ?? ProductRepository.instance;
    final byProduct = <String, List<CountLine>>{};
    for (final l in lines.values) {
      if (l.diff != 0) byProduct.putIfAbsent(l.productId, () => []).add(l);
    }
    var changed = 0;
    for (final entry in byProduct.entries) {
      final product = await repo.getProductById(entry.key, businessId);
      if (product == null) continue;
      final variantLines = entry.value.where((l) => l.variantId != null).toList();
      if (variantLines.isNotEmpty) {
        final variants = await repo.getVariantsForProduct(product.id);
        final next = <String, int>{};
        for (final l in variantLines) {
          final v = variants.where((x) => x.id == l.variantId).firstOrNull;
          if (v == null) continue;
          next[v.id] = (v.stock + l.diff).clamp(0, 1 << 30);
        }
        if (next.isEmpty) continue;
        await repo.adjustVariantStocks(product, next, reason);
      } else {
        final l = entry.value.first;
        await repo.adjustStock(product.id, businessId, (product.stock + l.diff).clamp(0, 1 << 30), reason);
      }
      changed++;
      // Lo ya ajustado sale del borrador: si algo falla después, al reintentar no se
      // vuelve a sumar (hallazgo de la revisión)
      for (final l in entry.value) {
        lines.remove(l.key);
      }
      await save();
    }
    // Lotes: lo que faltó sale de los lotes; lo que sobró queda «sin fecha»
    if (changed > 0) await LotsRepository.instance.reconcile(businessId, now: appNow());
    await discard();
    return changed;
  }
}
