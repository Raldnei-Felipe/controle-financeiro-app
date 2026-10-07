class Category {
  final String id;
  final String name;
  final int colorValue;
  final bool isActive;

  const Category({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.isActive,
  });

  Category copyWith({
    String? id,
    String? name,
    int? colorValue,
    bool? isActive,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'color_value': colorValue,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory Category.fromMap(Map<String, Object?> map) {
    return Category(
      id: map['id'] as String,
      name: map['name'] as String,
      colorValue: (map['color_value'] as num).toInt(),
      isActive: (map['is_active'] as int) == 1,
    );
  }
}
