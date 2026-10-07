import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

class RecurringService {
  final AppDatabase database;

  RecurringService({AppDatabase? database})
    : database = database ?? AppDatabase.instance;

  Future<void> generateDueTransactions() async {
    final db = await database.database;
    final today = _dateOnly(DateTime.now());

    await db.transaction((transaction) async {
      final rules = await transaction.query(
        'recurring_rules',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'next_due_date ASC',
      );

      for (final rule in rules) {
        final ruleId = rule['id'] as String;
        final type = rule['transaction_type'] as String;
        final description = rule['description'] as String;
        final amount = (rule['amount'] as num).toDouble();
        final day = (rule['day_of_month'] as num).toInt();
        final categoryId = rule['category_id'] as String?;
        final isFixed = (rule['is_fixed'] as num).toInt() == 1;

        var dueDate = DateTime.parse(rule['next_due_date'] as String);

        while (!_dateOnly(dueDate).isAfter(today)) {
          final monthKey =
              '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}';

          if (type == 'income') {
            await transaction.insert('incomes', {
              'id': const Uuid().v4(),
              'description': description,
              'amount': amount,
              'date': _dateOnly(dueDate).toIso8601String(),
              'is_recurring': 0,
              'status': 'received',
              'recurrence_rule_id': ruleId,
              'recurrence_month_key': monthKey,
              'created_at': DateTime.now().toIso8601String(),
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          } else if (type == 'expense') {
            if (categoryId == null) {
              throw StateError(
                'Uma regra de despesa recorrente está sem categoria.',
              );
            }

            await transaction.insert('expenses', {
              'id': const Uuid().v4(),
              'description': description,
              'amount': amount,
              'date': _dateOnly(dueDate).toIso8601String(),
              'category_id': categoryId,
              'is_fixed': isFixed ? 1 : 0,
              'status': 'pending',
              'payment_method': 'cash',
              'card_id': null,
              'installment_group_id': null,
              'installment_number': 1,
              'installment_count': 1,
              'recurrence_rule_id': ruleId,
              'recurrence_month_key': monthKey,
              'created_at': DateTime.now().toIso8601String(),
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }

          dueDate = _nextMonthlyDate(dueDate, day);
        }

        await transaction.update(
          'recurring_rules',
          {'next_due_date': dueDate.toIso8601String()},
          where: 'id = ?',
          whereArgs: [ruleId],
        );
      }
    });
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _nextMonthlyDate(DateTime currentDate, int day) {
    final nextMonth = DateTime(currentDate.year, currentDate.month + 1, 1);

    final lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;

    return DateTime(
      nextMonth.year,
      nextMonth.month,
      day > lastDay ? lastDay : day,
    );
  }
}
