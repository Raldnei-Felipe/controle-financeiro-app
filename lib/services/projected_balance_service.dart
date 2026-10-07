import '../database/app_database.dart';

/// Calcula o saldo projetado de um mês futuro.
///
/// Regras (confirmadas com o usuário):
/// - Acumulativo: cada mês desconta do saldo do mês anterior.
/// - Base: tudo que entrou/saiu até o fim do mês atual.
/// - Mês futuro M: soma receitas cadastradas em M, subtrai despesas
///   cadastradas em M (incluindo parcelas de cartão, que já estão
///   datadas no mês de vencimento de cada parcela) e projeta as
///   despesas fixas do mês atual que ainda não existem em M.
///
/// NÃO recalcula fechamento de cartão aqui: cada parcela já é uma
/// linha em 'expenses' com a data do mês em que vence.
class ProjectedBalanceService {
  final AppDatabase database;

  ProjectedBalanceService({
    AppDatabase? database,
  }) : database = database ?? AppDatabase.instance;

  Future<double> calculateProjectedBalance(DateTime month) async {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);
    final target = DateTime(month.year, month.month, 1);

    // Mês atual ou passado → saldo real, sem projeção.
    if (!target.isAfter(currentMonth)) {
      return _currentBalanceUpTo(currentMonth);
    }

    final db = await database.database;

    final nextMonthStart = DateTime(
      currentMonth.year,
      currentMonth.month + 1,
      1,
    );
    final targetEnd = DateTime(target.year, target.month + 1, 1);

    // ── Desempenho: apenas 2 consultas para tudo (em vez de dezenas). ──
    final allIncomes = await db.query(
      'incomes',
      where: 'date < ?',
      whereArgs: [targetEnd.toIso8601String()],
    );

    final allExpenses = await db.query(
      'expenses',
      where: 'date < ?',
      whereArgs: [targetEnd.toIso8601String()],
    );

    // 1) Saldo base: tudo até o fim do mês atual (ex.: R$ 5.000).
    final baseIncomes = _inRange(allIncomes, DateTime(2000), nextMonthStart);
    final baseExpenses = _inRange(allExpenses, DateTime(2000), nextMonthStart);
    double saldo = _sum(baseIncomes) - _sum(baseExpenses);

    // 2) Despesas FIXAS do mês atual → projetadas como recorrentes
    //    nos meses seguintes (se ainda não existirem lá).
    final currentMonthStart = DateTime(
      currentMonth.year,
      currentMonth.month,
      1,
    );
    final currentFixed = allExpenses.where((row) {
      final isFixed = (row['is_fixed'] as num?)?.toInt() == 1;
      final date = row['date'] as String? ?? '';
      return isFixed &&
          date.compareTo(currentMonthStart.toIso8601String()) >= 0 &&
          date.compareTo(nextMonthStart.toIso8601String()) < 0;
    }).toList();

    // 3) Acumula mês a mês até o mês alvo.
    var cursor = DateTime(currentMonth.year, currentMonth.month + 1, 1);
    while (!cursor.isAfter(target)) {
      final monthStart = DateTime(cursor.year, cursor.month, 1);
      final monthEnd = DateTime(cursor.year, cursor.month + 1, 1);

      final monthExpenses = _inRange(allExpenses, monthStart, monthEnd);
      final monthIncomes = _inRange(allIncomes, monthStart, monthEnd);

      saldo += _sum(monthIncomes);
      saldo -= _sum(monthExpenses);

      // Marcos já cadastrados NESTE mês (evita projetar em duplicidade).
      final existingFixed = <String>{};
      for (final expense in monthExpenses) {
        if ((expense['is_fixed'] as num?)?.toInt() == 1) {
          final desc =
          (expense['description'] as String? ?? '').trim().toLowerCase();
          final amount = (expense['amount'] as num).toDouble();
          existingFixed.add('$desc|$amount');
        }
      }

      // 3.1) Projeção das despesas fixas do mês atual que ainda não estão em M.
      for (final fixed in currentFixed) {
        final desc =
        (fixed['description'] as String? ?? '').trim().toLowerCase();
        final amount = (fixed['amount'] as num).toDouble();
        if (!existingFixed.contains('$desc|$amount')) {
          saldo -= amount;
        }
      }

      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    return saldo;
  }

  /// Saldo real (sem projeção) de um mês atual/passado.
  Future<double> _currentBalanceUpTo(DateTime currentMonth) async {
    final db = await database.database;
    final nextMonthStart = DateTime(
      currentMonth.year,
      currentMonth.month + 1,
      1,
    );

    final incomes = await db.query(
      'incomes',
      where: 'date < ?',
      whereArgs: [nextMonthStart.toIso8601String()],
    );
    final expenses = await db.query(
      'expenses',
      where: 'date < ?',
      whereArgs: [nextMonthStart.toIso8601String()],
    );

    return _sum(incomes) - _sum(expenses);
  }

  List<Map<String, Object?>> _inRange(
      List<Map<String, Object?>> rows,
      DateTime start,
      DateTime end,
      ) {
    final startIso = start.toIso8601String();
    final endIso = end.toIso8601String();
    return rows.where((row) {
      final date = row['date'] as String? ?? '';
      return date.compareTo(startIso) >= 0 && date.compareTo(endIso) < 0;
    }).toList();
  }

  double _sum(List<Map<String, Object?>> rows) {
    return rows.fold<double>(
      0,
          (sum, row) => sum + (row['amount'] as num).toDouble(),
    );
  }
}