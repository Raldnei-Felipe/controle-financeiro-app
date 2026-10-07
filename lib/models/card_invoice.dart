import 'expense.dart';

class CardInvoice {
  final String cardId;
  final String cardName;
  final DateTime referenceMonth;
  final DateTime dueDate;
  final double total;
  final bool isPaid;
  final List<Expense> purchases;

  const CardInvoice({
    required this.cardId,
    required this.cardName,
    required this.referenceMonth,
    required this.dueDate,
    required this.total,
    required this.isPaid,
    required this.purchases,
  });

  String get monthKey {
    final month = referenceMonth.month.toString().padLeft(2, '0');
    return '${referenceMonth.year}-$month';
  }
}
