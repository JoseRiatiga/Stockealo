class Category {
  final String id;
  final String businessId;
  final String name;
  final String? colorHex;

  Category({
    required this.id,
    this.businessId = 'default_business',
    required this.name,
    this.colorHex,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'color_hex': colorHex,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as String,
      businessId: map['business_id'] as String? ?? 'default_business',
      name: map['name'] as String,
      colorHex: map['color_hex'] as String?,
    );
  }
}
