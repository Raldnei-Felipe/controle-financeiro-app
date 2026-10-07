import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class RecurringRepository {
  final AppDatabase database;

  RecurringRepository({AppDatabase? database})
    : database = database ?? AppDatabase.instance;

  Future<List<Map<String, Object?>>> findAll() async {
    final db = await database.database;

    return db.query(
      'recurring_rules',
      orderBy: 'is_active DESC, day_of_month ASC',
    );
  }

  Future<void> insert({
    required String id,
    required String transactionType,
    required String description,
    required double amount,
    required String? categoryId,
    required bool isFixed,
    required DateTime startDate,
  }) async {
    final db = await database.database;
    final dueDate = DateTime(startDate.year, startDate.month, startDate.day);

    await db.insert('recurring_rules', {
      'id': id,
      'transaction_type': transactionType,
      'description': description,
      'amount': amount,
      'category_id': categoryId,
      'is_fixed': isFixed ? 1 : 0,
      'day_of_month': startDate.day,
      'start_date': dueDate.toIso8601String(),
      'next_due_date': dueDate.toIso8601String(),
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> deactivate(String id) async {
    final db = await database.database;

    await db.update(
      'recurring_rules',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
