class Business {
  final String id;
  final String userId;
  final String name;
  final String currency;

  /// Código ISO del país (prefijo telefónico, medios de pago, consejos de Stocky)
  final String country;

  /// Ícono elegido al crear el negocio (clave de BusinessIcons) y color "#RRGGBB"
  final String? icon;
  final String? color;

  /// Logo propio en Supabase Storage (opcional)
  final String? logoUrl;

  /// Arqueo de caja activado (opcional; apagado por defecto)
  final bool cashRegisterEnabled;
  final String? description;
  final DateTime createdAt;
  final bool isSynced;
  final bool isDeleted;
  final DateTime? deletedAt;

  Business({
    required this.id,
    required this.userId,
    required this.name,
    this.currency = 'COP',
    this.country = 'CO',
    this.icon,
    this.color,
    this.logoUrl,
    this.cashRegisterEnabled = false,
    this.description,
    required this.createdAt,
    this.isSynced = false,
    this.isDeleted = false,
    this.deletedAt,
  });

  /// Días restantes en la papelera antes de la eliminación definitiva (máximo 7 días)
  int get daysRemainingInTrash {
    if (deletedAt == null) return 7;
    final diff = DateTime.now().difference(deletedAt!);
    final remaining = 7 - diff.inDays;
    return remaining < 0 ? 0 : remaining;
  }

  /// Código de invitación corto de 8 caracteres para vincular colaboradores (ej. '6CC1-4831')
  String get inviteCode {
    final clean = id.replaceAll('-', '').toUpperCase();
    if (clean.length >= 8) {
      return '${clean.substring(0, 4)}-${clean.substring(4, 8)}';
    }
    return clean;
  }

  Business copyWith({
    String? id,
    String? userId,
    String? name,
    String? currency,
    String? country,
    String? icon,
    String? color,
    String? logoUrl,
    bool? cashRegisterEnabled,
    String? description,
    DateTime? createdAt,
    bool? isSynced,
    bool? isDeleted,
    DateTime? deletedAt,
  }) {
    return Business(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      country: country ?? this.country,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      logoUrl: logoUrl ?? this.logoUrl,
      cashRegisterEnabled: cashRegisterEnabled ?? this.cashRegisterEnabled,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'currency': currency,
      'country': country,
      'icon': icon,
      'color': color,
      'logo_url': logoUrl,
      'cash_register_enabled': cashRegisterEnabled ? 1 : 0,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
      'is_deleted': isDeleted ? 1 : 0,
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory Business.fromMap(Map<String, dynamic> map) {
    return Business(
      id: map['id'] as String,
      userId: map['user_id'] as String? ?? 'default_user',
      name: map['name'] as String,
      currency: map['currency'] as String? ?? 'COP',
      country: map['country'] as String? ?? 'CO',
      icon: map['icon'] as String?,
      color: map['color'] as String?,
      logoUrl: map['logo_url'] as String?,
      // En SQLite es 0/1; en la nube, booleano
      cashRegisterEnabled: map['cash_register_enabled'] == true || map['cash_register_enabled'] == 1,
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      isSynced: (map['is_synced'] as int?) == 1,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      deletedAt: map['deleted_at'] != null ? DateTime.tryParse(map['deleted_at'] as String) : null,
    );
  }
}
