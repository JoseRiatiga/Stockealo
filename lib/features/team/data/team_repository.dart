import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../models/business_member.dart';

class TeamRepository {
  static final TeamRepository instance = TeamRepository._internal();
  TeamRepository._internal();

  final AppDatabase _dbProvider = AppDatabase.instance;

  /// Obtiene los miembros y empleados de una empresa
  Future<List<BusinessMember>> getMembers(String businessId) async {
    final db = await _dbProvider.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'business_members',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => BusinessMember.fromMap(m)).toList();
  }

  /// Añade un empleado por su correo electrónico con un rol asignado
  Future<BusinessMember> addMember({
    required String businessId,
    required String email,
    required String role,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw Exception('Ingresa un correo electrónico válido.');
    }

    final db = await _dbProvider.database;

    // Verificar si ya está en el equipo de este negocio
    final existing = await db.query(
      'business_members',
      where: 'business_id = ? AND LOWER(email) = ?',
      whereArgs: [businessId, cleanEmail],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      throw Exception('Este usuario ya forma parte del equipo de esta empresa.');
    }

    // Verificar si el usuario ya está registrado en la app para asociar su user_id
    final userQuery = await db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: [cleanEmail],
      limit: 1,
    );
    final String? linkedUserId = userQuery.isNotEmpty ? userQuery.first['id'] as String : null;

    final member = BusinessMember(
      id: const Uuid().v4(),
      businessId: businessId,
      userId: linkedUserId,
      email: cleanEmail,
      role: role,
      status: 'ACTIVE',
      createdAt: DateTime.now(),
    );

    await db.insert('business_members', member.toMap());
    return member;
  }

  /// Cambia el rol de un miembro
  Future<void> updateRole(String memberId, String newRole) async {
    final db = await _dbProvider.database;
    await db.update(
      'business_members',
      {'role': newRole},
      where: 'id = ?',
      whereArgs: [memberId],
    );
  }

  /// Elimina un miembro del equipo de la empresa
  Future<void> removeMember(String memberId) async {
    final db = await _dbProvider.database;
    await db.delete(
      'business_members',
      where: 'id = ?',
      whereArgs: [memberId],
    );
  }

  /// Determina el rol del usuario en la empresa actual
  Future<String> getUserRoleInBusiness({
    required String businessId,
    required String userId,
    required String userEmail,
  }) async {
    final db = await _dbProvider.database;

    // 1. ¿Es el dueño fundador de la empresa?
    final bizQuery = await db.query(
      'businesses',
      where: 'id = ? AND user_id = ?',
      whereArgs: [businessId, userId],
      limit: 1,
    );

    if (bizQuery.isNotEmpty) {
      return 'OWNER';
    }

    // 2. ¿Está en la lista de miembros de la empresa?
    final memberQuery = await db.query(
      'business_members',
      where: 'business_id = ? AND (user_id = ? OR LOWER(email) = ?)',
      whereArgs: [businessId, userId, userEmail.trim().toLowerCase()],
      limit: 1,
    );

    if (memberQuery.isNotEmpty) {
      return memberQuery.first['role'] as String;
    }

    // Por defecto, si tiene acceso pero no rol definido
    return 'CASHIER';
  }
}
