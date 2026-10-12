class BusinessMember {
  final String id;
  final String businessId;
  final String? userId;
  final String email;
  final String role; // 'OWNER' | 'ADMIN' | 'CASHIER'
  final String status; // 'ACTIVE' | 'PENDING'
  final DateTime createdAt;

  BusinessMember({
    required this.id,
    required this.businessId,
    this.userId,
    required this.email,
    required this.role,
    this.status = 'ACTIVE',
    required this.createdAt,
  });

  bool get isOwner => role == 'OWNER';
  bool get isAdmin => role == 'ADMIN';
  bool get isCashier => role == 'CASHIER';

  // Permisos derivados para control de acceso y seguridad
  bool get canViewCosts => role == 'OWNER' || role == 'ADMIN';
  bool get canEditProducts => role == 'OWNER' || role == 'ADMIN';
  bool get canManageTeam => role == 'OWNER';
  bool get canAdjustStockDirectly => role == 'OWNER' || role == 'ADMIN';

  String get roleDisplayName {
    switch (role) {
      case 'OWNER':
        return 'Dueño';
      case 'ADMIN':
        return 'Administrador';
      case 'CASHIER':
        return 'Cajero / Vendedor';
      default:
        return role;
    }
  }

  String get roleDescription {
    switch (role) {
      case 'OWNER':
        return 'Control total de la empresa y gestión del equipo.';
      case 'ADMIN':
        return 'Puede gestionar productos, inventario y ventas. Puede ver costos.';
      case 'CASHIER':
        return 'Solo registra ventas. Precios de compra y costos protegidos.';
      default:
        return '';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'user_id': userId,
      'email': email,
      'role': role,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory BusinessMember.fromMap(Map<String, dynamic> map) {
    return BusinessMember(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      userId: map['user_id'] as String?,
      email: map['email'] as String,
      role: map['role'] as String,
      status: map['status'] as String? ?? 'ACTIVE',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
