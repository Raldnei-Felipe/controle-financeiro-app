import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/expense.dart';

class ExpenseRepository {
  final AppDatabase database;
  ExpenseRepository({AppDatabase? database})
      : database = database ?? AppDatabase.instance;

  Future<void> insertMany(List<Expense> expenses) async {
    if (expenses.isEmpty) {
      return;
    }
    final db = await database.database;
    await db.transaction((transaction) async {
      for (final expense in expenses) {
        await transaction.insert(
          'expenses',
          expense.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
  }

  Future<List<Expense>> findCardPurchasesByCardId(String cardId) async {
    final db = await database.database;
    final rows = await db.query(
      'expenses',
      where: 'payment_method = ? AND card_id = ?',
      whereArgs: ['card', cardId],
      orderBy: 'date DESC, created_at DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<void> insert(Expense expense) async {
    final db = await database.database;
    await db.insert(
      'expenses',
      expense.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Expense>> findAll() async {
    final db = await database.database;
    final rows = await db.query(
      'expenses',
      orderBy: 'date DESC, created_at DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<Expense?> findById(String id) async {
    final db = await database.database;
    final rows = await db.query(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Expense.fromMap(rows.first);
  }

  Future<List<Expense>> findByMonth(DateTime month) async {
    final db = await database.database;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final rows = await db.query(
      'expenses',
      where: 'date >= ? AND date < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date DESC, created_at DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<double> totalByMonth(DateTime month) async {
    final db = await database.database;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM expenses
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

  Future<double> totalFixedByMonth(DateTime month) async {
    return _totalByType(month: month, isFixed: true);
  }

  Future<double> totalVariableByMonth(DateTime month) async {
    return _totalByType(month: month, isFixed: false);
  }

  Future<double> _totalByType({
    required DateTime month,
    required bool isFixed,
  }) async {
    final db = await database.database;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM expenses
      WHERE date >= ?
        AND date < ?
        AND is_fixed = ?
      ''',
      [start.toIso8601String(), end.toIso8601String(), isFixed ? 1 : 0],
    );
    final value = result.first['total'];
    if (value is num) {
      return value.toDouble();
    }
    return 0;
  }

  Future<Map<String, double>> totalsByCategory(DateTime month) async {
    final db = await database.database;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final result = await db.rawQuery(
      '''
      SELECT
        categories.name AS category_name,
        COALESCE(SUM(expenses.amount), 0) AS category_total
      FROM expenses
      INNER JOIN categories
        ON categories.id = expenses.category_id
      WHERE expenses.date >= ?
        AND expenses.date < ?
      GROUP BY categories.id, categories.name
      ORDER BY category_total DESC
      ''',
      [start.toIso8601String(), end.toIso8601String()],
    );
    final totals = <String, double>{};
    for (final row in result) {
      final name = row['category_name'] as String;
      final value = row['category_total'];
      totals[name] = value is num ? value.toDouble() : 0;
    }
    return totals;
  }

  Future<void> update(Expense expense) async {
    final db = await database.database;
    await db.update(
      'expenses',
      expense.toMap(),
      where: 'id = ?',
      whereArgs: [expense.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await database.database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  /// Retorna as despesas de um mês, incluindo as despesas FIXAS do mês
  /// atual projetadas para os meses futuros (sem duplicar as que já existem).
  /// Para despesas de valor variável (água, luz), o valor usado é o
  /// informado para o mês (fixed_expense_payments.amount) — em qualquer mês.
  Future<List<Expense>> findByMonthWithProjectedFixed(DateTime month) async {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);
    final target = DateTime(month.year, month.month, 1);

    // Despesas reais do mês alvo.
    final realExpenses = await findByMonth(month);

    // ── [CORREÇÃO] Aplica o valor mensal nas despesas variáveis reais ──
    // Mesmo no mês atual/passado, a despesa variável deve mostrar/somar
    // o valor informado para aquele mês (não o 0 do cadastro).
    final adjustedReals = <Expense>[];
    for (final expense in realExpenses) {
      if (expense.isVariable) {
        final monthlyAmount =
        await fixedExpenseAmountForMonth(expense.id, month);
        adjustedReals.add(expense.copyWith(amount: monthlyAmount));
      } else {
        adjustedReals.add(expense);
      }
    }

    // Mês atual ou passado → retorna as reais (já com o valor mensal).
    if (!target.isAfter(currentMonth)) {
      return adjustedReals;
    }

    // Despesas fixas do mês atual (base da projeção).
    final currentFixed = await _findFixedByMonth(currentMonth);

    // Marca as que já existem no mês alvo (evita duplicar).
    // Para despesas variáveis, usa o valor informado do mês (0 se não informado).
    final existing = <String>{};
    for (final expense in adjustedReals) {
      existing.add(
        '${expense.description.trim().toLowerCase()}|${expense.amount}',
      );
    }

    final result = List<Expense>.from(adjustedReals);
    for (final fixed in currentFixed) {
      // Valor mensal da despesa variável (água, luz...).
      // Se ainda não informado, vale 0 (só o título, não entra na soma).
      final monthlyAmount = fixed.isVariable
          ? await fixedExpenseAmountForMonth(fixed.id, month)
          : fixed.amount;

      // Chave de deduplicação usa o valor mensal (evita duplicar quando
      // o valor informado bate com uma despesa real já existente).
      final key =
          '${fixed.description.trim().toLowerCase()}|$monthlyAmount';
      if (existing.contains(key)) {
        continue;
      }

      // Data da parcela projetada: mesmo dia da fixa, no mês alvo
      // (ajusta para o último dia do mês se o dia não existir).
      final lastDay = DateTime(target.year, target.month + 1, 0).day;
      final day = fixed.date.day > lastDay ? lastDay : fixed.date.day;
      final projectedDate = DateTime(target.year, target.month, day);

      result.add(
        fixed.copyWith(
          id: 'projected-${fixed.id}-${target.year}-${target.month}',
          date: projectedDate,
          amount: monthlyAmount,
        ),
      );
    }

    // Ordena por data (mais recente primeiro, como o restante do app).
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  /// Despesas fixas de um mês específico.
  Future<List<Expense>> _findFixedByMonth(DateTime month) async {
    final db = await database.database;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final rows = await db.query(
      'expenses',
      where: 'date >= ? AND date < ? AND is_fixed = ?',
      whereArgs: [
        start.toIso8601String(),
        end.toIso8601String(),
        1,
      ],
      orderBy: 'date DESC, created_at DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  /// Totais de despesas de um mês, incluindo as despesas FIXAS do mês
  /// atual projetadas para os meses futuros.
  /// Retorna total, fixas, variáveis e o total por categoria (por nome).
  Future<({
  double total,
  double fixed,
  double variable,
  Map<String, double> byCategory,
  })> projectedTotals(DateTime month) async {
    final expenses = await findByMonthWithProjectedFixed(month);
    double total = 0;
    double fixed = 0;
    double variable = 0;
    final byCategoryId = <String, double>{};
    for (final expense in expenses) {
      total += expense.amount;
      if (expense.isFixed) {
        fixed += expense.amount;
      } else {
        variable += expense.amount;
      }
      byCategoryId[expense.categoryId] =
          (byCategoryId[expense.categoryId] ?? 0) + expense.amount;
    }
    // Converte os IDs de categoria em nomes (como o SQL faz hoje).
    final db = await database.database;
    final categoryRows = await db.query('categories');
    final idToName = <String, String>{};
    for (final row in categoryRows) {
      idToName[row['id'] as String] = row['name'] as String? ?? '';
    }
    final byCategory = <String, double>{};
    byCategoryId.forEach((id, value) {
      byCategory[idToName[id] ?? 'Categoria desconhecida'] = value;
    });
    return (
    total: total,
    fixed: fixed,
    variable: variable,
    byCategory: byCategory,
    );
  }

  /// Saldo disponível do cartão: limite - parcelas/compras ainda não pagas.
  Future<double> availableLimitForCard(String cardId, double creditLimit) async {
    final purchases = await findCardPurchasesByCardId(cardId);
    double committed = 0;
    for (final purchase in purchases) {
      // Só o que ainda não foi pago compromete o limite.
      if (purchase.status != 'paid') {
        committed += purchase.amount;
      }
    }
    return creditLimit - committed;
  }

  /// Exclui uma compra do cartão. Se for parcelada, exclui TODAS as
  /// parcelas do grupo de uma só vez.
  Future<void> deletePurchase(Expense purchase) async {
    final db = await database.database;
    await db.transaction((transaction) async {
      final groupId = purchase.installmentGroupId;
      if (groupId != null) {
        await transaction.delete(
          'expenses',
          where: 'installment_group_id = ?',
          whereArgs: [groupId],
        );
      } else {
        await transaction.delete(
          'expenses',
          where: 'id = ?',
          whereArgs: [purchase.id],
        );
      }
    });
  }

  /// Registra a baixa (pago/pendente) de uma despesa fixa em um mês.
  /// Preserva o 'amount' já informado (não sobrescreve com 0).
  Future<void> setFixedPaid({
    required String expenseId,
    required DateTime month,
    required bool isPaid,
  }) async {
    final db = await database.database;
    final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final existing = await db.query(
      'fixed_expense_payments',
      columns: ['amount'],
      where: 'expense_id = ? AND month_key = ?',
      whereArgs: [expenseId, monthKey],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('fixed_expense_payments', {
        'expense_id': expenseId,
        'month_key': monthKey,
        'is_paid': isPaid ? 1 : 0,
        'paid_at': isPaid ? DateTime.now().toIso8601String() : null,
        'amount': 0,
      });
    } else {
      await db.update(
        'fixed_expense_payments',
        {
          'is_paid': isPaid ? 1 : 0,
          'paid_at': isPaid ? DateTime.now().toIso8601String() : null,
        },
        where: 'expense_id = ? AND month_key = ?',
        whereArgs: [expenseId, monthKey],
      );
    }
  }

  /// Conjunto de expense_id que já foram pagos em um determinado mês.
  Future<Set<String>> paidFixedExpenseIds(DateTime month) async {
    final db = await database.database;
    final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final rows = await db.query(
      'fixed_expense_payments',
      where: 'month_key = ? AND is_paid = ?',
      whereArgs: [monthKey, 1],
    );
    return rows.map((row) => row['expense_id'] as String).toSet();
  }

  /// Despesas fixas de um mês (reais + projetadas) com o status de pagamento.
  Future<List<FixedExpenseWithStatus>> findFixedWithStatus(DateTime month) async {
    final expenses = await findByMonthWithProjectedFixed(month);
    final fixed = expenses.where((e) => e.isFixed).toList();
    final paidIds = await paidFixedExpenseIds(month);
    return fixed.map((e) {
      final isProjected = e.id.startsWith('projected-');
      final sourceId = _sourceExpenseId(e.id);
      return FixedExpenseWithStatus(
        expense: e,
        sourceId: sourceId,
        isProjected: isProjected,
        isPaid: paidIds.contains(sourceId),
      );
    }).toList();
  }

  String _sourceExpenseId(String id) {
    if (!id.startsWith('projected-')) {
      return id;
    }
    final withoutPrefix = id.substring('projected-'.length);
    final parts = withoutPrefix.split('-');
    if (parts.length >= 3) {
      return parts.sublist(0, parts.length - 2).join('-');
    }
    return withoutPrefix;
  }

  Future<void> setExpensePaid({
    required String expenseId,
    required bool isPaid,
  }) async {
    final db = await database.database;
    await db.update(
      'expenses',
      {'status': isPaid ? 'paid' : 'pending'},
      where: 'id = ?',
      whereArgs: [expenseId],
    );
  }

  /// Exclui uma despesa e os registros de baixa vinculados a ela.
  /// Necessário para não quebrar a chave estrangeira de
  /// fixed_expense_payments ao excluir despesas fixas.
  Future<void> deleteExpenseCompletely(Expense expense) async {
    final db = await database.database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'fixed_expense_payments',
        where: 'expense_id = ?',
        whereArgs: [expense.id],
      );
      await transaction.delete(
        'expenses',
        where: 'id = ?',
        whereArgs: [expense.id],
      );
    });
  }

  /// Salva o valor de uma despesa variável (ex.: água, luz) para um mês.
  Future<void> setFixedExpenseAmount({
    required String expenseId,
    required DateTime month,
    required double amount,
  }) async {
    final db = await database.database;
    final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final existing = await db.query(
      'fixed_expense_payments',
      where: 'expense_id = ? AND month_key = ?',
      whereArgs: [expenseId, monthKey],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('fixed_expense_payments', {
        'expense_id': expenseId,
        'month_key': monthKey,
        'is_paid': 0,
        'amount': amount,
      });
    } else {
      await db.update(
        'fixed_expense_payments',
        {'amount': amount},
        where: 'expense_id = ? AND month_key = ?',
        whereArgs: [expenseId, monthKey],
      );
    }
  }

  /// Valor informado de uma despesa variável para um mês (0 se não informado).
  Future<double> fixedExpenseAmountForMonth(
      String expenseId,
      DateTime month,
      ) async {
    final db = await database.database;
    final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final rows = await db.query(
      'fixed_expense_payments',
      columns: ['amount'],
      where: 'expense_id = ? AND month_key = ?',
      whereArgs: [expenseId, monthKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return 0;
    }
    final value = rows.first['amount'];
    return value is num ? value.toDouble() : 0;
  }
}

class FixedExpenseWithStatus {
  final Expense expense;
  final String sourceId;
  final bool isProjected;
  final bool isPaid;

  const FixedExpenseWithStatus({
    required this.expense,
    required this.sourceId,
    required this.isProjected,
    required this.isPaid,
  });
}