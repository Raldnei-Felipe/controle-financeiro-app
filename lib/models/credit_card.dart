class CreditCard {
  final String id;
  final String name;
  final String issuer;
  final double creditLimit;
  final int closingDay;
  final int dueDay;
  final int colorValue;
  final bool isActive;
  final DateTime createdAt;

  const CreditCard({
    required this.id,
    required this.name,
    required this.issuer,
    required this.creditLimit,
    required this.closingDay,
    required this.dueDay,
    required this.colorValue,
    required this.isActive,
    required this.createdAt,
  });

  CreditCard copyWith({
    String? id,
    String? name,
    String? issuer,
    double? creditLimit,
    int? closingDay,
    int? dueDay,
    int? colorValue,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return CreditCard(
      id: id ?? this.id,
      name: name ?? this.name,
      issuer: issuer ?? this.issuer,
      creditLimit: creditLimit ?? this.creditLimit,
      closingDay: closingDay ?? this.closingDay,
      dueDay: dueDay ?? this.dueDay,
      colorValue: colorValue ?? this.colorValue,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'issuer': issuer,
      'credit_limit': creditLimit,
      'closing_day': closingDay,
      'due_day': dueDay,
      'color_value': colorValue,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory CreditCard.fromMap(Map<String, Object?> map) {
    return CreditCard(
      id: map['id'] as String,
      name: map['name'] as String,
      issuer: map['issuer'] as String,
      creditLimit: (map['credit_limit'] as num).toDouble(),
      closingDay: (map['closing_day'] as num).toInt(),
      dueDay: (map['due_day'] as num).toInt(),
      colorValue: (map['color_value'] as num).toInt(),
      isActive: (map['is_active'] as num).toInt() == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
