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

    // Verificar si el correo ya existe
    final existing = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [cleanEmail],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      throw Exception('Ya existe una cuenta con este correo.');
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
    SupabaseService.instance.upsertUserToCloud(userMap);

    return user;
  }

  /// Inicia sesión verificando el hash de la contraseña
  Future<AppUser> login(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    final db = await _dbProvider.database;

    final maps = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [cleanEmail],
      limit: 1,
    );

    if (maps.isEmpty) {
      throw Exception('Correo o contraseña incorrectos.');
    }

    final userRow = maps.first;
    final storedPassword = userRow['password'] as String;

    if (!HashHelper.verifyPassword(password, storedPassword)) {
      throw Exception('Correo o contraseña incorrectos.');
    }

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
    return user;
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
}
