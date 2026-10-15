import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/app_database.dart';
import '../../business/models/business.dart';
import '../../team/data/team_repository.dart';

class ExcelExportService {
  static final ExcelExportService instance = ExcelExportService._internal();
  ExcelExportService._internal();

  final AppDatabase _dbProvider = AppDatabase.instance;
  final TeamRepository _teamRepo = TeamRepository.instance;

  /// Verifica si el usuario actual tiene permiso para exportar a Excel (solo OWNER y ADMIN)
  Future<bool> canUserExport({
    required String businessId,
    required String userId,
    required String userEmail,
  }) async {
    final role = await _teamRepo.getUserRoleInBusiness(
      businessId: businessId,
      userId: userId,
      userEmail: userEmail,
    );
    return role == 'OWNER' || role == 'ADMIN';
  }

  /// Exporta el archivo completo de Excel (.xlsx) con 3 hojas: Inventario, Ventas, Clientes/Fiados
  Future<String> exportBusinessData({
    required Business business,
    required String userId,
    required String userEmail,
    void Function()? onGenerated,
  }) async {
    // Validación estricta de permisos (Opción A)
    final allowed = await canUserExport(
      businessId: business.id,
      userId: userId,
      userEmail: userEmail,
    );
    if (!allowed) {
      throw Exception(
        'Solo los propietarios y administradores pueden exportar a Excel para proteger los márgenes y costos del negocio.',
      );
    }

    final db = await _dbProvider.database;
    final excel = Excel.createExcel();

    // 1. Hoja 1: Inventario
    excel.rename('Sheet1', 'Inventario');
    final Sheet sheetInventario = excel['Inventario'];

    // Cabecera Inventario
    sheetInventario.appendRow([
      TextCellValue('Código / SKU'),
      TextCellValue('Producto'),
      TextCellValue('Categoría'),
      TextCellValue('Precio Costo (${business.currency})'),
      TextCellValue('Precio Venta (${business.currency})'),
      TextCellValue('Margen (%)'),
      TextCellValue('Stock Actual'),
      TextCellValue('Stock Mínimo'),
      TextCellValue('Valor Total Costo (${business.currency})'),
      TextCellValue('Valor Total Venta (${business.currency})'),
      TextCellValue('Estado'),
    ]);

    final products = await db.query(
      'products',
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [business.id],
      orderBy: 'name ASC',
    );

    for (final p in products) {
      final purchasePrice = (p['purchase_price'] as num?)?.toDouble() ?? 0.0;
      final salePrice = (p['sale_price'] as num?)?.toDouble() ?? 0.0;
      final stock = (p['stock'] as num?)?.toInt() ?? 0;
      final minStock = (p['min_stock'] as num?)?.toInt() ?? 5;
      final margin = salePrice > 0 ? ((salePrice - purchasePrice) / salePrice) * 100 : 0.0;
      final totalCost = purchasePrice * stock;
      final totalSale = salePrice * stock;

      String estado;
      if (stock <= 0) {
        estado = 'Agotado';
      } else if (stock <= minStock) {
        estado = 'Bajo Stock';
      } else {
        estado = 'Óptimo';
      }

      sheetInventario.appendRow([
        TextCellValue(p['code'] as String? ?? ''),
        TextCellValue(p['name'] as String? ?? ''),
        TextCellValue(p['category'] as String? ?? 'General'),
        DoubleCellValue(purchasePrice),
        DoubleCellValue(salePrice),
        DoubleCellValue(double.parse(margin.toStringAsFixed(1))),
        IntCellValue(stock),
        IntCellValue(minStock),
        DoubleCellValue(totalCost),
        DoubleCellValue(totalSale),
        TextCellValue(estado),
      ]);
    }

    // 2. Hoja 2: Ventas
    final Sheet sheetVentas = excel['Ventas'];
    sheetVentas.appendRow([
      TextCellValue('Fecha y Hora'),
      TextCellValue('Producto'),
      TextCellValue('Cantidad'),
      TextCellValue('Precio Unitario (${business.currency})'),
      TextCellValue('Costo Unitario (${business.currency})'),
      TextCellValue('Total Venta (${business.currency})'),
      TextCellValue('Costo Total (${business.currency})'),
      TextCellValue('Ganancia Neta (${business.currency})'),
      TextCellValue('Método de Pago'),
      TextCellValue('Cliente'),
      TextCellValue('Estado de Pago'),
    ]);

    final sales = await db.query(
      'sales',
      where: 'business_id = ?',
      whereArgs: [business.id],
      orderBy: 'date DESC',
    );

    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    for (final s in sales) {
      final dateStr = s['date'] as String? ?? '';
      final parsedDate = DateTime.tryParse(dateStr);
      final formattedDate = parsedDate != null ? dateFormat.format(parsedDate) : dateStr;

      final quantity = (s['quantity'] as num?)?.toInt() ?? 1;
      final total = (s['total'] as num?)?.toDouble() ?? 0.0;
      final totalCost = (s['total_cost'] as num?)?.toDouble() ?? 0.0;
      final netProfit = (s['net_profit'] as num?)?.toDouble() ?? 0.0;
      final unitPrice = quantity > 0 ? total / quantity : 0.0;
      final unitCost = quantity > 0 ? totalCost / quantity : 0.0;

      sheetVentas.appendRow([
        TextCellValue(formattedDate),
        TextCellValue(s['product_name'] as String? ?? ''),
        IntCellValue(quantity),
        DoubleCellValue(unitPrice),
        DoubleCellValue(unitCost),
        DoubleCellValue(total),
        DoubleCellValue(totalCost),
        DoubleCellValue(netProfit),
        TextCellValue(s['payment_method'] as String? ?? 'EFECTIVO'),
        TextCellValue(s['customer_name'] as String? ?? 'Consumidor Final'),
        TextCellValue(s['payment_status'] as String? ?? 'PAGADO'),
      ]);
    }

    // 3. Hoja 3: Clientes y Deudas (Fiados)
    final Sheet sheetClientes = excel['Clientes y Fiados'];
    sheetClientes.appendRow([
      TextCellValue('Cliente'),
      TextCellValue('Teléfono'),
      TextCellValue('Dirección'),
      TextCellValue('Saldo Deuda (${business.currency})'),
      TextCellValue('Fecha Registro'),
      TextCellValue('Estado Deuda'),
    ]);

    final customers = await db.query(
      'customers',
      where: 'business_id = ?',
      whereArgs: [business.id],
      orderBy: 'debt_balance DESC',
    );

    for (final c in customers) {
      final debt = (c['debt_balance'] as num?)?.toDouble() ?? 0.0;
      final createdAt = c['created_at'] as String? ?? '';
      final parsedCreated = DateTime.tryParse(createdAt);
      final formattedCreated = parsedCreated != null ? DateFormat('yyyy-MM-dd').format(parsedCreated) : createdAt;

      sheetClientes.appendRow([
        TextCellValue(c['name'] as String? ?? ''),
        TextCellValue(c['phone'] as String? ?? '-'),
        TextCellValue(c['address'] as String? ?? '-'),
        DoubleCellValue(debt),
        TextCellValue(formattedCreated),
        TextCellValue(debt > 0 ? 'Con saldo pendiente' : 'Al día'),
      ]);
    }

    // Guardar archivo y compartir
    final fileBytes = excel.save();
    if (fileBytes == null) {
      throw Exception('No se pudo generar el archivo de Excel.');
    }

    final sanitizedBizName = business.name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'Reporte_${sanitizedBizName}_$timestamp.xlsx';

    if (kIsWeb) {
      onGenerated?.call();
      await Share.shareXFiles(
        [
          XFile.fromData(
            Uint8List.fromList(fileBytes),
            name: fileName,
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject: 'Reporte Excel Stockealo - ${business.name}',
      );
      return fileName;
    }

    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/$fileName';

    final file = File(filePath);
    await file.writeAsBytes(fileBytes);

    onGenerated?.call();

    await Share.shareXFiles(
      [XFile(filePath, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      subject: 'Reporte Excel Stockealo - ${business.name}',
      text: 'Exportación de datos de Stockealo (${business.name}) generada el ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}.',
    );

    return filePath;
  }
}
