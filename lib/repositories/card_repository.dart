import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/credit_card.dart';

class CardRepository {
  final AppDatabase database;

  CardRepository({AppDatabase? database})
    : database = database ?? AppDatabase.instance;

  Future<List<CreditCard>> findAll() async {
    final db = await database.database;

    final rows = await db.query(
      'credit_cards',
      orderBy: 'is_active DESC, name COLLATE NOCASE ASC',
    );

    return rows.map(CreditCard.fromMap).toList();
  }

  Future<List<CreditCard>> findActive() async {
    final db = await database.database;

    final rows = await db.query(
      'credit_cards',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map(CreditCard.fromMap).toList();
  }

  Future<CreditCard?> findById(String id) async {
    final db = await database.database;

    final rows = await db.query(
      'credit_cards',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return CreditCard.fromMap(rows.first);
  }

  Future<void> insert(CreditCard card) async {
    final db = await database.database;

    await db.insert(
      'credit_cards',
      card.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(CreditCard card) async {
    final db = await database.database;

    await db.update(
      'credit_cards',
      card.toMap(),
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  Future<void> deactivate(String id) async {
    final db = await database.database;

    await db.update(
      'credit_cards',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> reactivate(String id) async {
    final db = await database.database;

    await db.update(
      'credit_cards',
      {'is_active': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  /// Exclui definitivamente o cartão e todos os dados vinculados
  /// (compras no cartão e faturas).
  Future<void> delete(CreditCard card) async {
    final db = await database.database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'expenses',
        where: 'payment_method = ? AND card_id = ?',
        whereArgs: ['card', card.id],
      );
      await transaction.delete(
        'card_invoices',
        where: 'card_id = ?',
        whereArgs: [card.id],
      );
      await transaction.delete(
        'credit_cards',
        where: 'id = ?',
        whereArgs: [card.id],
      );
    });
  }
}
