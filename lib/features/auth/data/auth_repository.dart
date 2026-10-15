import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/hash_helper.dart';
import '../models/app_user.dart';

class AuthRepository {
  static final AuthRepository instance = AuthRepository._internal();
  AuthRepository._internal();

  final AppDatabase _dbProvider = AppDatabase.instance;
  static AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  /// Registra un nuevo usuario con correo, contraseña cifrada, nombre y teléfono
  Future<AppUser> register({
    required String email,
    required String password,
    String? name,
    String? phone,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = name?.trim();
    final cleanPhone = phone?.trim();

    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw Exception('Ingresa un correo electrónico válido.');
    }
    if (password.length < 6) {
      throw Exception('La contraseña debe tener al menos 6 caracteres.');
    }

    final db = await _dbProvider.database;

    // 1. Verificar si el correo ya existe localmente
    final existing = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [cleanEmail],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      throw Exception('Ya existe una cuenta con este correo.');
    }

    // 2. Verificar si ya existe en Supabase
    if (!SupabaseService.instance.isInitialized) {
      await SupabaseService.instance.initialize();
    }
    final client = SupabaseService.instance.client;
    if (client != null) {
      try {
        final cloudCheck = await client
            .from('users')
            .select('id')
            .eq('email', cleanEmail)
            .maybeSingle();
        if (cloudCheck != null) {
          throw Exception('Ya existe una cuenta con este correo en la nube. Inicia sesión con tus credenciales.');
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('Ya existe')) rethrow;
        debugPrint('Nota: no se pudo verificar duplicado en Supabase: $e');
      }
    }

    // Hasheo seguro unidireccional con SHA-256 y Salting
    final hashedPassword = HashHelper.hashPassword(password);

    final user = AppUser(
      id: const Uuid().v4(),
      email: cleanEmail,
      name: (cleanName != null && cleanName.isNotEmpty) ? cleanName : null,
      phone: (cleanPhone != null && cleanPhone.isNotEmpty) ? cleanPhone : null,
      createdAt: DateTime.now(),
    );

    final userMap = {
      ...user.toMap(),
      'password': hashedPassword,
    };

    await db.insert('users', userMap);

    _currentUser = user;
    await _dbProvider.setSetting('active_user_id', user.id);

    // Sincronizar usuario a Supabase en tiempo real
    await SupabaseService.instance.upsertUserToCloud(userMap);

    // Descargar datos si este correo ya había sido invitado a algún negocio
    await SupabaseService.instance.syncFromCloud(user.id, user.email);

    // Si había membresías pendientes con este email, vincular su nuevo user_id local y en la nube
    await db.update(
      'business_members',
      {'user_id': user.id},
      where: "LOWER(email) = ? AND (user_id IS NULL OR TRIM(user_id) = '')",
      whereArgs: [cleanEmail],
    );

    if (client != null) {
      try {
        await client
            .from('business_members')
            .update({'user_id': user.id})
            .eq('user_email', cleanEmail);
      } catch (_) {}
    }

    return user;
  }

  /// Inicia sesión verificando credenciales localmente o consultando Supabase Cloud
  Future<AppUser> login(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    final db = await _dbProvider.database;

    // 1. Intentar autenticación con base de datos local SQLite
    final maps = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [cleanEmail],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      final userRow = maps.first;
      final storedPassword = userRow['password'] as String;

      if (HashHelper.verifyPassword(password, storedPassword)) {
        // Auto-migración si el usuario tenía contraseña previa en texto plano
        final secureHash = HashHelper.hashPassword(password);
        if (storedPassword != secureHash) {
          await db.update(
            'users',
            {'password': secureHash},
            where: 'id = ?',
            whereArgs: [userRow['id']],
          );
        }

        final user = AppUser.fromMap(userRow);
        _currentUser = user;
        await _dbProvider.setSetting('active_user_id', user.id);

        // Descargar datos actualizados de la nube
        await SupabaseService.instance.syncFromCloud(user.id, user.email);

        // Vincular membresías locales si correspondía
        await db.update(
          'business_members',
          {'user_id': user.id},
          where: "LOWER(email) = ? AND (user_id IS NULL OR TRIM(user_id) = '')",
          whereArgs: [cleanEmail],
        );

        return user;
      }
    }

    // 2. Si no se encontró en SQLite o la contraseña local no coincidió,
    // validar directamente contra Supabase Cloud
    if (!SupabaseService.instance.isInitialized) {
      await SupabaseService.instance.initialize();
    }

    final client = SupabaseService.instance.client;
    if (client != null) {
      try {
        final cloudUser = await client
            .from('users')
            .select()
            .eq('email', cleanEmail)
            .maybeSingle();

        if (cloudUser != null) {
          final storedCloudPassword = cloudUser['password'] as String?;
          final isMatch = storedCloudPassword != null &&
              (HashHelper.verifyPassword(password, storedCloudPassword) ||
               storedCloudPassword == password ||
               storedCloudPassword == HashHelper.hashPassword(password));

          if (isMatch) {
            final user = AppUser(
              id: cloudUser['id'] as String,
              email: cloudUser['email'] as String,
              name: cloudUser['name'] as String?,
              phone: cloudUser['phone'] as String?,
              avatarPath: cloudUser['avatar_path'] as String?,
              createdAt: cloudUser['created_at'] != null
                  ? DateTime.tryParse(cloudUser['created_at']) ?? DateTime.now()
                  : DateTime.now(),
            );

            final secureHash = HashHelper.hashPassword(password);
            final userMap = {
              ...user.toMap(),
              'password': secureHash,
            };

            // Guardar usuario en SQLite local para futuros inicios de sesión offline
            await db.insert(
              'users',
              userMap,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

            _currentUser = user;
            await _dbProvider.setSetting('active_user_id', user.id);

            // Descargar todas las empresas, productos, categorías y datos asociados desde la nube
            await SupabaseService.instance.syncFromCloud(user.id, user.email);

            // Vincular membresías locales si correspondía
            await db.update(
              'business_members',
              {'user_id': user.id},
              where: "LOWER(email) = ? AND (user_id IS NULL OR TRIM(user_id) = '')",
              whereArgs: [cleanEmail],
            );

            return user;
          }
        }
      } catch (e) {
        debugPrint('Error al verificar usuario en Supabase: $e');
      }
    }

    throw Exception('Correo o contraseña incorrectos.');
  }

  /// Restaura la sesión guardada si existe
  Future<AppUser?> restoreSession() async {
    if (_currentUser != null) return _currentUser;
    final activeId = await _dbProvider.getSetting('active_user_id');
    if (activeId != null) {
      return await reloadUser(activeId);
    }
    return null;
  }

  /// Cierra la sesión activa
  Future<void> logout() async {
    _currentUser = null;
    await _dbProvider.setSetting('active_user_id', null);
  }

  /// Actualiza los datos del perfil del usuario (nombre, teléfono, foto)
  Future<AppUser> updateProfile({
    required String userId,
    String? name,
    String? phone,
    String? avatarPath,
  }) async {
    final db = await _dbProvider.database;
    final Map<String, dynamic> values = {};
    if (name != null) values['name'] = name.trim();
    if (phone != null) values['phone'] = phone.trim();
    if (avatarPath != null) values['avatar_path'] = avatarPath;

    if (values.isNotEmpty) {
      await db.update(
        'users',
        values,
        where: 'id = ?',
        whereArgs: [userId],
      );
    }

    if (_currentUser != null && _currentUser!.id == userId) {
      _currentUser = _currentUser!.copyWith(
        name: name?.trim() ?? _currentUser!.name,
        phone: phone?.trim() ?? _currentUser!.phone,
        avatarPath: avatarPath ?? _currentUser!.avatarPath,
      );
    }

    // Sincronizar perfil actualizado a Supabase en tiempo real
    final updatedUserMap = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (updatedUserMap.isNotEmpty) {
      SupabaseService.instance.upsertUserToCloud(updatedUserMap.first);
    }

    return _currentUser!;
  }

  /// Cambia la contraseña de acceso verificando la contraseña actual
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final db = await _dbProvider.database;
    final check = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (check.isEmpty) {
      throw Exception('Usuario no encontrado.');
    }

    final storedPassword = check.first['password'] as String;
    if (!HashHelper.verifyPassword(currentPassword, storedPassword)) {
      throw Exception('La contraseña actual es incorrecta.');
    }

    if (newPassword.length < 6) {
      throw Exception('La nueva contraseña debe tener al menos 6 caracteres.');
    }

    final newHashedPassword = HashHelper.hashPassword(newPassword);

    await db.update(
      'users',
      {'password': newHashedPassword},
      where: 'id = ?',
      whereArgs: [userId],
    );

    // Sincronizar contraseña actualizada a Supabase
    final updatedUserMap = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (updatedUserMap.isNotEmpty) {
      SupabaseService.instance.upsertUserToCloud(updatedUserMap.first);
    }
  }

  /// Recarga el usuario desde la base de datos
  Future<AppUser?> reloadUser(String userId) async {
    final db = await _dbProvider.database;
    final maps = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (maps.isNotEmpty) {
      _currentUser = AppUser.fromMap(maps.first);
      return _currentUser;
    }
    return null;
  }

  /// Verifica si la contraseña proporcionada coincide con la del usuario en sesión
  Future<bool> verifyCurrentPassword(String password) async {
    final user = _currentUser;
    if (user == null) return false;
    final db = await _dbProvider.database;
    final maps = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [user.id],
      limit: 1,
    );
    if (maps.isEmpty) return false;
    final storedPassword = maps.first['password'] as String;
    return HashHelper.verifyPassword(password, storedPassword);
  }
}
