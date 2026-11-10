import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../../backup/data/auto_backup_service.dart';

/// Importador guiado de Excel (0.12.0), para quien ya lleva sus productos en un
/// Excel hecho a mano: encuentra la hoja y la fila de los títulos, propone qué es
/// cada columna (la persona lo corrige), muestra cómo quedarán los productos con
/// avisos por fila y, antes de importar, guarda una copia para poder deshacer.

/// Qué representa una columna
enum ImportField {
  name('Nombre'),
  code('Código'),
  category('Categoría'),
  cost('Costo'),
  price('Precio de venta'),
  stock('Stock'),
  minStock('Stock mínimo'),
  ignore('Ignorar');

  final String label;
  const ImportField(this.label);
}

/// Una hoja del archivo con sus celdas como texto
class ImportTable {
  final String name;
  final List<List<String>> rows;

  const ImportTable(this.name, this.rows);
}

/// Un producto leído del archivo, con sus avisos
class ImportRow {
  /// Número de fila en el archivo (empieza en 1, como en Excel)
  final int line;
  final String name;
  final String? code;
  final String? category;
  final double? cost;
  final double? price;
  final int? stock;
  final int? minStock;
  final List<String> issues;

  const ImportRow({
    required this.line,
    required this.name,
    this.code,
    this.category,
    this.cost,
    this.price,
    this.stock,
    this.minStock,
    this.issues = const [],
  });
}

/// Si el stock del archivo reemplaza al actual o se suma
enum StockMode { replace, add }

class ImportOutcome {
  final int created;
  final int updated;
  final int skipped;
  final bool backedUp;

  const ImportOutcome({required this.created, required this.updated, required this.skipped, required this.backedUp});
}

class GuidedImport {
  GuidedImport._();

  /// Palabras con las que se reconoce cada columna (sin tildes, en minúscula)
  static const _synonyms = <ImportField, List<String>>{
    ImportField.code: ['codigo', 'cod', 'sku', 'barra', 'barras', 'referencia', 'ref', 'ean', 'id producto'],
    ImportField.name: ['nombre', 'producto', 'descripcion', 'articulo', 'item', 'detalle'],
    ImportField.category: ['categoria', 'linea', 'familia', 'grupo', 'tipo', 'seccion'],
    ImportField.cost: ['costo', 'compra', 'precio compra', 'precio de compra', 'valor compra', 'p compra', 'costo unitario'],
    ImportField.price: ['precio', 'venta', 'pvp', 'valor', 'precio venta', 'precio de venta', 'valor venta', 'p venta', 'precio publico'],
    ImportField.stock: ['stock', 'cantidad', 'existencia', 'existencias', 'unidades', 'inventario', 'cant', 'saldo'],
    ImportField.minStock: ['minimo', 'stock minimo', 'alerta', 'reorden', 'min'],
  };

  static String fold(String s) {
    const from = 'áéíóúüñÁÉÍÓÚÜÑ';
    const to = 'aeiouunAEIOUUN';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i < 0 ? ch : to[i]);
    }
    return b.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Qué campo parece ser un título; null si no se reconoce
  static ImportField? fieldOf(String header) {
    final h = fold(header);
    if (h.isEmpty) return null;
    // Primero las frases más largas: "precio de compra" es costo, no precio de venta
    ImportField? best;
    var bestLength = 0;
    for (final e in _synonyms.entries) {
      for (final w in e.value) {
        final matches = h == w || h.startsWith('$w ') || h.endsWith(' $w') || h.contains(' $w ') || (w.length >= 4 && h.contains(w));
        if (matches && w.length > bestLength) {
          best = e.key;
          bestLength = w.length;
        }
      }
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // Lectura
  // ---------------------------------------------------------------------------

  /// Lee un .xlsx o un .csv. Un .xls viejo no se puede leer: hay que guardarlo como .xlsx.
  static List<ImportTable> read(Uint8List bytes, String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.xls')) {
      throw const FormatException('Ese archivo es de un Excel antiguo (.xls). Ábrelo en Excel y usa «Guardar como» › «Libro de Excel (.xlsx)».');
    }
    if (lower.endsWith('.csv') || lower.endsWith('.txt')) return [ImportTable('CSV', parseCsv(_decode(bytes)))];
    final excel = Excel.decodeBytes(bytes);
    return [
      for (final name in excel.tables.keys)
        ImportTable(name, [
          for (final row in excel.tables[name]!.rows)
            [for (final cell in row) _cellText(cell?.value)],
        ]),
    ];
  }

  static String _decode(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static String _cellText(CellValue? v) => switch (v) {
        null => '',
        IntCellValue(:final value) => '$value',
        DoubleCellValue(:final value) => value == value.roundToDouble() ? '${value.toInt()}' : '$value',
        TextCellValue() => v.value.toString().trim(),
        _ => v.toString().trim(),
      };

  /// CSV separado por coma o por punto y coma, con comillas
  static List<List<String>> parseCsv(String text) {
    final clean = text.replaceFirst('﻿', '');
    final firstLine = clean.split(RegExp(r'\r?\n')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final sep = ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length ? ';' : ',';
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < clean.length; i++) {
      final ch = clean[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < clean.length && clean[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == sep) {
        row.add(cell.toString().trim());
        cell.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < clean.length && clean[i + 1] == '\n') i++;
        row.add(cell.toString().trim());
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString().trim());
      rows.add(row);
    }
    return rows.where((r) => r.any((c) => c.isNotEmpty)).toList();
  }

  // ---------------------------------------------------------------------------
  // Detección
  // ---------------------------------------------------------------------------

  /// Fila de los títulos: la primera (de las 15 primeras) con al menos dos títulos
  /// reconocidos y uno de ellos el nombre. -1 si no se encuentra.
  static int headerRowOf(ImportTable t) {
    for (var i = 0; i < t.rows.length && i < 15; i++) {
      final fields = t.rows[i].map(fieldOf).whereType<ImportField>().toSet();
      if (fields.length >= 2 && fields.contains(ImportField.name)) return i;
    }
    for (var i = 0; i < t.rows.length && i < 15; i++) {
      if (t.rows[i].map(fieldOf).whereType<ImportField>().toSet().length >= 2) return i;
    }
    return -1;
  }

  /// La hoja con productos: la que tiene títulos reconocibles y más filas
  static ImportTable? productSheet(List<ImportTable> tables) {
    ImportTable? best;
    var bestScore = -1;
    for (final t in tables) {
      final h = headerRowOf(t);
      if (h < 0) continue;
      final name = fold(t.name);
      if (name.contains('cliente') || name.contains('fiado')) continue;
      // Más títulos reconocidos pesa más que más filas
      final score = t.rows[h].map(fieldOf).whereType<ImportField>().length * 1000 + t.rows.length - h;
      if (score > bestScore) {
        best = t;
        bestScore = score;
      }
    }
    return best ?? (tables.length == 1 ? tables.first : null);
  }

  /// Propuesta de qué es cada columna (la persona la puede cambiar)
  static Map<int, ImportField> guessMapping(List<String> header) {
    final map = <int, ImportField>{};
    final used = <ImportField>{};
    for (var i = 0; i < header.length; i++) {
      final f = fieldOf(header[i]);
      if (f != null && !used.contains(f)) {
        map[i] = f;
        used.add(f);
      } else {
        map[i] = ImportField.ignore;
      }
    }
    return map;
  }

  /// Valor de dinero o cantidad escrito como sea: "$12.500", "12,500", "12.500,50", "1500"
  static double? parseAmount(String raw) {
    var s = raw.replaceAll(RegExp(r'[^0-9,.\-]'), '');
    if (s.isEmpty || s == '-') return null;
    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      // El último separador es el decimal
      final decimal = lastDot > lastComma ? '.' : ',';
      final thousands = decimal == '.' ? ',' : '.';
      s = s.replaceAll(thousands, '').replaceAll(decimal, '.');
    } else if (lastDot >= 0 || lastComma >= 0) {
      final sep = lastDot >= 0 ? '.' : ',';
      final parts = s.split(sep);
      // "12.500" o "1,250,000": miles. "12.5" o "12,50": decimales
      final looksThousands = parts.length > 2 || (parts.length == 2 && parts.last.length == 3);
      s = looksThousands ? parts.join() : parts.join('.');
    }
    return double.tryParse(s);
  }

  /// Los productos tal como quedarán, con avisos por fila
  static List<ImportRow> buildRows(ImportTable t, int headerRow, Map<int, ImportField> mapping) {
    int? col(ImportField f) {
      for (final e in mapping.entries) {
        if (e.value == f) return e.key;
      }
      return null;
    }

    String cell(List<String> row, int? i) => i == null || i >= row.length ? '' : row[i].trim();
    final nameCol = col(ImportField.name);
    final result = <ImportRow>[];
    final seenCodes = <String>{};
    for (var r = headerRow + 1; r < t.rows.length; r++) {
      final row = t.rows[r];
      if (row.every((c) => c.trim().isEmpty)) continue;
      final issues = <String>[];
      final name = cell(row, nameCol);
      if (name.isEmpty) issues.add('Sin nombre: no se importa');
      double? amount(ImportField f, String label) {
        final text = cell(row, col(f));
        if (text.isEmpty) return null;
        final v = parseAmount(text);
        if (v == null || v < 0) issues.add('$label no válido: «$text»');
        return v != null && v >= 0 ? v : null;
      }

      final code = cell(row, col(ImportField.code));
      if (code.isNotEmpty && !seenCodes.add(code.toUpperCase())) issues.add('Código repetido en el archivo: $code');
      result.add(ImportRow(
        line: r + 1,
        name: name,
        code: code.isEmpty ? null : code,
        category: cell(row, col(ImportField.category)).isEmpty ? null : cell(row, col(ImportField.category)),
        cost: amount(ImportField.cost, 'Costo'),
        price: amount(ImportField.price, 'Precio'),
        stock: amount(ImportField.stock, 'Stock')?.round(),
        minStock: amount(ImportField.minStock, 'Stock mínimo')?.round(),
        issues: issues,
      ));
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Importar
  // ---------------------------------------------------------------------------

  /// Guarda una copia (si el equipo puede) y crea o actualiza los productos.
  /// Las filas sin nombre o con código repetido se omiten.
  static Future<ImportOutcome> apply({
    required String businessId,
    required List<ImportRow> rows,
    required bool updateExisting,
    required StockMode stockMode,
  }) async {
    var backedUp = false;
    if (AutoBackupService.instance.isSupported) {
      try {
        await AutoBackupService.instance.backupNow();
        backedUp = true;
      } catch (e) {
        debugPrint('No se pudo guardar la copia antes de importar: $e');
      }
    }
    final db = await AppDatabase.instance.database;
    var created = 0, updated = 0, skipped = 0;
    for (final r in rows) {
      if (r.name.isEmpty || r.issues.any((i) => i.startsWith('Código repetido'))) {
        skipped++;
        continue;
      }
      final existing = await db.query(
        'products',
        where: r.code != null
            ? 'business_id = ? AND (code = ? OR LOWER(name) = ?)'
            : 'business_id = ? AND LOWER(name) = ?',
        whereArgs: [businessId, if (r.code != null) r.code, r.name.toLowerCase()],
        limit: 1,
      );
      final now = DateTime.now().toIso8601String();
      if (existing.isNotEmpty) {
        if (!updateExisting) {
          skipped++;
          continue;
        }
        final e = existing.first;
        final current = (e['stock'] as num?)?.toInt() ?? 0;
        final stock = r.stock == null ? current : (stockMode == StockMode.add ? current + r.stock! : r.stock!);
        await db.update(
          'products',
          {
            if (r.category != null) 'category': r.category,
            if (r.cost != null) 'purchase_price': r.cost,
            if (r.price != null) 'sale_price': r.price,
            'stock': stock,
            if (r.minStock != null) 'min_stock': r.minStock,
            'is_active': 1,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [e['id']],
        );
        final rowsAfter = await db.query('products', where: 'id = ?', whereArgs: [e['id']], limit: 1);
        SupabaseService.instance.upsertProductToCloud(rowsAfter.first);
        updated++;
      } else {
        final product = {
          'id': const Uuid().v4(),
          'business_id': businessId,
          'code': r.code ?? 'PRD-${DateTime.now().millisecondsSinceEpoch % 1000000}-${r.line}',
          'name': r.name,
          'description': null,
          'category': r.category ?? 'General',
          'purchase_price': r.cost ?? 0,
          'sale_price': r.price ?? 0,
          'stock': r.stock ?? 0,
          'min_stock': r.minStock ?? 5,
          'photo_path': null,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
          'is_synced': 0,
        };
        await db.insert('products', product);
        SupabaseService.instance.upsertProductToCloud(product);
        created++;
      }
    }
    return ImportOutcome(created: created, updated: updated, skipped: skipped, backedUp: backedUp);
  }

  /// Plantilla de ejemplo para quien empieza de cero
  static List<int> template() {
    final excel = Excel.createExcel();
    final sheet = excel['Productos'];
    excel.delete('Sheet1');
    sheet.appendRow([for (final h in ['Nombre', 'Código', 'Categoría', 'Costo', 'Precio de venta', 'Stock', 'Stock mínimo']) TextCellValue(h)]);
    sheet.appendRow([
      TextCellValue('Arroz Diana 500 g'), TextCellValue('7702001'), TextCellValue('Granos'),
      const IntCellValue(2100), const IntCellValue(2800), const IntCellValue(24), const IntCellValue(6),
    ]);
    sheet.appendRow([
      TextCellValue('Gaseosa 400 ml'), TextCellValue('7702002'), TextCellValue('Bebidas'),
      const IntCellValue(1500), const IntCellValue(2500), const IntCellValue(36), const IntCellValue(12),
    ]);
    final bytes = excel.encode();
    if (bytes == null) throw Exception('No se pudo crear la plantilla.');
    return bytes;
  }
}
