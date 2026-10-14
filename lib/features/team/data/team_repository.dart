import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../../business/data/business_repository.dart';
import '../../business/models/business.dart';
import '../models/business_member.dart';

class TeamRepository {
  static final TeamRepository instance = TeamRepository._internal();
  TeamRepository._internal();

  final AppDatabase _dbProvider = AppDatabase.instance;

  /// Obtiene los miembros y empleados de una empresa con sus nombres resueltos
  Future<List<BusinessMember>> getMembers(String businessId) async {
    final db = await _dbProvider.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT bm.*, COALESCE(bm.name, u.name) as resolved_name
      FROM business_members bm
      LEFT JOIN users u ON (bm.user_id = u.id OR LOWER(bm.email) = LOWER(u.email))
      WHERE bm.business_id = ?
      ORDER BY bm.created_at ASC
    ''', [businessId]);

    return maps.map((m) {
      final data = Map<String, dynamic>.from(m);
      if (data['name'] == null || (data['name'] as String).trim().isEmpty) {
        data['name'] = data['resolved_name'];
      }
      return BusinessMember.fromMap(data);
    }).toList();
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

    // Verificar si ya está en el equipo de este negocio localmente
    final existing = await db.query(
      'business_members',
      where: 'business_id = ? AND LOWER(email) = ?',
      whereArgs: [businessId, cleanEmail],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      throw Exception('Este usuario ya forma parte del equipo de esta empresa.');
    }

    // 1. Verificar si el usuario ya está registrado en la app localmente
    final userQuery = await db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: [cleanEmail],
      limit: 1,
    );
    String? linkedUserId = userQuery.isNotEmpty ? userQuery.first['id'] as String : null;
    String? linkedUserName = userQuery.isNotEmpty ? userQuery.first['name'] as String? : null;

    // 2. Si no está en SQLite local, consultar si ya está registrado en Supabase Cloud
    if (linkedUserId == null) {
      try {
        final client = SupabaseService.instance.client;
        if (client != null) {
          final cloudUser = await client
              .from('users')
              .select('id, name')
              .eq('email', cleanEmail)
              .maybeSingle();
          if (cloudUser != null) {
            linkedUserId = cloudUser['id'] as String?;
            linkedUserName = cloudUser['name'] as String?;
          }
        }
      } catch (_) {}
    }

    final memberName = linkedUserName ?? cleanEmail.split('@').first;
    final member = BusinessMember(
      id: const Uuid().v4(),
      businessId: businessId,
      userId: linkedUserId,
      email: cleanEmail,
      name: memberName,
      role: role,
      status: 'ACTIVE',
      createdAt: DateTime.now(),
    );

    await db.insert('business_members', member.toMap());

    // 3. Sincronizar en tiempo real a Supabase Cloud
    SupabaseService.instance.upsertBusinessMemberToCloud(member.toMap());

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

    // Sincronizar actualización de rol en Supabase en tiempo real
    final updated = await db.query(
      'business_members',
      where: 'id = ?',
      whereArgs: [memberId],
      limit: 1,
    );
    if (updated.isNotEmpty) {
      SupabaseService.instance.upsertBusinessMemberToCloud(updated.first);
    }
  }

  /// Elimina un miembro del equipo de la empresa
  Future<void> removeMember(String memberId) async {
    final db = await _dbProvider.database;
    await db.delete(
      'business_members',
      where: 'id = ?',
      whereArgs: [memberId],
    );

    // Eliminar de Supabase en tiempo real
    SupabaseService.instance.deleteBusinessMemberFromCloud(memberId);
  }

  /// Determina el rol del usuario en la empresa actual
  Future<String> getUserRoleInBusiness({
    required String businessId,
    required String userId,
    required String userEmail,
  }) async {
    final db = await _dbProvider.database;
    final cleanEmail = userEmail.trim().toLowerCase();

    // 1. Consultar primero en la tabla de miembros (fuente de verdad del equipo)
    final memberQuery = await db.query(
      'business_members',
      where: 'business_id = ? AND (user_id = ? OR LOWER(email) = ?)',
      whereArgs: [businessId, userId, cleanEmail],
      limit: 1,
    );

    if (memberQuery.isNotEmpty) {
      return memberQuery.first['role'] as String;
    }

    // 2. Si no tiene registro explícito localmente, consultar Supabase si está disponible
    if (SupabaseService.instance.client != null) {
      try {
        final cloudMember = await SupabaseService.instance.client!
            .from('business_members')
            .select()
            .eq('business_id', businessId)
            .or('user_id.eq.$userId,user_email.ilike.$cleanEmail')
            .maybeSingle();
        if (cloudMember != null) {
          final cloudRole = (cloudMember['role'] as String?) ?? 'CASHIER';
          await db.insert(
            'business_members',
            {
              'id': cloudMember['id'],
              'business_id': businessId,
              'user_id': userId,
              'email': cleanEmail,
              'name': cloudMember['user_name'] ?? cleanEmail.split('@').first,
              'role': cloudRole,
              'status': 'ACTIVE',
              'created_at': cloudMember['created_at'] ?? DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          return cloudRole;
        }
      } catch (_) {}
    }

    // 3. Verificar si existe algún dueño ya registrado en miembros para evitar usurpación accidental
    final existingOwnerQuery = await db.query(
      'business_members',
      where: 'business_id = ? AND role = "OWNER"',
      whereArgs: [businessId],
      limit: 1,
    );
    if (existingOwnerQuery.isNotEmpty) {
      final actualOwnerUserId = existingOwnerQuery.first['user_id'] as String?;
      final actualOwnerEmail = (existingOwnerQuery.first['email'] as String?)?.toLowerCase();
      if (actualOwnerUserId != userId && actualOwnerEmail != cleanEmail) {
        return 'CASHIER';
      }
      return 'OWNER';
    }

    // 4. Si no hay registros de miembros, verificar si coincide con el creador del negocio local
    final bizQuery = await db.query(
      'businesses',
      where: 'id = ? AND user_id = ?',
      whereArgs: [businessId, userId],
      limit: 1,
    );

    if (bizQuery.isNotEmpty) {
      return 'OWNER';
    }

    // Por defecto, rol restringido
    return 'CASHIER';
  }

  /// Une a un usuario a un negocio existente mediante código de invitación o escaneo QR
  Future<Business> joinBusinessByCode({
    required String codeOrId,
    required String userId,
    required String userEmail,
    String? userName,
  }) async {
    String cleanInput = codeOrId.trim();

    // Si viene de un QR con formato URL/Deep link: stockealo://join?biz=UUID o code=CODE
    if (cleanInput.contains('biz=')) {
      final uri = Uri.tryParse(cleanInput);
      if (uri != null && uri.queryParameters.containsKey('biz')) {
        cleanInput = uri.queryParameters['biz']!;
      } else {
        final match = RegExp(r'biz=([a-zA-Z0-9\-]+)').firstMatch(cleanInput);
        if (match != null) {
          cleanInput = match.group(1)!;
        }
      }
    } else if (cleanInput.contains('code=')) {
      final uri = Uri.tryParse(cleanInput);
      if (uri != null && uri.queryParameters.containsKey('code')) {
        cleanInput = uri.queryParameters['code']!;
      }
    }

    cleanInput = cleanInput.replaceAll('-', '').replaceAll(' ', '').trim().toLowerCase();
    if (cleanInput.isEmpty) {
      throw Exception('Ingresa un código de invitación válido.');
    }

    if (!SupabaseService.instance.isInitialized) {
      await SupabaseService.instance.initialize();
    }
    final client = SupabaseService.instance.client;
    if (client == null) {
      throw Exception('No hay conexión con la nube. Verifica tu conexión a internet.');
    }

    // 1. Buscar la empresa en Supabase por ID completo o prefijo de ID
    Map<String, dynamic>? cloudBiz;
    if (cleanInput.length >= 32) {
      try {
        final allBiz = await client.from('businesses').select().eq('is_deleted', 0);
        for (final b in allBiz) {
          final idNoDash = (b['id'] as String).replaceAll('-', '').toLowerCase();
          if (idNoDash == cleanInput) {
            cloudBiz = b;
            break;
          }
        }
      } catch (e) {
        debugPrint('Error buscando por UUID completo: $e');
      }
    }

    if (cloudBiz == null) {
      try {
        final List<dynamic> results = await client
            .from('businesses')
            .select()
            .ilike('id', '$cleanInput%')
            .eq('is_deleted', 0)
            .limit(1);
        if (results.isNotEmpty) {
          cloudBiz = results.first as Map<String, dynamic>;
        }
      } catch (e) {
        debugPrint('Error buscando negocio por prefijo: $e');
      }
    }

    if (cloudBiz == null) {
      throw Exception('Código no encontrado. Verifica con el dueño o administrador de la empresa.');
    }

    final bizId = cloudBiz['id'] as String;
    final bizName = cloudBiz['name'] as String;
    final bizCurrency = (cloudBiz['currency'] as String?) ?? 'COP';

    final db = await _dbProvider.database;

    // 2. Guardar o actualizar la empresa en la base local SQLite
    // Al unirse a una empresa existente, el creador NO es el usuario que se une
    final existingBiz = await db.query('businesses', where: 'id = ?', whereArgs: [bizId], limit: 1);
    final ownerUserId = (cloudBiz['user_id'] as String?) ??
        (existingBiz.isNotEmpty ? existingBiz.first['user_id'] as String? : null) ??
        'remote_owner';

    final business = Business(
      id: bizId,
      userId: ownerUserId,
      name: bizName,
      currency: bizCurrency,
      createdAt: cloudBiz['created_at'] != null
          ? DateTime.tryParse(cloudBiz['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
    await db.insert('businesses', business.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

    // 3. Crear o actualizar membresía en SQLite local
    final cleanEmail = userEmail.trim().toLowerCase();
    final existingMember = await db.query(
      'business_members',
      where: 'business_id = ? AND (user_id = ? OR LOWER(email) = ?)',
      whereArgs: [bizId, userId, cleanEmail],
      limit: 1,
    );

    final resolvedUserName = userName ?? cleanEmail.split('@').first;
    if (existingMember.isEmpty) {
      final member = BusinessMember(
        id: const Uuid().v4(),
        businessId: bizId,
        userId: userId,
        email: cleanEmail,
        name: resolvedUserName,
        role: 'CASHIER',
        status: 'ACTIVE',
        createdAt: DateTime.now(),
      );
      await db.insert('business_members', member.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

      // Sincronizar membresía a Supabase Cloud
      await SupabaseService.instance.upsertBusinessMemberToCloud(member.toMap());
    } else {
      await db.update(
        'business_members',
        {
          'user_id': userId,
          'status': 'ACTIVE',
          if (userName != null) 'name': userName,
        },
        where: 'id = ?',
        whereArgs: [existingMember.first['id']],
      );
      final updatedMap = {
        ...existingMember.first,
        'user_id': userId,
        'status': 'ACTIVE',
        if (userName != null) 'name': userName,
      };
      await SupabaseService.instance.upsertBusinessMemberToCloud(updatedMap);
    }

    // 4. Descargar todos los productos y datos de la empresa desde la nube
    await SupabaseService.instance.syncFromCloud(userId, userEmail);

    // 5. Establecer empresa como activa
    BusinessRepository.instance.setActiveBusiness(business);

    return business;
  }
}
