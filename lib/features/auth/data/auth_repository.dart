import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/app_database.dart';
import '../../stocky/data/stocky_assistant_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/countries.dart';
import '../models/app_user.dart';

/// Autenticación sobre Supabase Auth.
///
/// Las contraseñas solo existen en Supabase Auth: ni el dispositivo ni la tabla
/// `users` guardan hashes. La fila de `users` conserva el perfil y el `id` de la
/// app, que para cuentas antiguas difiere del `id` de Supabase Auth; el vínculo
/// entre ambos es el correo verificado.
/// La sesión del código verificado ya no existe (venció o se cerró): hay que
/// pedir un código nuevo.
class PasswordResetExpiredException implements Exception {
  const PasswordResetExpiredException();

  @override
  String toString() => 'Exception: La verificación venció. Pide un código nuevo para continuar.';
}

class AuthRepository {
  static final AuthRepository instance = AuthRepository._internal();
  AuthRepository._internal();

  final AppDatabase _dbProvider = AppDatabase.instance;
  static AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;

  /// Fija la sesión sin pasar por Supabase (solo pruebas)
  @visibleForTesting
  static set debugCurrentUser(AppUser? user) => _currentUser = user;
  bool get isAuthenticated => _currentUser != null;

  /// Paso 1 del registro: envía un código de 6 dígitos al correo
  Future<void> requestRegistrationCode(String email) async {
    final cleanEmail = _validateEmail(email);
    final auth = await _requireAuth();
    try {
      await auth.signInWithOtp(email: cleanEmail, shouldCreateUser: true);
    } catch (e) {
      throw Exception(_translateAuthError(e));
    }
  }

  /// Paso 2 del registro: verifica el código, fija la contraseña y crea el perfil
  Future<AppUser> completeRegistration({
    required String email,
    required String code,
    required String password,
    String? name,
    String? phone,
  }) async {
    final cleanEmail = _validateEmail(email);
    _validatePassword(password);
    final auth = await _requireAuth();

    try {
      await auth.verifyOTP(email: cleanEmail, token: code.trim(), type: OtpType.email);
      await auth.updateUser(UserAttributes(password: password));
    } catch (e) {
      throw Exception(_translateAuthError(e));
    }

    await _dbProvider.useAccount(auth.currentUser!.id, cleanEmail);
    final cleanName = name?.trim();
    // Sin prefijo, el número es del país configurado en el teléfono
    final cleanPhone = PhoneNumbers.toE164(phone, country: deviceCountry()) ?? phone?.trim();
    final user = await _resolveAppUser(
      auth.currentUser!,
      name: (cleanName != null && cleanName.isNotEmpty) ? cleanName : null,
      phone: (cleanPhone != null && cleanPhone.isNotEmpty) ? cleanPhone : null,
    );

    // Si este correo había sido invitado a algún negocio, vincular su user_id en la nube
    try {
      await SupabaseService.instance.client?.rpc('link_my_memberships');
    } catch (e) {
      debugPrint('No se pudieron vincular invitaciones pendientes: $e');
    }

    await _finishLogin(user);
    return user;
  }

  /// Inicia sesión con Supabase Auth. Las cuentas creadas antes de la migración
  /// se trasladan a Supabase Auth en el primer inicio de sesión.
  Future<AppUser> login(String email, String password) async {
    final cleanEmail = _validateEmail(email);
    final auth = await _requireAuth();

    try {
      await auth.signInWithPassword(email: cleanEmail, password: password);
    } on AuthException catch (e) {
      if (!_isInvalidCredentials(e)) throw Exception(_translateAuthError(e));

      final migrated = await _migrateLegacyAccount(cleanEmail, password);
      if (!migrated) throw Exception('Correo o contraseña incorrectos.');
      try {
        await auth.signInWithPassword(email: cleanEmail, password: password);
      } catch (e) {
        throw Exception(_translateAuthError(e));
      }
    } catch (e) {
      throw Exception(_translateAuthError(e));
    }

    await _dbProvider.useAccount(auth.currentUser!.id, cleanEmail);
    final user = await _resolveAppUser(auth.currentUser!);
    await _finishLogin(user);
    return user;
  }

  /// Restaura la sesión guardada por Supabase (funciona sin conexión)
  Future<AppUser?> restoreSession() async {
    if (_currentUser != null) return _currentUser;

    // main() inicializa Supabase antes de runApp; sin cliente no hay sesión que restaurar
    final authUser = SupabaseService.instance.client?.auth.currentUser;
    final email = authUser?.email?.toLowerCase();
    if (authUser == null || email == null) return null;

    await _dbProvider.useAccount(authUser.id, email);
    final db = await _dbProvider.database;
    final maps = await db.query('users', where: 'LOWER(email) = ?', whereArgs: [email], limit: 1);
    if (maps.isNotEmpty) {
      _currentUser = AppUser.fromMap(maps.first);
      await _dbProvider.setSetting('active_user_id', _currentUser!.id);
      return _currentUser;
    }

    // Sesión válida pero el perfil no está en este dispositivo: traerlo de la nube
    try {
      final user = await _resolveAppUser(authUser);
      await _finishLogin(user);
      return user;
    } catch (e) {
      debugPrint('No se pudo restaurar el perfil desde la nube: $e');
      return null;
    }
  }

  /// Cierra la sesión activa
  Future<void> logout() async {
    _currentUser = null;
    await _dbProvider.setSetting('active_user_id', null);
    StockyAssistantService.instance.clearAllConversations();
    try {
      await SupabaseService.instance.client?.auth.signOut();
    } catch (e) {
      debugPrint('Error al cerrar sesión en Supabase: $e');
    }
    await _dbProvider.useAccount(null);
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
    if (phone != null) values['phone'] = PhoneNumbers.toE164(phone, country: deviceCountry()) ?? phone.trim();
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
        phone: values['phone'] as String? ?? _currentUser!.phone,
        avatarPath: avatarPath ?? _currentUser!.avatarPath,
      );
    }

    // Actualizar nombre en todas las membresías de equipo asociadas a este usuario
    if (name != null && name.trim().isNotEmpty) {
      final cleanName = name.trim();
      final userEmail = _currentUser?.email.toLowerCase() ?? '';
      await db.update(
        'business_members',
        {'name': cleanName},
        where: 'user_id = ? OR LOWER(email) = ?',
        whereArgs: [userId, userEmail],
      );

      final client = SupabaseService.instance.client;
      if (client != null && userEmail.isNotEmpty) {
        try {
          await client.rpc('link_my_memberships', params: {'p_name': cleanName});
        } catch (e) {
          debugPrint('No se pudo actualizar el nombre en las membresías: $e');
        }
      }
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
    _validatePassword(newPassword, label: 'La nueva contraseña');
    if (!await verifyCurrentPassword(currentPassword)) {
      throw Exception('La contraseña actual es incorrecta.');
    }

    final auth = await _requireAuth();
    try {
      await auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      throw Exception(_translateAuthError(e));
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

  /// Verifica si la contraseña proporcionada coincide con la del usuario en sesión.
  /// Requiere conexión: la contraseña solo la conoce Supabase Auth.
  Future<bool> verifyCurrentPassword(String password) async {
    final user = _currentUser;
    if (user == null) return false;
    final auth = await _requireAuth();
    try {
      await auth.signInWithPassword(email: user.email, password: password);
      return true;
    } on AuthException catch (e) {
      if (_isInvalidCredentials(e)) return false;
      throw Exception(_translateAuthError(e));
    } catch (e) {
      throw Exception(_translateAuthError(e));
    }
  }

  /// Solicita el código OTP de 6 dígitos para restablecer contraseña.
  /// No revela si el correo tiene cuenta ni crea cuentas nuevas: a un correo sin
  /// cuenta simplemente no le llega el código.
  Future<void> requestPasswordResetOtp(String email) async {
    final cleanEmail = _validateEmail(email);
    final auth = await _requireAuth();

    // Las cuentas anteriores a la Fase 1 pueden no tener usuario de Auth todavía;
    // el servidor lo crea solo si el correo ya tiene perfil en Stockealo.
    try {
      await SupabaseService.instance.client!.functions.invoke(
        'prepare-password-reset',
        body: {'email': cleanEmail},
      );
    } catch (e) {
      debugPrint('No se pudo preparar la recuperación: $e');
    }

    try {
      await auth.signInWithOtp(email: cleanEmail, shouldCreateUser: false);
    } catch (e) {
      if (isUnknownAccountError(e)) return;
      throw Exception(_translateAuthError(e));
    }
  }

  /// Error de Supabase al pedir un código para un correo sin cuenta (con shouldCreateUser: false)
  @visibleForTesting
  static bool isUnknownAccountError(Object e) {
    if (e is! AuthException) return false;
    final msg = '${e.code} ${e.message}'.toLowerCase();
    return msg.contains('otp_disabled') ||
        msg.contains('user_not_found') ||
        msg.contains('signups not allowed for otp');
  }

  // ---------------------------------------------------------------------------
  // Recuperación de contraseña en dos pasos
  //
  // 1. verifyPasswordResetCode: el código se verifica (y se consume) una sola vez;
  //    deja una sesión temporal que prueba que el correo es del usuario.
  // 2. setNewPassword: con esa sesión se puede intentar guardar la contraseña las
  //    veces que haga falta, sin pedir otro código.
  // finishPasswordReset / cancelPasswordReset cierran esa sesión temporal.
  // ---------------------------------------------------------------------------

  /// Paso 2: verifica el código. Lanza un error legible si es incorrecto o venció.
  Future<void> verifyPasswordResetCode({required String email, required String code}) async {
    final cleanEmail = _validateEmail(email);
    final auth = await _requireAuth();
    try {
      await auth.verifyOTP(email: cleanEmail, token: code.trim(), type: OtpType.email);
    } catch (e) {
      throw Exception(_translateAuthError(e));
    }

    // El código prueba que el correo es suyo; aun así solo se restablecen cuentas existentes
    final profile = await _fetchCloudProfile(cleanEmail);
    if (profile == null) {
      await _signOutQuietly(auth);
      throw Exception('No encontramos ninguna cuenta registrada con este correo en Stockealo.');
    }
  }

  /// Paso 3: guarda la nueva contraseña con la sesión del código verificado.
  /// Devuelve false si es la misma que ya tenía (la sesión sigue abierta para que
  /// el usuario elija otra o decida quedarse con la actual).
  Future<bool> setNewPassword({required String email, required String newPassword}) async {
    final cleanEmail = _validateEmail(email);
    _validatePassword(newPassword, label: 'La nueva contraseña');
    final auth = await _requireAuth();
    if (auth.currentUser?.email?.toLowerCase() != cleanEmail) {
      throw const PasswordResetExpiredException();
    }

    try {
      await auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      if (_isSamePassword(e)) return false;
      if (_isSessionGone(e)) throw const PasswordResetExpiredException();
      throw Exception(_translateAuthError(e));
    } catch (e) {
      throw Exception(_translateAuthError(e));
    }

    await finishPasswordReset(cleanEmail);
    return true;
  }

  /// Termina la recuperación: retira el hash antiguo si quedaba y cierra la sesión
  /// temporal para que el usuario ingrese con su contraseña.
  Future<void> finishPasswordReset(String email) async {
    try {
      await SupabaseService.instance.client
          ?.from('users')
          .update({'password': authManagedPassword})
          .eq('email', email.trim().toLowerCase());
    } catch (e) {
      debugPrint('No se pudo retirar el hash antiguo: $e');
    }
    await cancelPasswordReset();
  }

  /// Cierra la sesión que abre la verificación del código si el usuario abandona
  /// la recuperación de contraseña sin terminarla (no afecta a una sesión normal).
  Future<void> cancelPasswordReset() async {
    if (_currentUser != null) return;
    final auth = SupabaseService.instance.client?.auth;
    if (auth?.currentSession != null) await _signOutQuietly(auth!);
  }

  static bool _isSamePassword(AuthException e) =>
      '${e.code} ${e.message}'.toLowerCase().contains('same_password');

  static bool _isSessionGone(AuthException e) {
    final msg = '${e.code} ${e.message}'.toLowerCase();
    return msg.contains('session_not_found') || msg.contains('session_expired') || msg.contains('jwt expired');
  }

  // ---------------------------------------------------------------------------
  // Internos
  // ---------------------------------------------------------------------------

  Future<GoTrueClient> _requireAuth() async {
    if (!SupabaseService.instance.isInitialized) {
      await SupabaseService.instance.initialize();
    }
    final client = SupabaseService.instance.client;
    if (client == null) {
      throw Exception('No hay conexión con el servidor. Verifica tu internet e inténtalo de nuevo.');
    }
    return client.auth;
  }

  /// Traslada a Supabase Auth una cuenta creada antes de la migración.
  /// La Edge Function `legacy-login` valida el hash antiguo en el servidor.
  Future<bool> _migrateLegacyAccount(String email, String password) async {
    final client = SupabaseService.instance.client;
    if (client == null) return false;
    try {
      final response = await client.functions.invoke(
        'legacy-login',
        body: {'email': email, 'password': password},
      );
      final data = response.data;
      return data is Map && data['migrated'] == true;
    } catch (e) {
      debugPrint('Migración de cuenta antigua no disponible: $e');
      return false;
    }
  }

  /// Busca el perfil de la app para el correo verificado, creándolo si no existe
  Future<AppUser> _resolveAppUser(User authUser, {String? name, String? phone}) async {
    final email = authUser.email!.toLowerCase();
    final profile = await _fetchCloudProfile(email);

    if (profile != null) {
      return AppUser(
        id: profile['id'] as String,
        email: profile['email'] as String,
        name: profile['name'] as String? ?? name,
        phone: profile['phone'] as String? ?? phone,
        avatarPath: profile['avatar_path'] as String?,
        createdAt: DateTime.tryParse(profile['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
    }

    final user = AppUser(
      id: authUser.id,
      email: email,
      name: name ?? authUser.userMetadata?['name'] as String?,
      phone: phone,
      createdAt: DateTime.now(),
    );
    final client = SupabaseService.instance.client!;
    await client.from('users').insert({
      ...user.toMap(),
      'password': authManagedPassword,
    });
    return user;
  }

  Future<Map<String, dynamic>?> _fetchCloudProfile(String email) async {
    final client = SupabaseService.instance.client;
    if (client == null) return null;
    return await client
        .from('users')
        .select('id, email, name, phone, avatar_path, created_at')
        .eq('email', email)
        .maybeSingle();
  }

  /// Guarda el perfil en el dispositivo, abre la sesión y descarga los datos
  Future<void> _finishLogin(AppUser user) async {
    final db = await _dbProvider.database;
    await db.insert(
      'users',
      {...user.toMap(), 'password': authManagedPassword},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    _currentUser = user;
    await _dbProvider.setSetting('active_user_id', user.id);

    // Descargar empresas, productos, categorías y datos asociados desde la nube
    await SupabaseService.instance.syncFromCloud(user.id, user.email);

    // Vincular membresías locales si correspondía
    await db.update(
      'business_members',
      {'user_id': user.id},
      where: "LOWER(email) = ? AND (user_id IS NULL OR TRIM(user_id) = '')",
      whereArgs: [user.email.toLowerCase()],
    );
  }

  Future<void> _signOutQuietly(GoTrueClient auth) async {
    try {
      await auth.signOut();
    } catch (_) {}
  }

  String _validateEmail(String email) {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw Exception('Ingresa un correo electrónico válido.');
    }
    return cleanEmail;
  }

  void _validatePassword(String password, {String label = 'La contraseña'}) {
    if (password.length < 6) {
      throw Exception('$label debe tener al menos 6 caracteres.');
    }
  }

  bool _isInvalidCredentials(AuthException e) =>
      e.code == 'invalid_credentials' || e.message.toLowerCase().contains('invalid login credentials');

  String _translateAuthError(Object e) => translateAuthError(e);

  /// Convierte errores de Supabase Auth y de red en mensajes para el usuario
  @visibleForTesting
  static String translateAuthError(Object e) {
    if (e is Exception && e is! AuthException && e.toString().startsWith('Exception: ')) {
      return e.toString().replaceFirst('Exception: ', '');
    }
    final msg = (e is AuthException ? '${e.code} ${e.message}' : e.toString()).toLowerCase();
    if (msg.contains('email_not_confirmed') || msg.contains('email not confirmed')) {
      return 'Debes confirmar tu correo antes de ingresar.';
    }
    if (msg.contains('otp_expired') || msg.contains('token has expired') || msg.contains('invalid token')) {
      return 'El código ingresado es incorrecto o ya expiró.';
    }
    if (msg.contains('over_email_send_rate_limit') || msg.contains('for security purposes')) {
      return 'Por seguridad, espera unos segundos antes de solicitar un nuevo código.';
    }
    if (msg.contains('weak_password')) {
      return 'La contraseña es demasiado débil. Usa una más larga o menos común.';
    }
    if (msg.contains('same_password')) {
      return 'La nueva contraseña debe ser diferente a la actual.';
    }
    if (msg.contains('invalid_credentials') || msg.contains('invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (msg.contains('socketexception') || msg.contains('failed host lookup') ||
        msg.contains('clientexception') || msg.contains('network')) {
      return 'Necesitas conexión a internet. Verifica tu red e inténtalo de nuevo.';
    }
    debugPrint('Error de autenticación sin traducir: $e');
    return 'No se pudo completar la operación. Inténtalo de nuevo.';
  }
}
