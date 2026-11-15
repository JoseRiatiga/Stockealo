import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/services/supabase_service.dart';
import '../models/business_member.dart';
import '../models/business_role.dart';
import 'activity_repository.dart';

/// Roles del negocio (0.15.0, etapa 2 de `docs/plan-roles.md`): los ajustes del
/// Administrador y del Cajero, y los roles propios. Solo el dueño los cambia.
class RolesRepository {
  static final RolesRepository instance = RolesRepository._();
  RolesRepository._();

  /// Roles propios en el plan gratis (con Pro, sin límite)
  static const freeCustomLimit = 1;

  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<BusinessRole>> list(String businessId) async {
    final rows = await (await _db).query('business_roles', where: 'business_id = ?', whereArgs: [businessId], orderBy: 'created_at');
    return [for (final r in rows) BusinessRole.fromMap(r)];
  }

  /// Carga los roles del negocio en [Permissions] (al abrir el negocio y al guardar)
  Future<void> apply(String businessId) async {
    final roles = await list(businessId);
    Permissions.applyBusiness(
      builtins: {for (final r in roles) if (r.isBuiltin) r.builtin!: r.perms},
      custom: {for (final r in roles) if (!r.isBuiltin) r.id: (name: r.name, perms: r.perms)},
    );
  }

  /// Rol propio nuevo, desde una plantilla o desde cero
  BusinessRole newCustom(String businessId, {required String name, required Set<Perm> perms, String? templateId}) {
    final now = DateTime.now();
    final all = Permissions.withDependencies(perms);
    return BusinessRole(
      id: const Uuid().v4(),
      businessId: businessId,
      name: name.trim(),
      baseRole: Permissions.baseFor(all),
      perms: all,
      templateId: templateId,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// El ajuste de un rol por defecto ('ADMIN' o 'CASHIER') con estos permisos
  BusinessRole builtinWith(String businessId, String code, Set<Perm> perms) {
    final now = DateTime.now();
    return BusinessRole(
      id: BusinessRole.builtinId(businessId, code),
      businessId: businessId,
      name: Permissions.labelOf(code),
      baseRole: code,
      builtin: code,
      perms: perms,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Guarda un rol (nuevo o cambiado). [summary] queda en Actividad del equipo.
  Future<void> save(BusinessRole role, {String? summary}) async {
    final fixed = role.isBuiltin
        ? role.copyWith(updatedAt: DateTime.now())
        : role.copyWith(baseRole: Permissions.baseFor(role.perms), updatedAt: DateTime.now());
    await (await _db).insert('business_roles', fixed.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    SupabaseService.instance.upsertBusinessRoleToCloud(fixed.cloudRow());
    // Las personas con este rol propio se apoyan en el rol de la nube que le toca
    if (!fixed.isBuiltin) {
      final db = await _db;
      final members = await db.query('business_members', where: 'role_id = ?', whereArgs: [fixed.id]);
      for (final m in members) {
        if (m['role'] != fixed.baseRole) {
          await db.update('business_members', {'role': fixed.baseRole}, where: 'id = ?', whereArgs: [m['id']]);
          SupabaseService.instance.upsertBusinessMemberToCloud({...m, 'role': fixed.baseRole});
        }
      }
    }
    if (summary != null) {
      ActivityRepository.instance.log(
        businessId: fixed.businessId,
        action: ActivityAction.roleChange,
        summary: summary,
        data: {'role_id': fixed.id},
      );
    }
    await apply(fixed.businessId);
  }

  /// Borra un rol propio: quienes lo tenían vuelven a su rol de la nube (Administrador
  /// o Cajero), nunca se quedan sin entrar
  Future<void> delete(BusinessRole role) async {
    if (role.isBuiltin) return;
    final db = await _db;
    final members = await db.query('business_members', where: 'role_id = ?', whereArgs: [role.id]);
    for (final m in members) {
      await db.update('business_members', {'role_id': null}, where: 'id = ?', whereArgs: [m['id']]);
      SupabaseService.instance.upsertBusinessMemberToCloud({...m, 'role_id': null});
    }
    await db.delete('business_roles', where: 'id = ?', whereArgs: [role.id]);
    SupabaseService.instance.deleteBusinessRoleFromCloud(role.id);
    ActivityRepository.instance.log(
      businessId: role.businessId,
      action: ActivityAction.roleChange,
      summary: 'Borró el rol ${role.name}${members.isEmpty ? '' : ' (${members.length} ${members.length == 1 ? 'persona volvió' : 'personas volvieron'} a su rol anterior)'}',
      data: {'role_id': role.id},
    );
    await apply(role.businessId);
  }

  /// Le da a una persona un rol por defecto ([code] = 'ADMIN' o 'CASHIER') o uno propio
  Future<void> assign(BusinessMember member, {String? code, BusinessRole? role}) async {
    assert(code != null || role != null);
    final base = role?.baseRole ?? code!;
    final db = await _db;
    await db.update('business_members', {'role': base, 'role_id': role?.id}, where: 'id = ?', whereArgs: [member.id]);
    final rows = await db.query('business_members', where: 'id = ?', whereArgs: [member.id], limit: 1);
    if (rows.isNotEmpty) SupabaseService.instance.upsertBusinessMemberToCloud(rows.first);
    ActivityRepository.instance.log(
      businessId: member.businessId,
      action: ActivityAction.roleChange,
      summary: 'Cambió el rol de ${member.displayName}: ${member.roleDisplayName} → ${role?.name ?? Permissions.labelOf(code)}',
      data: {'member_id': member.id},
    );
  }

  /// Texto para Actividad: qué permisos se encendieron y cuáles se apagaron
  static String changeSummary(String roleName, Set<Perm> before, Set<Perm> after) {
    final on = [for (final p in Perm.values) if (after.contains(p) && !before.contains(p)) p.label];
    final off = [for (final p in Perm.values) if (before.contains(p) && !after.contains(p)) p.label];
    return 'Cambió los permisos de $roleName: '
        '${[if (on.isNotEmpty) '+${on.join(', +')}', if (off.isNotEmpty) '−${off.join(', −')}'].join('; ')}';
  }
}
