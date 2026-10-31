import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/data/auth_repository.dart';
import '../models/business.dart';

class BusinessRepository extends ChangeNotifier {
  static final BusinessRepository instance = BusinessRepository._internal();
  BusinessRepository._internal() {
    // Los montos se muestran con el símbolo de la moneda del negocio activo
    activeBusinessNotifier.addListener(() {
      final business = activeBusinessNotifier.value;
      CurrencyFormatter.useCurrency(business?.currency);
      // Acento de la app si el usuario eligió usar el color del negocio
      ThemeController.instance.setBusinessColor(business?.color);
    });
  }

  final AppDatabase _dbProvider = AppDatabase.instance;
  static Business? _activeBusiness;
  /// Usuario para el que se eligió el negocio activo en memoria
  static String? _activeBusinessUserId;
  /// Clave en app_settings (cada cuenta tiene su propio archivo de base de datos)
  static const String _activeBusinessKey = 'active_business_id';

  /// Notificador reactivo del negocio activo actual
  final ValueNotifier<Business?> activeBusinessNotifier = ValueNotifier<Business?>(null);

  /// Negocio activo actual en memoria
  Business? get currentActiveBusiness => _activeBusiness;

  /// Obtiene el negocio activo para un usuario (null si no tiene empresas aún)
  Future<Business?> getActiveBusiness(String userId, [String? userEmail]) async {
    if (_activeBusiness != null && _activeBusinessUserId == userId) {
      if (activeBusinessNotifier.value?.id != _activeBusiness!.id) {
        activeBusinessNotifier.value = _activeBusiness;
      }
      return _activeBusiness!;
    }

    final list = await getAllBusinesses(userId, userEmail);

    // Tras un logout, las pantallas de la sesión anterior siguen montadas un instante y
    // piden su negocio con el userId viejo. No deben dejarlo activo para la siguiente cuenta.
    if (AuthRepository.instance.currentUser?.id != userId) return null;

    // Retomar el último negocio elegido; si ya no está disponible, el primero
    final savedId = await _dbProvider.getSetting(_activeBusinessKey);
    _activeBusiness = list.where((b) => b.id == savedId).firstOrNull ?? list.firstOrNull;
    _activeBusinessUserId = userId;
    activeBusinessNotifier.value = _activeBusiness;
    notifyListeners();
    return _activeBusiness;
  }

  /// Cambia la empresa activa en el contexto de trabajo y notifica inmediatamente a todos los módulos
  void setActiveBusiness(Business? business) {
    _activeBusiness = business;
    _activeBusinessUserId = business == null ? null : AuthRepository.instance.currentUser?.id;
    activeBusinessNotifier.value = business;
    notifyListeners();
    // null llega al cerrar sesión: se conserva la elección para el próximo ingreso
    if (business != null) _rememberActiveBusiness(business.id);
  }

  Future<void> _rememberActiveBusiness(String businessId) async {
    try {
      await _dbProvider.setSetting(_activeBusinessKey, businessId);
    } catch (e) {
      debugPrint('No se pudo guardar el negocio activo: $e');
    }
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
    String country = 'CO',
    String? icon,
    String? color,
  }) async {
    final db = await _dbProvider.database;
    final business = Business(
      id: const Uuid().v4(),
      userId: userId,
      name: name.trim(),
      currency: currency,
      country: country,
      icon: icon,
      color: color,
      createdAt: DateTime.now(),
    );

    await db.insert('businesses', business.toMap());
    _activeBusiness = business;
    _activeBusinessUserId = userId;
    await _rememberActiveBusiness(business.id);
    activeBusinessNotifier.value = business;
    notifyListeners();

    // Sincronizar en tiempo real a Supabase
    SupabaseService.instance.upsertBusinessToCloud(business.toMap());

    // Registrar automáticamente al creador como OWNER en business_members
    try {
      final userQuery = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
      final userEmail = userQuery.isNotEmpty ? (userQuery.first['email'] as String?)?.trim() : null;
      final userName = userQuery.isNotEmpty ? (userQuery.first['name'] as String?)?.trim() : null;

      final ownerMember = {
        'id': const Uuid().v4(),
        'business_id': business.id,
        'user_id': userId,
        'email': userEmail ?? '',
        'name': userName ?? 'Dueño',
        'role': 'OWNER',
        'status': 'ACTIVE',
        'created_at': DateTime.now().toIso8601String(),
      };
      await db.insert('business_members', ownerMember, conflictAlgorithm: ConflictAlgorithm.replace);
      SupabaseService.instance.upsertBusinessMemberToCloud(ownerMember);
    } catch (e) {
      debugPrint('Error registrando creador como OWNER en business_members: $e');
    }

    return business;
  }

  /// Actualiza los datos de una empresa. Los campos opcionales en null no cambian.
  Future<Business?> updateBusiness({
    required String id,
    required String name,
    required String currency,
    String? description,
    String? country,
    String? icon,
    String? color,
    String? logoUrl,
    bool? cashRegisterEnabled,
  }) async {
    final db = await _dbProvider.database;
    final Map<String, dynamic> updateData = {
      'name': name.trim(),
      'currency': currency,
      if (description != null) 'description': description.trim(),
      if (country != null) 'country': country,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (logoUrl != null) 'logo_url': logoUrl,
      if (cashRegisterEnabled != null) 'cash_register_enabled': cashRegisterEnabled ? 1 : 0,
    };

    await db.update(
      'businesses',
      updateData,
      where: 'id = ?',
      whereArgs: [id],
    );

    final rows = await db.query('businesses', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final saved = Business.fromMap(rows.first);

    if (_activeBusiness?.id == id) {
      _activeBusiness = saved;
      activeBusinessNotifier.value = _activeBusiness;
      notifyListeners();
    }

    // Se envía la fila completa: la nube guarda país, ícono, color y demás en cada cambio
    SupabaseService.instance.upsertBusinessToCloud(saved.toMap());
    return saved;
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
      activeBusinessNotifier.value = null;
      notifyListeners();
    }

    // Actualizar estado en Supabase en tiempo real
    await SupabaseService.instance.updateBusinessDeletedStatus(id, true);
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

    // Restaurar estado en Supabase en tiempo real
    await SupabaseService.instance.updateBusinessDeletedStatus(id, false);
  }

  /// Elimina definitivamente una empresa y todos sus datos en SQLite y Supabase
  Future<void> deleteBusinessPermanently(String id) async {
    final db = await _dbProvider.database;

    await db.transaction((txn) async {
      await txn.delete('stock_movements', where: 'business_id = ?', whereArgs: [id]);
      await txn.delete('sales', where: 'business_id = ?', whereArgs: [id]);
      await txn.delete('customers', where: 'business_id = ?', whereArgs: [id]);
      await txn.delete('products', where: 'business_id = ?', whereArgs: [id]);
      await txn.delete('categories', where: 'business_id = ?', whereArgs: [id]);
      await txn.delete('business_members', where: 'business_id = ?', whereArgs: [id]);
      await txn.delete('businesses', where: 'id = ?', whereArgs: [id]);
    });

    if (_activeBusiness?.id == id) {
      _activeBusiness = null;
      activeBusinessNotifier.value = null;
      notifyListeners();
    }

    // Eliminar también en Supabase Cloud
    await SupabaseService.instance.deleteBusinessPermanently(id);
  }

  /// Vacía toda la papelera del usuario eliminando definitivamente todas sus empresas archivadas
  Future<void> emptyTrash(String userId) async {
    final db = await _dbProvider.database;
    final trashed = await db.query(
      'businesses',
      columns: ['id'],
      where: 'user_id = ? AND is_deleted = 1',
      whereArgs: [userId],
    );

    for (final row in trashed) {
      final bizId = row['id'] as String;
      await deleteBusinessPermanently(bizId);
    }
  }
}
