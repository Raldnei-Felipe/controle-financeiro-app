class Income {
  final String id;
  final String description;
  final double amount;
  final DateTime date;
  final bool isRecurring;
  final String status;
  final DateTime createdAt;

  const Income({
    required this.id,
    required this.description,
    required this.amount,
    required this.date,
    required this.isRecurring,
    required this.status,
    required this.createdAt,
  });

  Income copyWith({
    String? id,
    String? description,
    double? amount,
    DateTime? date,
    bool? isRecurring,
    String? status,
    DateTime? createdAt,
  }) {
    return Income(
      id: id ?? this.id,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      isRecurring: isRecurring ?? this.isRecurring,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'description': description,
      'amount': amount,
      'date': date.toIso8601String(),
      'is_recurring': isRecurring ? 1 : 0,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Income.fromMap(Map<String, Object?> map) {
    return Income(
      id: map['id'] as String,
      description: map['description'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
      isRecurring: (map['is_recurring'] as int) == 1,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
