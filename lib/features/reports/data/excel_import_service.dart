import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';

class ImportPreview {
  final int productsFound;
  final int customersFound;
  final List<String> productSampleNames;
  final List<String> customerSampleNames;
  final String filePath;

  const ImportPreview({
    required this.productsFound,
    required this.customersFound,
    required this.productSampleNames,
    required this.customerSampleNames,
    required this.filePath,
  });
}

class ImportResult {
  final bool success;
  final int productsImported;
  final int productsUpdated;
  final int customersImported;
  final String? errorMessage;

  const ImportResult({
    required this.success,
    this.productsImported = 0,
    this.productsUpdated = 0,
    this.customersImported = 0,
    this.errorMessage,
  });
}

class ExcelImportService {
  static final ExcelImportService instance = ExcelImportService._internal();
  ExcelImportService._internal();

  final AppDatabase _dbProvider = AppDatabase.instance;

  /// Analiza un archivo Excel y devuelve un resumen previo de lo que contiene
  Future<ImportPreview> inspectExcel(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('El archivo seleccionado no existe.');
    }

    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    int productsCount = 0;
    int customersCount = 0;
    final List<String> productSamples = [];
    final List<String> customerSamples = [];

    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null || sheet.rows.isEmpty) continue;

      final tableNameLower = table.toLowerCase();

      // Analizar si es hoja de inventario/productos
      if (tableNameLower.contains('inventario') ||
          tableNameLower.contains('producto') ||
          tableNameLower.contains('stock') ||
          (excel.tables.keys.length == 1)) {
        final rows = sheet.rows;
        if (rows.length > 1) {
          // Detectar columnas en la fila 0
          final headerRow = rows[0];
          int nameIdx = -1;
          for (int i = 0; i < headerRow.length; i++) {
            final val = headerRow[i]?.value?.toString().toLowerCase() ?? '';
            if (val.contains('nombre') || val.contains('producto') || val.contains('descripcion')) {
              nameIdx = i;
              break;
            }
          }

          for (int r = 1; r < rows.length; r++) {
            final row = rows[r];
            if (row.isEmpty) continue;
            final nameVal = nameIdx != -1 && nameIdx < row.length ? row[nameIdx]?.value?.toString().trim() : null;
            if (nameVal != null && nameVal.isNotEmpty) {
              productsCount++;
              if (productSamples.length < 5) productSamples.add(nameVal);
            }
          }
        }
      }

      // Analizar si es hoja de clientes/deudas
      if (tableNameLower.contains('cliente') || tableNameLower.contains('fiado')) {
        final rows = sheet.rows;
        if (rows.length > 1) {
          for (int r = 1; r < rows.length; r++) {
            final row = rows[r];
            if (row.isEmpty) continue;
            final nameVal = row.isNotEmpty ? row[0]?.value?.toString().trim() : null;
            if (nameVal != null && nameVal.isNotEmpty) {
              customersCount++;
              if (customerSamples.length < 5) customerSamples.add(nameVal);
            }
          }
        }
      }
    }

    return ImportPreview(
      productsFound: productsCount,
      customersFound: customersCount,
      productSampleNames: productSamples,
      customerSampleNames: customerSamples,
      filePath: filePath,
    );
  }

  /// Ejecuta la importación masiva en la base de datos local
  Future<ImportResult> executeImport({
    required String filePath,
    required String businessId,
    bool updateExisting = true,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('El archivo no existe.');
      }

      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final db = await _dbProvider.database;

      int importedProducts = 0;
      int updatedProducts = 0;
      int importedCustomers = 0;

      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null || sheet.rows.length < 2) continue;

        final tableNameLower = table.toLowerCase();
        final rows = sheet.rows;
        final header = rows[0];

        // 1. Procesar Hoja de Inventario / Productos
        if (tableNameLower.contains('inventario') ||
            tableNameLower.contains('producto') ||
            tableNameLower.contains('stock') ||
            (excel.tables.keys.length == 1 && !tableNameLower.contains('cliente'))) {
          
          int codeIdx = -1;
          int nameIdx = -1;
          int categoryIdx = -1;
          int costIdx = -1;
          int priceIdx = -1;
          int stockIdx = -1;
          int minStockIdx = -1;

          for (int c = 0; c < header.length; c++) {
            final h = header[c]?.value?.toString().toLowerCase().trim() ?? '';
            if (h.contains('código') || h.contains('codigo') || h.contains('sku') || h.contains('barra')) {
              codeIdx = c;
            } else if (h.contains('nombre') || h.contains('producto')) {
              nameIdx = c;
            } else if (h.contains('categoría') || h.contains('categoria')) {
              categoryIdx = c;
            } else if (h.contains('compra') || h.contains('costo')) {
              costIdx = c;
            } else if (h.contains('venta') || h.contains('precio')) {
              priceIdx = c;
            } else if (h.contains('stock actual') || h == 'stock' || h.contains('cantidad') || h.contains('existencia')) {
              stockIdx = c;
            } else if (h.contains('mínimo') || h.contains('minimo') || h.contains('alerta')) {
              minStockIdx = c;
            }
          }

          if (nameIdx == -1 && header.length > 1) nameIdx = 1;
          if (codeIdx == -1) codeIdx = 0;

          for (int r = 1; r < rows.length; r++) {
            final row = rows[r];
            if (row.isEmpty) continue;

            final name = nameIdx != -1 && nameIdx < row.length ? row[nameIdx]?.value?.toString().trim() : '';
            if (name == null || name.isEmpty) continue;

            String code = codeIdx != -1 && codeIdx < row.length ? row[codeIdx]?.value?.toString().trim() ?? '' : '';
            if (code.isEmpty) {
              code = 'PRD-${DateTime.now().millisecondsSinceEpoch % 1000000}-$r';
            }

            final category = (categoryIdx != -1 && categoryIdx < row.length)
                ? row[categoryIdx]?.value?.toString().trim() ?? 'General'
                : 'General';

            final cost = (costIdx != -1 && costIdx < row.length)
                ? _parseNum(row[costIdx]?.value)
                : 0.0;

            final price = (priceIdx != -1 && priceIdx < row.length)
                ? _parseNum(row[priceIdx]?.value)
                : 0.0;

            final stock = (stockIdx != -1 && stockIdx < row.length)
                ? _parseNum(row[stockIdx]?.value).toInt()
                : 0;

            final minStock = (minStockIdx != -1 && minStockIdx < row.length)
                ? _parseNum(row[minStockIdx]?.value).toInt()
                : 5;

            // Verificar si el producto ya existe en SQLite
            final existing = await db.query(
              'products',
              where: 'business_id = ? AND (code = ? OR name = ?)',
              whereArgs: [businessId, code, name],
              limit: 1,
            );

            final now = DateTime.now().toIso8601String();

            if (existing.isNotEmpty) {
              if (updateExisting) {
                final existingId = existing.first['id'] as String;
                await db.update(
                  'products',
                  {
                    'category': category.isNotEmpty ? category : 'General',
                    'purchase_price': cost > 0 ? cost : existing.first['purchase_price'],
                    'sale_price': price > 0 ? price : existing.first['sale_price'],
                    'stock': stock,
                    'min_stock': minStock,
                    'updated_at': now,
                    'is_active': 1,
                  },
                  where: 'id = ?',
                  whereArgs: [existingId],
                );
                updatedProducts++;

                // Sincronizar a nube si está activa
                SupabaseService.instance.updateProductStockInCloud(existingId, stock);
              }
            } else {
              final newId = const Uuid().v4();
              final productMap = {
                'id': newId,
                'business_id': businessId,
                'code': code,
                'name': name,
                'description': null,
                'category': category.isNotEmpty ? category : 'General',
                'purchase_price': cost,
                'sale_price': price,
                'stock': stock,
                'min_stock': minStock,
                'photo_path': null,
                'is_active': 1,
                'created_at': now,
                'updated_at': now,
                'is_synced': 0,
              };

              await db.insert('products', productMap);
              importedProducts++;

              // Sincronizar a nube si está activa
              SupabaseService.instance.upsertProductToCloud(productMap);
            }
          }
        }

        // 2. Procesar Hoja de Clientes y Fiados
        if (tableNameLower.contains('cliente') || tableNameLower.contains('fiado')) {
          int nameIdx = 0;
          int phoneIdx = -1;
          int addressIdx = -1;
          int debtIdx = -1;

          for (int c = 0; c < header.length; c++) {
            final h = header[c]?.value?.toString().toLowerCase().trim() ?? '';
            if (h.contains('nombre') || h.contains('cliente')) nameIdx = c;
            if (h.contains('teléfono') || h.contains('telefono') || h.contains('celular')) phoneIdx = c;
            if (h.contains('dirección') || h.contains('direccion')) addressIdx = c;
            if (h.contains('deuda') || h.contains('saldo')) debtIdx = c;
          }

          for (int r = 1; r < rows.length; r++) {
            final row = rows[r];
            if (row.isEmpty) continue;

            final name = nameIdx < row.length ? row[nameIdx]?.value?.toString().trim() : '';
            if (name == null || name.isEmpty) continue;

            final phone = (phoneIdx != -1 && phoneIdx < row.length) ? row[phoneIdx]?.value?.toString().trim() : null;
            final address = (addressIdx != -1 && addressIdx < row.length) ? row[addressIdx]?.value?.toString().trim() : null;
            final debt = (debtIdx != -1 && debtIdx < row.length) ? _parseNum(row[debtIdx]?.value) : 0.0;

            final existing = await db.query(
              'customers',
              where: 'business_id = ? AND name = ?',
              whereArgs: [businessId, name],
              limit: 1,
            );

            if (existing.isEmpty) {
              final newId = const Uuid().v4();
              final custMap = {
                'id': newId,
                'business_id': businessId,
                'name': name,
                'phone': phone,
                'address': address,
                'debt_balance': debt,
                'created_at': DateTime.now().toIso8601String(),
                'is_synced': 0,
              };
              await db.insert('customers', custMap);
              importedCustomers++;
              SupabaseService.instance.upsertCustomerToCloud(custMap);
            }
          }
        }
      }

      return ImportResult(
        success: true,
        productsImported: importedProducts,
        productsUpdated: updatedProducts,
        customersImported: importedCustomers,
      );
    } catch (e) {
      debugPrint('Error en importación de Excel: $e');
      return ImportResult(
        success: false,
        errorMessage: 'Error al procesar el archivo Excel: $e',
      );
    }
  }

  double _parseNum(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    final str = val.toString().replaceAll('\$', '').replaceAll(' ', '').replaceAll(',', '.');
    return double.tryParse(str) ?? 0.0;
  }
}
