import '../../suppliers/models/purchase.dart';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../business/models/business.dart';
import '../../team/data/team_repository.dart';

/// Partes que se pueden descargar desde Reportes
enum ReportSection {
  inventory('Inventario', 'Productos, tallas y colores con sus existencias y valor'),
  sales('Ventas', 'Cada venta del periodo, con su talla o color'),
  customers('Clientes y fiados', 'Clientes con su teléfono y lo que deben'),
  movements('Movimientos', 'Entradas, ajustes y anulaciones del inventario en el periodo'),
  profit('Ganancias', 'Lo vendido y ganado por producto en el periodo'),
  purchases('Compras', 'Mercancía que llegó en el periodo, con proveedor, factura y lo que falta pagar'),
  supplierCosts('Costos por proveedor', 'Último costo de cada producto con cada proveedor');

  final String label;
  final String description;
  const ReportSection(this.label, this.description);

  /// Si depende del periodo elegido
  bool get usesPeriod => this == sales || this == movements || this == profit || this == purchases;
}

/// Periodo del reporte. Sin fechas = todo el historial.
@immutable
class ReportPeriod {
  final DateTime? from; // incluido
  final DateTime? to; // excluido
  final String label;

  const ReportPeriod({this.from, this.to, required this.label});

  static const all = ReportPeriod(label: 'Todo');

  static ReportPeriod today([DateTime? now]) {
    final n = now ?? DateTime.now();
    final start = DateTime(n.year, n.month, n.day);
    return ReportPeriod(from: start, to: start.add(const Duration(days: 1)), label: 'Hoy');
  }

  /// Semana de lunes a domingo
  static ReportPeriod thisWeek([DateTime? now]) {
    final n = now ?? DateTime.now();
    final start = DateTime(n.year, n.month, n.day).subtract(Duration(days: n.weekday - 1));
    return ReportPeriod(from: start, to: start.add(const Duration(days: 7)), label: 'Esta semana');
  }

  static ReportPeriod thisMonth([DateTime? now]) {
    final n = now ?? DateTime.now();
    return ReportPeriod(from: DateTime(n.year, n.month), to: DateTime(n.year, n.month + 1), label: 'Este mes');
  }

  /// Del día [first] al día [last], ambos incluidos
  static ReportPeriod range(DateTime first, DateTime last) {
    final from = DateTime(first.year, first.month, first.day);
    final to = DateTime(last.year, last.month, last.day).add(const Duration(days: 1));
    final f = DateFormat('d/M/yyyy');
    return ReportPeriod(from: from, to: to, label: '${f.format(from)} al ${f.format(last)}');
  }

  bool contains(DateTime d) => (from == null || !d.isBefore(from!)) && (to == null || d.isBefore(to!));

  /// Para el nombre del archivo: "" (todo), "2026-11-08" o "2026-11-01_a_2026-11-30"
  String get fileTag {
    if (from == null || to == null) return '';
    final f = DateFormat('yyyy-MM-dd');
    final last = to!.subtract(const Duration(days: 1));
    return f.format(from!) == f.format(last) ? f.format(from!) : '${f.format(from!)}_a_${f.format(last)}';
  }
}

/// Arma los reportes en Excel: todo en un libro con una hoja por parte, o un
/// archivo por cada parte. Reemplaza al Excel único de antes, que siempre traía todo.
class ReportExportService {
  ReportExportService._();
  static final instance = ReportExportService._();

  static const _xlsx = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// Solo dueño o administrador: el reporte trae costos y márgenes
  Future<bool> canExport({required String businessId, required String userId, required String userEmail}) async {
    final role = await TeamRepository.instance.getUserRoleInBusiness(
      businessId: businessId,
      userId: userId,
      userEmail: userEmail,
    );
    return role == 'OWNER' || role == 'ADMIN';
  }

  /// Genera y comparte los archivos. Devuelve sus nombres.
  Future<List<String>> export({
    required Business business,
    required String userId,
    required String userEmail,
    required Set<ReportSection> sections,
    ReportPeriod period = ReportPeriod.all,
    bool singleFile = true,
    void Function()? onGenerated,
  }) async {
    if (sections.isEmpty) throw Exception('Elige al menos una parte del reporte.');
    if (!await canExport(businessId: business.id, userId: userId, userEmail: userEmail)) {
      throw Exception('Solo el dueño o un administrador pueden descargar reportes, porque incluyen costos y ganancias.');
    }
    final db = await AppDatabase.instance.database;
    final ordered = ReportSection.values.where(sections.contains).toList();
    final files = await buildFiles(db: db, business: business, sections: ordered, period: period, singleFile: singleFile);
    onGenerated?.call();
    await _share(files, business);
    return [for (final f in files) f.name];
  }

  /// Arma los libros sin compartirlos (también para pruebas)
  @visibleForTesting
  Future<List<({String name, List<int> bytes})>> buildFiles({
    required DatabaseExecutor db,
    required Business business,
    required List<ReportSection> sections,
    required ReportPeriod period,
    required bool singleFile,
  }) async {
    final biz = business.name.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    final tag = period.fileTag;
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    String fileName(String what, {bool dated = true}) =>
        '${what}_$biz${dated && tag.isNotEmpty ? '_$tag' : ''}${tag.isEmpty || !dated ? '_$stamp' : ''}.xlsx';

    if (singleFile) {
      final excel = Excel.createExcel();
      final first = excel.getDefaultSheet() ?? 'Sheet1';
      for (var i = 0; i < sections.length; i++) {
        final name = _sheetName(sections[i]);
        if (i == 0) excel.rename(first, name);
        await _fill(sections[i], excel[name], db, business, period);
      }
      final what = sections.length == 1 ? _fileWord(sections.first) : 'Reporte_completo';
      return [(name: fileName(what, dated: sections.any((s) => s.usesPeriod)), bytes: _encode(excel))];
    }

    return [
      for (final s in sections)
        await () async {
          final excel = Excel.createExcel();
          final name = _sheetName(s);
          excel.rename(excel.getDefaultSheet() ?? 'Sheet1', name);
          await _fill(s, excel[name], db, business, period);
          return (name: fileName(_fileWord(s), dated: s.usesPeriod), bytes: _encode(excel));
        }(),
    ];
  }

  static String _sheetName(ReportSection s) => s.label;

  static String _fileWord(ReportSection s) => switch (s) {
        ReportSection.inventory => 'Inventario',
        ReportSection.sales => 'Ventas',
        ReportSection.customers => 'Clientes',
        ReportSection.movements => 'Movimientos',
        ReportSection.profit => 'Ganancias',
        ReportSection.purchases => 'Compras',
        ReportSection.supplierCosts => 'Costos_por_proveedor',
      };

  /// encode() y no save(): en la web save() además descarga solo un "FlutterExcel.xlsx"
  static List<int> _encode(Excel excel) {
    final bytes = excel.encode();
    if (bytes == null) throw Exception('No se pudo generar el archivo de Excel.');
    return bytes;
  }

  Future<void> _fill(ReportSection section, Sheet sheet, DatabaseExecutor db, Business b, ReportPeriod p) =>
      switch (section) {
        ReportSection.inventory => _inventory(sheet, db, b),
        ReportSection.sales => _sales(sheet, db, b, p),
        ReportSection.customers => _customers(sheet, db, b),
        ReportSection.movements => _movements(sheet, db, b, p),
        ReportSection.profit => _profit(sheet, db, b, p),
        ReportSection.purchases => _purchases(sheet, db, b, p),
        ReportSection.supplierCosts => _supplierCosts(sheet, db, b),
      };

  /// Entradas de mercancía del negocio; vacío si la base aún no tiene la tabla
  Future<List<Purchase>> _purchasesOf(DatabaseExecutor db, Business b) async {
    try {
      final rows = await db.query('purchases', where: 'business_id = ?', whereArgs: [b.id], orderBy: 'date ASC');
      return rows.map(Purchase.fromMap).toList();
    } on DatabaseException {
      return const [];
    }
  }

  Future<void> _purchases(Sheet sheet, DatabaseExecutor db, Business b, ReportPeriod p) async {
    final cur = b.currency;
    sheet.appendRow(_header([
      'Fecha', 'Proveedor', 'Factura', 'Producto', 'Variante', 'Cantidad', 'Costo unitario ($cur)',
      'Subtotal ($cur)', 'Forma de pago', 'Estado del pago', 'Falta pagar ($cur)',
    ]));
    var units = 0;
    var total = 0.0, owed = 0.0;
    for (final purchase in await _purchasesOf(db, b)) {
      if (!p.contains(purchase.date)) continue;
      final payState = !purchase.isCredit
          ? 'Pagada'
          : (purchase.isPaid ? 'Pagada' : (purchase.isOverdue() ? 'Vencida' : 'Por pagar'));
      for (final (index, i) in purchase.items.indexed) {
        units += i.quantity;
        total += i.subtotal;
        sheet.appendRow([
          TextCellValue(DateFormat('dd/MM/yyyy').format(purchase.date)),
          TextCellValue(purchase.supplierName ?? ''),
          TextCellValue(purchase.invoiceNumber ?? ''),
          TextCellValue(i.productName),
          TextCellValue(i.variantName ?? ''),
          IntCellValue(i.quantity),
          DoubleCellValue(i.unitCost),
          DoubleCellValue(i.subtotal),
          TextCellValue(purchase.isCredit ? 'Crédito' : 'Contado'),
          TextCellValue(payState),
          // Lo que se debe va una sola vez por entrada, en su primer renglón
          DoubleCellValue(index == 0 ? purchase.balance : 0),
        ]);
      }
      owed += purchase.balance;
    }
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue('TOTAL (${p.label})'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      IntCellValue(units),
      TextCellValue(''),
      DoubleCellValue(total),
      TextCellValue(''),
      TextCellValue(''),
      DoubleCellValue(owed),
    ]);
  }

  Future<void> _supplierCosts(Sheet sheet, DatabaseExecutor db, Business b) async {
    final cur = b.currency;
    sheet.appendRow(_header([
      'Producto', 'Proveedor', 'Último costo ($cur)', 'Fecha', 'Costo anterior ($cur)', 'Cambio ($cur)', 'Más barato',
    ]));
    final purchases = await _purchasesOf(db, b);
    final names = <String, String>{
      for (final p in purchases)
        for (final i in p.items) i.productId: i.productName,
    };
    final costs = SupplierCost.latestByProduct(purchases);
    final products = costs.keys.toList()..sort((a, b) => (names[a] ?? '').toLowerCase().compareTo((names[b] ?? '').toLowerCase()));
    for (final id in products) {
      for (final (index, c) in costs[id]!.indexed) {
        sheet.appendRow([
          TextCellValue(names[id] ?? 'Producto'),
          TextCellValue(c.supplierName),
          DoubleCellValue(c.unitCost),
          TextCellValue(DateFormat('dd/MM/yyyy').format(c.date)),
          if (c.previousCost == null) TextCellValue('') else DoubleCellValue(c.previousCost!),
          if (c.change == null) TextCellValue('') else DoubleCellValue(c.change!),
          TextCellValue(index == 0 && costs[id]!.length > 1 ? 'Sí' : ''),
        ]);
      }
    }
  }

  static List<TextCellValue> _header(List<String> titles) => [for (final t in titles) TextCellValue(t)];

  Future<void> _inventory(Sheet sheet, DatabaseExecutor db, Business b) async {
    final cur = b.currency;
    sheet.appendRow(_header([
      'Código / SKU', 'Producto', 'Variante', 'Categoría', 'Precio costo ($cur)', 'Precio venta ($cur)',
      'Margen (%)', 'Existencias', 'Stock mínimo', 'Valor al costo ($cur)', 'Valor a la venta ($cur)', 'Estado',
    ]));
    final products = await db.query('products',
        where: 'business_id = ? AND is_active = 1', whereArgs: [b.id], orderBy: 'name COLLATE NOCASE ASC');
    final variants = await db.query('product_variants', where: 'business_id = ?', whereArgs: [b.id]);
    final byProduct = <String, List<Map<String, Object?>>>{};
    for (final v in variants) {
      byProduct.putIfAbsent(v['product_id'] as String, () => []).add(v);
    }
    for (final p in products) {
      final cost = (p['purchase_price'] as num?)?.toDouble() ?? 0;
      final price = (p['sale_price'] as num?)?.toDouble() ?? 0;
      final minStock = (p['min_stock'] as num?)?.toInt() ?? 5;
      final margin = price > 0 ? (price - cost) / price * 100 : 0.0;
      void row(String variant, String code, int stock, double extra) {
        final unitPrice = price + extra;
        sheet.appendRow([
          TextCellValue(code),
          TextCellValue(p['name'] as String? ?? ''),
          TextCellValue(variant),
          TextCellValue(p['category'] as String? ?? 'General'),
          DoubleCellValue(cost),
          DoubleCellValue(unitPrice),
          DoubleCellValue(double.parse(margin.toStringAsFixed(1))),
          IntCellValue(stock),
          IntCellValue(minStock),
          DoubleCellValue(cost * stock),
          DoubleCellValue(unitPrice * stock),
          TextCellValue(stock <= 0 ? 'Agotado' : (stock <= minStock ? 'Bajo stock' : 'Óptimo')),
        ]);
      }

      final vs = (p['has_variants'] as int? ?? 0) == 1 ? (byProduct[p['id']] ?? const []) : const [];
      if (vs.isEmpty) {
        row('', p['code'] as String? ?? '', (p['stock'] as num?)?.toInt() ?? 0, 0);
      } else {
        // Una fila por talla y color: así se ve cuántas quedan de cada una
        for (final v in vs) {
          final first = (v['attribute_value'] as String? ?? '').trim();
          final second = (v['attribute2_value'] as String? ?? '').trim();
          final label = [first, second].where((x) => x.isNotEmpty).join(' · ');
          row(label, (v['sku_or_barcode'] as String?)?.trim().isNotEmpty == true ? v['sku_or_barcode'] as String : p['code'] as String? ?? '',
              (v['stock'] as num?)?.toInt() ?? 0, (v['additional_price'] as num?)?.toDouble() ?? 0);
        }
      }
    }
  }

  Future<List<Map<String, Object?>>> _salesIn(DatabaseExecutor db, Business b, ReportPeriod p) async {
    final rows = await db.query('sales', where: 'business_id = ?', whereArgs: [b.id], orderBy: 'date DESC');
    return [
      for (final s in rows)
        if (p.from == null || (DateTime.tryParse(s['date'] as String? ?? '') != null &&
            p.contains(DateTime.parse(s['date'] as String).toLocal())))
          s,
    ];
  }

  Future<void> _sales(Sheet sheet, DatabaseExecutor db, Business b, ReportPeriod p) async {
    final cur = b.currency;
    sheet.appendRow(_header([
      'Fecha y hora', 'Factura', 'Producto', 'Variante', 'Cantidad', 'Precio unitario ($cur)', 'Total ($cur)',
      'Costo ($cur)', 'Ganancia ($cur)', 'Método de pago', 'Cliente', 'Vendedor',
    ]));
    final f = DateFormat('yyyy-MM-dd HH:mm');
    var units = 0;
    var total = 0.0, cost = 0.0, profit = 0.0;
    for (final s in await _salesIn(db, b, p)) {
      final qty = (s['quantity'] as num?)?.toInt() ?? 1;
      final t = (s['total'] as num?)?.toDouble() ?? 0;
      final c = (s['total_cost'] as num?)?.toDouble() ?? 0;
      final n = (s['net_profit'] as num?)?.toDouble() ?? (t - c);
      final date = DateTime.tryParse(s['date'] as String? ?? '');
      units += qty;
      total += t;
      cost += c;
      profit += n;
      sheet.appendRow([
        TextCellValue(date == null ? '${s['date']}' : f.format(date.toLocal())),
        TextCellValue(s['invoice_number'] as String? ?? ''),
        TextCellValue(s['product_name'] as String? ?? ''),
        TextCellValue(s['variant_name'] as String? ?? ''),
        IntCellValue(qty),
        DoubleCellValue(qty > 0 ? t / qty : 0),
        DoubleCellValue(t),
        DoubleCellValue(c),
        DoubleCellValue(n),
        TextCellValue(_paymentLabel(s['payment_method'] as String?)),
        TextCellValue(s['customer_name'] as String? ?? 'Consumidor final'),
        TextCellValue(s['seller_name'] as String? ?? ''),
      ]);
    }
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue('TOTAL (${p.label})'), TextCellValue(''), TextCellValue(''), TextCellValue(''),
      IntCellValue(units), TextCellValue(''), DoubleCellValue(total), DoubleCellValue(cost), DoubleCellValue(profit),
    ]);
  }

  static String _paymentLabel(String? m) => switch ((m ?? '').toUpperCase()) {
        'EFECTIVO' => 'Efectivo',
        'TRANSFERENCIA' => 'Transferencia',
        'FIADO' => 'Fiado',
        '' => 'Efectivo',
        _ => m!,
      };

  Future<void> _customers(Sheet sheet, DatabaseExecutor db, Business b) async {
    sheet.appendRow(_header(['Cliente', 'Teléfono', 'Dirección', 'Debe (${b.currency})', 'Cliente desde', 'Estado']));
    final rows = await db.query('customers', where: 'business_id = ?', whereArgs: [b.id], orderBy: 'debt_balance DESC');
    final f = DateFormat('yyyy-MM-dd');
    for (final c in rows) {
      final debt = (c['debt_balance'] as num?)?.toDouble() ?? 0;
      final created = DateTime.tryParse(c['created_at'] as String? ?? '');
      sheet.appendRow([
        TextCellValue(c['name'] as String? ?? ''),
        TextCellValue(c['phone'] as String? ?? ''),
        TextCellValue(c['address'] as String? ?? ''),
        DoubleCellValue(debt),
        TextCellValue(created == null ? '' : f.format(created.toLocal())),
        TextCellValue(debt > 0 ? 'Con saldo pendiente' : 'Al día'),
      ]);
    }
  }

  Future<void> _movements(Sheet sheet, DatabaseExecutor db, Business b, ReportPeriod p) async {
    sheet.appendRow(_header(['Fecha y hora', 'Producto', 'Tipo', 'Cantidad', 'Existencias después', 'Motivo']));
    final rows = await db.rawQuery(
      'SELECT m.*, pr.name AS product_name FROM stock_movements m '
      'LEFT JOIN products pr ON pr.id = m.product_id WHERE m.business_id = ? ORDER BY m.date DESC',
      [b.id],
    );
    final f = DateFormat('yyyy-MM-dd HH:mm');
    for (final m in rows) {
      final date = DateTime.tryParse(m['date'] as String? ?? '');
      if (p.from != null && (date == null || !p.contains(date.toLocal()))) continue;
      sheet.appendRow([
        TextCellValue(date == null ? '' : f.format(date.toLocal())),
        TextCellValue(m['product_name'] as String? ?? '(producto borrado)'),
        TextCellValue(_movementLabel(m['type'] as String?)),
        IntCellValue((m['quantity'] as num?)?.toInt() ?? 0),
        IntCellValue((m['resulting_stock'] as num?)?.toInt() ?? 0),
        TextCellValue(m['reason'] as String? ?? ''),
      ]);
    }
  }

  static String _movementLabel(String? t) => switch ((t ?? '').toUpperCase()) {
        'ENTRADA_COMPRA' => 'Entrada',
        'SALIDA_VENTA' || 'VENTA' => 'Venta',
        'AJUSTE' => 'Ajuste',
        'DEVOLUCION' => 'Devolución',
        _ => t ?? '',
      };

  Future<void> _profit(Sheet sheet, DatabaseExecutor db, Business b, ReportPeriod p) async {
    final cur = b.currency;
    sheet.appendRow(_header(['Producto', 'Unidades vendidas', 'Ventas ($cur)', 'Costo ($cur)', 'Ganancia ($cur)', 'Margen (%)']));
    final byProduct = <String, ({int units, double total, double cost})>{};
    for (final s in await _salesIn(db, b, p)) {
      final name = s['product_name'] as String? ?? 'Producto';
      final prev = byProduct[name] ?? (units: 0, total: 0.0, cost: 0.0);
      byProduct[name] = (
        units: prev.units + ((s['quantity'] as num?)?.toInt() ?? 1),
        total: prev.total + ((s['total'] as num?)?.toDouble() ?? 0),
        cost: prev.cost + ((s['total_cost'] as num?)?.toDouble() ?? 0),
      );
    }
    final ranked = byProduct.entries.toList()
      ..sort((a, b) => (b.value.total - b.value.cost).compareTo(a.value.total - a.value.cost));
    var units = 0;
    var total = 0.0, cost = 0.0;
    for (final e in ranked) {
      final gain = e.value.total - e.value.cost;
      units += e.value.units;
      total += e.value.total;
      cost += e.value.cost;
      sheet.appendRow([
        TextCellValue(e.key),
        IntCellValue(e.value.units),
        DoubleCellValue(e.value.total),
        DoubleCellValue(e.value.cost),
        DoubleCellValue(gain),
        DoubleCellValue(e.value.total > 0 ? double.parse((gain / e.value.total * 100).toStringAsFixed(1)) : 0),
      ]);
    }
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue('TOTAL (${p.label})'),
      IntCellValue(units),
      DoubleCellValue(total),
      DoubleCellValue(cost),
      DoubleCellValue(total - cost),
      DoubleCellValue(total > 0 ? double.parse(((total - cost) / total * 100).toStringAsFixed(1)) : 0),
    ]);
  }

  Future<void> _share(List<({String name, List<int> bytes})> files, Business b) async {
    if (kIsWeb) {
      await Share.shareXFiles(
        [for (final f in files) XFile.fromData(Uint8List.fromList(f.bytes), name: f.name, mimeType: _xlsx)],
        subject: 'Reporte de ${b.name}',
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final paths = <XFile>[];
    for (final f in files) {
      final path = '${dir.path}/${f.name}';
      await File(path).writeAsBytes(f.bytes);
      paths.add(XFile(path, mimeType: _xlsx));
    }
    await Share.shareXFiles(paths, subject: 'Reporte de ${b.name}');
  }
}
