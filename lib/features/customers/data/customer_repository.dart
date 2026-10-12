import 'dart:math';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../models/customer.dart';
import '../models/customer_payment.dart';

class PaymentResult {
  final Customer customer;
  final CustomerPayment payment;
  final double previousDebt;
  final double remainingDebt;

  const PaymentResult({
    required this.customer,
    required this.payment,
    required this.previousDebt,
    required this.remainingDebt,
  });
}

class CustomerRepository {
  static final CustomerRepository instance = CustomerRepository._internal();
  CustomerRepository._internal();

  final AppDatabase _dbProvider = AppDatabase.instance;

  /// Obtiene todos los clientes de una empresa ordenados por saldo deudor descendente
  Future<List<Customer>> getCustomers(String businessId) async {
    final db = await _dbProvider.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'debt_balance DESC, name ASC',
    );
    return maps.map((m) => Customer.fromMap(m)).toList();
  }

  /// Obtiene un cliente por su ID
  Future<Customer?> getCustomerById(String id) async {
    final db = await _dbProvider.database;
    final maps = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isNotEmpty) return Customer.fromMap(maps.first);
    return null;
  }

  /// Crea un nuevo cliente
  Future<Customer> createCustomer({
    required String businessId,
    required String name,
    String? phone,
    String? address,
    double initialDebt = 0.0,
  }) async {
    final db = await _dbProvider.database;
    final customer = Customer(
      id: const Uuid().v4(),
      businessId: businessId,
      name: name.trim(),
      phone: phone?.trim().isNotEmpty == true ? phone!.trim() : null,
      address: address?.trim().isNotEmpty == true ? address!.trim() : null,
      debtBalance: max(0.0, initialDebt),
      createdAt: DateTime.now(),
    );

    final map = customer.toMap();
    await db.insert('customers', map);

    // Sincronizar en tiempo real si la nube está activa
    SupabaseService.instance.upsertCustomerToCloud(map);

    return customer;
  }

  /// Actualiza datos del cliente
  Future<void> updateCustomer({
    required String id,
    required String name,
    String? phone,
    String? address,
  }) async {
    final db = await _dbProvider.database;
    await db.update(
      'customers',
      {
        'name': name.trim(),
        'phone': phone?.trim().isNotEmpty == true ? phone!.trim() : null,
        'address': address?.trim().isNotEmpty == true ? address!.trim() : null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    final updated = await getCustomerById(id);
    if (updated != null) {
      SupabaseService.instance.upsertCustomerToCloud(updated.toMap());
    }
  }

  /// Obtiene el historial de abonos de un cliente
  Future<List<CustomerPayment>> getCustomerPayments(String customerId) async {
    final db = await _dbProvider.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customer_payments',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'date DESC',
    );
    return maps.map((m) => CustomerPayment.fromMap(m)).toList();
  }

  /// Registra un abono a la deuda del cliente y descuenta el saldo pendiente
  Future<PaymentResult> recordPayment({
    required String customerId,
    required String businessId,
    required double amount,
    required String paymentMethod, // 'EFECTIVO' | 'TRANSFERENCIA'
    String? notes,
  }) async {
    if (amount <= 0) {
      throw Exception('El monto del abono debe ser mayor a cero.');
    }

    final db = await _dbProvider.database;
    final customer = await getCustomerById(customerId);
    if (customer == null) {
      throw Exception('Cliente no encontrado.');
    }

    final previousDebt = customer.debtBalance;
    if (previousDebt <= 0) {
      throw Exception('El cliente ya se encuentra al día y no tiene deudas pendientes.');
    }

    final remainingDebt = max(0.0, previousDebt - amount);
    final now = DateTime.now();

    final payment = CustomerPayment(
      id: const Uuid().v4(),
      businessId: businessId,
      customerId: customerId,
      amount: amount,
      paymentMethod: paymentMethod,
      date: now,
      notes: notes?.trim().isNotEmpty == true ? notes!.trim() : null,
    );

    await db.transaction((txn) async {
      // 1. Guardar registro de abono
      await txn.insert('customer_payments', payment.toMap());

      // 2. Actualizar saldo en la tabla de clientes
      await txn.update(
        'customers',
        {
          'debt_balance': remainingDebt,
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );
    });

    final updatedCustomer = customer.copyWith(debtBalance: remainingDebt);

    // Sincronizar actualización de saldo a Supabase
    SupabaseService.instance.upsertCustomerToCloud(updatedCustomer.toMap());

    return PaymentResult(
      customer: updatedCustomer,
      payment: payment,
      previousDebt: previousDebt,
      remainingDebt: remainingDebt,
    );
  }

  /// Elimina un cliente
  Future<void> deleteCustomer(String id) async {
    final db = await _dbProvider.database;
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }
}
