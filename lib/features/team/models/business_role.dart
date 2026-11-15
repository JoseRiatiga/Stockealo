import 'dart:convert';

import '../../../core/permissions/permissions.dart';

/// Un rol del negocio (0.15.0, etapa 2 de `docs/plan-roles.md`):
/// - el ajuste de un rol por defecto ([builtin] = 'ADMIN' o 'CASHIER'), por ejemplo un
///   Cajero que también ve costos;
/// - o un rol propio ([builtin] = null), por ejemplo «Vendedor».
class BusinessRole {
  final String id;
  final String businessId;
  final String name;

  /// El rol que usa la nube para dejarlo trabajar: 'ADMIN' o 'CASHIER'
  final String baseRole;

  /// 'ADMIN' o 'CASHIER' si es el ajuste de un rol por defecto; null si es propio
  final String? builtin;
  final Set<Perm> perms;

  /// Límites con números (Pro); sin la clave = sin límite
  final Map<RoleLimit, double> limits;

  /// Plantilla de la que salió (vendedor, bodega…), solo como referencia
  final String? templateId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BusinessRole({
    required this.id,
    required this.businessId,
    required this.name,
    required this.baseRole,
    this.builtin,
    required this.perms,
    this.limits = const {},
    this.templateId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isBuiltin => builtin != null;

  /// El rol como lo lee [Permissions.can]: 'ADMIN', 'CASHIER' o 'ROLE:<id>'
  String get roleKey => builtin ?? Permissions.customRole(id);

  /// Id fijo del ajuste de un rol por defecto: uno por negocio
  static String builtinId(String businessId, String code) => '$businessId-$code';

  BusinessRole copyWith({String? name, Set<Perm>? perms, Map<RoleLimit, double>? limits, String? baseRole, DateTime? updatedAt}) =>
      BusinessRole(
        id: id,
        businessId: businessId,
        name: name ?? this.name,
        baseRole: baseRole ?? this.baseRole,
        builtin: builtin,
        perms: perms ?? this.perms,
        limits: limits ?? this.limits,
        templateId: templateId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  static Set<Perm> _permsOf(Object? raw) {
    final list = raw is String ? (raw.trim().isEmpty ? const [] : jsonDecode(raw) as List) : (raw as List? ?? const []);
    return {for (final k in list) Perm.byName('$k')}.whereType<Perm>().toSet();
  }

  static Map<RoleLimit, double> _limitsOf(Object? raw) {
    final map = raw is String ? (raw.trim().isEmpty ? const {} : jsonDecode(raw) as Map) : (raw as Map? ?? const {});
    return {
      for (final e in map.entries)
        if (RoleLimit.byName('${e.key}') != null && e.value is num && (e.value as num) >= 0)
          RoleLimit.byName('${e.key}')!: (e.value as num).toDouble(),
    };
  }

  static Map<String, double> _limitNames(Map<RoleLimit, double> limits) => {for (final e in limits.entries) e.key.name: e.value};

  static List<String> _names(Set<Perm> perms) => [for (final p in Perm.values) if (perms.contains(p)) p.name];

  /// Fila de la base local (los permisos como texto JSON)
  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'name': name,
        'base_role': baseRole,
        'builtin': builtin,
        'perms': jsonEncode(_names(perms)),
        'limits': jsonEncode(_limitNames(limits)),
        'template_id': templateId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// Fila para Supabase (los permisos como lista)
  Map<String, dynamic> cloudRow() => {...toMap(), 'perms': _names(perms), 'limits': _limitNames(limits)};

  factory BusinessRole.fromMap(Map<String, dynamic> m) {
    final builtin = m['builtin'] as String?;
    return BusinessRole(
      id: m['id'] as String,
      businessId: m['business_id'] as String,
      name: (m['name'] as String?)?.trim().isNotEmpty == true ? (m['name'] as String).trim() : 'Rol',
      baseRole: (m['base_role'] as String?) == Permissions.admin ? Permissions.admin : Permissions.cashier,
      builtin: builtin == Permissions.admin || builtin == Permissions.cashier ? builtin : null,
      perms: _permsOf(m['perms']),
      limits: _limitsOf(m['limits']),
      templateId: m['template_id'] as String?,
      createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${m['updated_at']}') ?? DateTime.now(),
    );
  }
}
