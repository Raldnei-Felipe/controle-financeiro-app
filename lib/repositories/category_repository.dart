import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/category.dart';

class CategoryRepository {
  final AppDatabase database;

  CategoryRepository({AppDatabase? database})
    : database = database ?? AppDatabase.instance;

  Future<List<Category>> findActive() async {
    final db = await database.database;

    final rows = await db.query(
      'categories',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'name ASC',
    );

    return rows.map(Category.fromMap).toList();
  }

  Future<List<Category>> findAll() async {
    final db = await database.database;

    final rows = await db.query('categories', orderBy: 'name ASC');

    return rows.map(Category.fromMap).toList();
  }

  Future<Category?> findById(String id) async {
    final db = await database.database;

    final rows = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return Category.fromMap(rows.first);
  }

  Future<void> insert(Category category) async {
    final db = await database.database;

    await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(Category category) async {
    final db = await database.database;

    await db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<void> deactivate(String id) async {
    final db = await database.database;

    await db.update(
      'categories',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
