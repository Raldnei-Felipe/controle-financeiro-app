import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/card_invoice.dart';
import '../models/credit_card.dart';
import '../models/expense.dart';
import 'expense_repository.dart';

class CardInvoiceRepository {
  final AppDatabase database;
  final ExpenseRepository expenseRepository;

  CardInvoiceRepository({
    AppDatabase? database,
    ExpenseRepository? expenseRepository,
  }) : database = database ?? AppDatabase.instance,
       expenseRepository = expenseRepository ?? ExpenseRepository();

  Future<List<CardInvoice>> findByCard(CreditCard card) async {
    final purchases = await expenseRepository.findCardPurchasesByCardId(
      card.id,
    );

    final grouped = <String, List<Expense>>{};

    for (final purchase in purchases) {
      final referenceMonth = _referenceMonthFor(purchase.date, card.closingDay);

      final key = _monthKey(referenceMonth);

      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(purchase);
    }

    final db = await database.database;
    final invoices = <CardInvoice>[];

    for (final entry in grouped.entries) {
      final parts = entry.key.split('-');
      final year = int.parse(parts[0]);
      final monthNumber = int.parse(parts[1]);

      final referenceMonth = DateTime(year, monthNumber, 1);
      final dueDate = _dueDateFor(referenceMonth, card.closingDay, card.dueDay);

      final savedRows = await db.query(
        'card_invoices',
        where: 'card_id = ? AND month_key = ?',
        whereArgs: [card.id, entry.key],
        limit: 1,
      );

      var isPaid = false;

      if (savedRows.isNotEmpty) {
        isPaid = (savedRows.first['is_paid'] as num).toInt() == 1;
      }

      final invoicePurchases = entry.value;
      final total = invoicePurchases.fold<double>(
        0,
        (sum, purchase) => sum + purchase.amount,
      );

      invoices.add(
        CardInvoice(
          cardId: card.id,
          cardName: card.name,
          referenceMonth: referenceMonth,
          dueDate: dueDate,
          total: total,
          isPaid: isPaid,
          purchases: invoicePurchases,
        ),
      );
    }

    invoices.sort((a, b) => b.referenceMonth.compareTo(a.referenceMonth));

    return invoices;
  }

  Future<void> setPaid({
    required CardInvoice invoice,
    required bool isPaid,
  }) async {
    final db = await database.database;

    await db.insert('card_invoices', {
      'card_id': invoice.cardId,
      'month_key': invoice.monthKey,
      'due_date': invoice.dueDate.toIso8601String(),
      'is_paid': isPaid ? 1 : 0,
      'paid_at': isPaid ? DateTime.now().toIso8601String() : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  DateTime _referenceMonthFor(DateTime purchaseDate, int closingDay) {
    final purchaseMonth = DateTime(purchaseDate.year, purchaseDate.month, 1);

    if (purchaseDate.day <= closingDay) {
      return purchaseMonth;
    }

    return DateTime(purchaseDate.year, purchaseDate.month + 1, 1);
  }

  DateTime _dueDateFor(DateTime referenceMonth, int closingDay, int dueDay) {
    final dueMonth = dueDay > closingDay
        ? referenceMonth
        : DateTime(referenceMonth.year, referenceMonth.month + 1, 1);

    final lastDayOfMonth = DateTime(dueMonth.year, dueMonth.month + 1, 0).day;

    final safeDueDay = dueDay > lastDayOfMonth ? lastDayOfMonth : dueDay;

    return DateTime(dueMonth.year, dueMonth.month, safeDueDay);
  }

  String _monthKey(DateTime month) {
    final monthText = month.month.toString().padLeft(2, '0');
    return '${month.year}-$monthText';
  }
  /// Soma das compras cuja fatura ainda NÃO foi paga (comprometem o limite).
  Future<double> committedAmount(CreditCard card) async {
    final invoices = await findByCard(card);
    double committed = 0;
    for (final invoice in invoices) {
      if (!invoice.isPaid) {
        committed += invoice.total;
      }
    }
    return committed;
  }
}
