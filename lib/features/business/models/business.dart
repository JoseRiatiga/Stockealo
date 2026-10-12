class Business {
  final String id;
  final String userId;
  final String name;
  final String currency;
  final DateTime createdAt;
  final bool isSynced;
  final bool isDeleted;
  final DateTime? deletedAt;

  Business({
    required this.id,
    required this.userId,
    required this.name,
    this.currency = 'COP',
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
      createdAt: DateTime.parse(map['created_at'] as String),
      isSynced: (map['is_synced'] as int?) == 1,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      deletedAt: map['deleted_at'] != null ? DateTime.tryParse(map['deleted_at'] as String) : null,
    );
  }
}
