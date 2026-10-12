class AppUser {
  final String id;
  final String email;
  final String? name;
  final String? phone;
  final String? avatarPath;
  final DateTime createdAt;

  AppUser({
    required this.id,
    required this.email,
    this.name,
    this.phone,
    this.avatarPath,
    required this.createdAt,
  });

  String get displayName => (name != null && name!.trim().isNotEmpty) ? name! : email.split('@').first;

  AppUser copyWith({
    String? id,
    String? email,
    String? name,
    String? phone,
    String? avatarPath,
    DateTime? createdAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      avatarPath: avatarPath ?? this.avatarPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'phone': phone,
      'avatar_path': avatarPath,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      email: map['email'] as String,
      name: map['name'] as String?,
      phone: map['phone'] as String?,
      avatarPath: map['avatar_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
