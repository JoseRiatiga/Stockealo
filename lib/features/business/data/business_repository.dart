import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../models/business.dart';

class BusinessRepository {
  static final BusinessRepository instance = BusinessRepository._internal();
  BusinessRepository._internal();

  final AppDatabase _dbProvider = AppDatabase.instance;
  static Business? _activeBusiness;

  /// Negocio activo actual en memoria
  Business? get currentActiveBusiness => _activeBusiness;

  /// Obtiene el negocio activo para un usuario (null si no tiene empresas aún)
  Future<Business?> getActiveBusiness(String userId, [String? userEmail]) async {
    if (_activeBusiness != null) {
      return _activeBusiness!;
    }

    final list = await getAllBusinesses(userId, userEmail);
    if (list.isNotEmpty) {
      _activeBusiness = list.first;
      return _activeBusiness;
    }

    _activeBusiness = null;
    return null;
  }

  /// Cambia la empresa activa en el contexto de trabajo
  void setActiveBusiness(Business? business) {
    _activeBusiness = business;
  }

  /// Purga definitivamente empresas en papelera que superaron los 7 días
  Future<void> purgeExpiredDeletedBusinesses() async {
    final db = await _dbProvider.database;
    final limitDate = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    await db.delete(
      'businesses',
      where: 'is_deleted = 1 AND deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [limitDate],
    );
  }

  /// Obtiene todas las empresas activas registradas para este usuario (como dueño o como miembro del equipo)
  Future<List<Business>> getAllBusinesses(String userId, [String? userEmail]) async {
    await purgeExpiredDeletedBusinesses();
    final db = await _dbProvider.database;
    final cleanEmail = userEmail?.trim().toLowerCase() ?? '';
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT DISTINCT b.* FROM businesses b
      LEFT JOIN business_members m ON b.id = m.business_id
      WHERE (b.is_deleted = 0 OR b.is_deleted IS NULL)
        AND (b.user_id = ? OR m.user_id = ? OR (m.email IS NOT NULL AND LOWER(m.email) = ?))
      ORDER BY b.created_at ASC
    ''', [userId, userId, cleanEmail]);
    return maps.map((map) => Business.fromMap(map)).toList();
  }

  /// Obtiene las empresas en papelera (eliminadas hace menos de 7 días)
  Future<List<Business>> getDeletedBusinesses(String userId) async {
    await purgeExpiredDeletedBusinesses();
    final db = await _dbProvider.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'businesses',
      where: 'user_id = ? AND is_deleted = 1',
      whereArgs: [userId],
      orderBy: 'deleted_at DESC',
    );
    return maps.map((map) => Business.fromMap(map)).toList();
  }

  /// Crea una nueva empresa 100% limpia para este usuario
  Future<Business> createBusiness({
    required String name,
    required String userId,
    String currency = 'COP',
  }) async {
    final db = await _dbProvider.database;
    final business = Business(
      id: const Uuid().v4(),
      userId: userId,
      name: name.trim(),
      currency: currency,
      createdAt: DateTime.now(),
    );

    await db.insert('businesses', business.toMap());
    _activeBusiness = business;
    return business;
  }

  /// Actualiza los datos de una empresa (nombre y moneda)
  Future<void> updateBusiness({
    required String id,
    required String name,
    required String currency,
  }) async {
    final db = await _dbProvider.database;
    await db.update(
      'businesses',
      {
        'name': name.trim(),
        'currency': currency,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    if (_activeBusiness?.id == id) {
      _activeBusiness = _activeBusiness!.copyWith(
        name: name.trim(),
        currency: currency,
      );
    }
  }

  /// Mueve una empresa a la papelera (conservando datos durante 7 días)
  Future<void> softDeleteBusiness(String id) async {
    final db = await _dbProvider.database;
    await db.update(
      'businesses',
      {
        'is_deleted': 1,
        'deleted_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    if (_activeBusiness?.id == id) {
      _activeBusiness = null;
    }
  }

  /// Restaura una empresa que estaba en la papelera
  Future<void> restoreBusiness(String id) async {
    final db = await _dbProvider.database;
    await db.update(
      'businesses',
      {
        'is_deleted': 0,
        'deleted_at': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
