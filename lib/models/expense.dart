class Expense {
  final String id;
  final String description;
  final double amount;
  final DateTime date;
  final String categoryId;
  final bool isFixed;
  final String status;
  final DateTime createdAt;
  final String paymentMethod;
  final String? cardId;
  final String? installmentGroupId;
  final int installmentNumber;
  final int installmentCount;
  final bool isVariable;

  const Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.date,
    required this.categoryId,
    required this.isFixed,
    required this.status,
    required this.createdAt,
    this.paymentMethod = 'cash',
    this.isVariable = false,
    this.cardId,
    this.installmentGroupId,
    this.installmentNumber = 1,
    this.installmentCount = 1,
  });

  Expense copyWith({
    String? id,
    String? description,
    double? amount,
    DateTime? date,
    String? categoryId,
    bool? isFixed,
    String? status,
    DateTime? createdAt,
    String? paymentMethod,
    String? cardId,
    String? installmentGroupId,
    int? installmentNumber,
    int? installmentCount,
    bool? isVariable,

  }) {
    return Expense(
      id: id ?? this.id,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      categoryId: categoryId ?? this.categoryId,
      isFixed: isFixed ?? this.isFixed,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      cardId: cardId ?? this.cardId,
      installmentGroupId: installmentGroupId ?? this.installmentGroupId,
      installmentNumber: installmentNumber ?? this.installmentNumber,
      installmentCount: installmentCount ?? this.installmentCount,
      isVariable: isVariable ?? this.isVariable,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'description': description,
      'amount': amount,
      'date': date.toIso8601String(),
      'category_id': categoryId,
      'is_fixed': isFixed ? 1 : 0,
      'status': status,
      'payment_method': paymentMethod,
      'card_id': cardId,
      'installment_group_id': installmentGroupId,
      'installment_number': installmentNumber,
      'installment_count': installmentCount,
      'is_variable': isVariable ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Expense.fromMap(Map<String, Object?> map) {
    return Expense(
      id: map['id'] as String,
      description: map['description'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
      categoryId: map['category_id'] as String,
      isFixed: (map['is_fixed'] as num).toInt() == 1,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      paymentMethod: map['payment_method'] as String? ?? 'cash',
      cardId: map['card_id'] as String?,
      installmentGroupId: map['installment_group_id'] as String?,
      installmentNumber: (map['installment_number'] as num?)?.toInt() ?? 1,
      installmentCount: (map['installment_count'] as num?)?.toInt() ?? 1,
      isVariable: (map['is_variable'] as int? ?? 0) == 1,
    );
  }
}
