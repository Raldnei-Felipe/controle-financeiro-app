import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/income.dart';

class IncomeRepository {
  final AppDatabase database;

  IncomeRepository({AppDatabase? database})
    : database = database ?? AppDatabase.instance;

  Future<void> insert(Income income) async {
    final db = await database.database;

    await db.insert(
      'incomes',
      income.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Income>> findAll() async {
    final db = await database.database;

    final rows = await db.query(
      'incomes',
      orderBy: 'date DESC, created_at DESC',
    );

    return rows.map(Income.fromMap).toList();
  }

  Future<Income?> findById(String id) async {
    final db = await database.database;

    final rows = await db.query(
      'incomes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return Income.fromMap(rows.first);
  }

  Future<List<Income>> findByMonth(DateTime month) async {
    final db = await database.database;

    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);

    final rows = await db.query(
      'incomes',
      where: 'date >= ? AND date < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date DESC, created_at DESC',
    );

    return rows.map(Income.fromMap).toList();
  }

  Future<double> totalByMonth(DateTime month) async {
    final db = await database.database;

    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);

    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM incomes
      WHERE date >= ? AND date < ?
      ''',
      [start.toIso8601String(), end.toIso8601String()],
    );

    final value = result.first['total'];

    if (value is num) {
      return value.toDouble();
    }

    return 0;
  }

  Future<void> update(Income income) async {
    final db = await database.database;

    await db.update(
      'incomes',
      income.toMap(),
      where: 'id = ?',
      whereArgs: [income.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await database.database;

    await db.delete('incomes', where: 'id = ?', whereArgs: [id]);
  }
  /// Total das receitas recorrentes/fixas (is_recurring = 1).
  /// Usado para projetar as receitas dos meses futuros.
  Future<double> recurringTotal() async {
    final db = await database.database;
    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM incomes
      WHERE is_recurring = 1
      ''',
    );
    final value = result.first['total'];
    if (value is num) {
      return value.toDouble();
    }
    return 0;
  }
  /// Total das receitas NÃO recorrentes de um mês específico.
  /// Uma receita manual adicionada para dezembro aparece SÓ em dezembro
  /// (não reflete no mês posterior).
  Future<double> nonRecurringTotalByMonth(DateTime month) async {
    final db = await database.database;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM incomes
      WHERE is_recurring = 0
        AND date >= ? AND date < ?
      ''',
      [start.toIso8601String(), end.toIso8601String()],
    );
    final value = result.first['total'];
    return value is num ? value.toDouble() : 0;
  }
}
