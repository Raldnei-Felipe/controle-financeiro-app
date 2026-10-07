import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../recurring/recurring_screen.dart';
import '../../core/theme/app_theme.dart';
import '../../models/category.dart';
import '../../models/expense.dart';
import '../../repositories/card_invoice_repository.dart';
import '../../repositories/card_repository.dart';
import '../../repositories/category_repository.dart';
import '../../repositories/expense_repository.dart';
import '../../repositories/income_repository.dart';
import '../settings/settings_screen.dart';
import 'dart:math' as math;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final IncomeRepository incomeRepository = IncomeRepository();
  final ExpenseRepository expenseRepository = ExpenseRepository();
  final CategoryRepository categoryRepository = CategoryRepository();
  final CardRepository cardRepository = CardRepository();
  final CardInvoiceRepository invoiceRepository = CardInvoiceRepository();

  DateTime selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  List<Category> categories = [];
  double incomeTotal = 0;
  double fixedTotal = 0;
  double variableTotal = 0;
  double cardDueTotal = 0;
  double expenseTotal = 0;
  double carriedBalance = 0;
  double projectedResult = 0;
  bool isFutureMonth = false;
  bool isImmediateNextMonth = false;
  Map<String, double> categoryTotals = {};
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (!mounted) {
      return;
    }
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month, 1);
      final targetMonth = DateTime(
        selectedMonth.year,
        selectedMonth.month,
        1,
      );
      final future = targetMonth.isAfter(currentMonth);
      final nextMonth = DateTime(
        currentMonth.year,
        currentMonth.month + 1,
        1,
      );
      final immediateNext = future && targetMonth == nextMonth;

      final results = await Future.wait([
        categoryRepository.findActive(),
        expenseRepository.findByMonthWithProjectedFixed(selectedMonth),
        expenseRepository.findByMonth(selectedMonth),
      ]);

      final loadedCategories = results[0] as List<Category>;
      final projectedExpenses = results[1] as List<Expense>;
      final monthExpenses = results[2] as List<Expense>;

      // ── Despesas fixas (reais + projetadas nos meses futuros) ──
      final fixedList = projectedExpenses
          .where((expense) => expense.isFixed)
          .toList();
      final loadedFixedTotal = fixedList.fold<double>(
        0,
            (sum, expense) => sum + expense.amount,
      );

      // ── Despesas diárias (Pix/Débito/Dinheiro) — sem cartão e sem fixas ──
      final variableList = monthExpenses
          .where(
            (expense) =>
        expense.paymentMethod != 'card' && !expense.isFixed,
      )
          .toList();
      final loadedVariableTotal = variableList.fold<double>(
        0,
            (sum, expense) => sum + expense.amount,
      );

      // ── Faturas de cartão que VENCEM no mês selecionado ──
      final loadedCardDueTotal = await _cardDueInMonth(selectedMonth);

      // ── Total de despesas do mês ──
      // Mês futuro: fixas + cartão (não há despesas diárias ainda).
      final loadedExpenseTotal = future
          ? loadedFixedTotal + loadedCardDueTotal
          : loadedFixedTotal + loadedVariableTotal + loadedCardDueTotal;

      // ── Receitas ──
      double loadedIncomeTotal;
      if (future) {
        // Mês futuro: receitas recorrentes (todo mês) + receitas manuais
        // adicionadas ESPECIFICAMENTE para esse mês.
        // A receita manual vale só no mês em que entrou (não vaza p/ o próximo).
        final recurring = await incomeRepository.recurringTotal();
        final manual =
        await incomeRepository.nonRecurringTotalByMonth(selectedMonth);
        loadedIncomeTotal = recurring + manual;
      } else {
        // Mês atual/passado: receitas reais do mês.
        loadedIncomeTotal = await incomeRepository.totalByMonth(selectedMonth);
      }

      // ── Box 1 — Valor em conta ──
      // Novembro (1º mês futuro): herda o saldo real do mês atual.
      // Dezembro em diante: zera (R$ 0,00).
      double loadedCarriedBalance = 0;
      if (immediateNext) {
        loadedCarriedBalance = await _realMonthBalance(currentMonth);
      }

      // ── Box 4 — Resultado ──
      double loadedProjectedResult;
      if (future) {
        if (immediateNext) {
          // Novembro: Valor em conta − Despesas do mês
          loadedProjectedResult =
              loadedCarriedBalance - loadedExpenseTotal;
        } else {
          // Dezembro em diante: Despesas do mês − Receitas
          loadedProjectedResult = loadedExpenseTotal - loadedIncomeTotal;
        }
      } else {
        loadedProjectedResult = loadedIncomeTotal - loadedExpenseTotal;
      }

      // ── Gastos por categoria (fixas + diárias, sem cartão) ──
      final loadedCategoryTotals = <String, double>{};
      for (final expense in [...fixedList, ...variableList]) {
        final name = _categoryName(expense.categoryId);
        loadedCategoryTotals[name] =
            (loadedCategoryTotals[name] ?? 0) + expense.amount;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        categories = loadedCategories;
        incomeTotal = loadedIncomeTotal;
        fixedTotal = loadedFixedTotal;
        variableTotal = loadedVariableTotal;
        cardDueTotal = loadedCardDueTotal;
        expenseTotal = loadedExpenseTotal;
        carriedBalance = loadedCarriedBalance;
        projectedResult = loadedProjectedResult;
        isFutureMonth = future;
        isImmediateNextMonth = immediateNext;
        categoryTotals = loadedCategoryTotals;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorMessage = 'Não foi possível carregar o resumo financeiro.';
        isLoading = false;
      });
    }
  }

  // ── Soma das faturas de cartão que vencem no mês informado ──
  Future<double> _cardDueInMonth(DateTime month) async {
    final cards = await cardRepository.findAll();
    double total = 0;
    for (final card in cards) {
      final invoices = await invoiceRepository.findByCard(card);
      for (final invoice in invoices) {
        if (invoice.dueDate.year == month.year &&
            invoice.dueDate.month == month.month) {
          total += invoice.total;
        }
      }
    }
    return total;
  }

  // ── Saldo final real de um mês: receitas − despesas reais ──
  Future<double> _realMonthBalance(DateTime month) async {
    final income = await incomeRepository.totalByMonth(month);
    final fixed = await _fixedTotalIn(month);
    final variable = await _variableTotalIn(month);
    final cardDue = await _cardDueInMonth(month);
    return income - (fixed + variable + cardDue);
  }

  Future<double> _fixedTotalIn(DateTime month) async {
    final expenses =
    await expenseRepository.findByMonthWithProjectedFixed(month);
    final fixed = expenses.where((e) => e.isFixed).toList();
    return fixed.fold<double>(0, (sum, e) => sum + e.amount);
  }

  Future<double> _variableTotalIn(DateTime month) async {
    final expenses = await expenseRepository.findByMonth(month);
    final variable = expenses
        .where((e) => e.paymentMethod != 'card' && !e.isFixed)
        .toList();
    return variable.fold<double>(0, (sum, e) => sum + e.amount);
  }

  Future<void> _changeMonth(int amount) async {
    setState(() {
      selectedMonth = DateTime(
        selectedMonth.year,
        selectedMonth.month + amount,
        1,
      );
    });
    await _loadDashboard();
  }

  // Saldo exibido no card principal (mês atual) ou resultado (mês futuro).
  double get balance {
    if (isFutureMonth) {
      return projectedResult;
    }
    return incomeTotal - expenseTotal;
  }

  String _monthLabel(DateTime date) {
    const months = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril',
      'Maio', 'Junho', 'Julho', 'Agosto',
      'Setembro', 'Outubro', 'Novembro', 'Dezembro',
    ];
    return '${months[date.month - 1]} de ${date.year}';
  }

  String _currency(double value) {
    return NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    ).format(value);
  }

  String _categoryName(String id) {
    for (final category in categories) {
      if (category.id == id) {
        return category.name;
      }
    }
    return 'Categoria desconhecida';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MINHAS FINANÇAS',
          style: TextStyle(
            color: AppColors.darkOrange,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
            tooltip: 'Configurações',
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            onPressed: _loadDashboard,
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const RecurringScreen(),
                ),
              );
            },
            tooltip: 'Recorrências',
            icon: const Icon(Icons.event_repeat),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.orange,
        onRefresh: _loadDashboard,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 260),
          Center(
            child: CircularProgressIndicator(color: AppColors.orange),
          ),
        ],
      );
    }
    if (errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 180),
          const Icon(Icons.error_outline, color: AppColors.red, size: 48),
          const SizedBox(height: 16),
          Text(errorMessage!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _loadDashboard,
            child: const Text('Tentar novamente'),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Olá! Aqui está seu resumo',
          style: TextStyle(color: AppColors.gray),
        ),
        const SizedBox(height: 5),
        const Text(
          'Controle financeiro',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildMonthSelector(),
        const SizedBox(height: 16),
        if (isFutureMonth)
          _buildFutureMonthBoxes()
        else ...[
          _buildBalanceCard(),
          const SizedBox(height: 12),
          _buildIncomeAndExpenseCards(),
          const SizedBox(height: 12),
          _buildCompositionCard(),
        ],
        const SizedBox(height: 20),
        _buildCategorySection(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildMonthSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Mês anterior',
            ),
            Expanded(
              child: Text(
                _monthLabel(selectedMonth),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.darkOrange,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Próximo mês',
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MESES FUTUROS — os 5 boxes
  // ─────────────────────────────────────────────────────────────
  Widget _buildFutureMonthBoxes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Box 1 — Valor em conta
        _futureBox(
          title: 'Valor em conta',
          value: carriedBalance,
          caption: isImmediateNextMonth
              ? 'Saldo que sobrou no mês anterior'
              : 'Zerado a partir deste mês (R\$ 0,00)',
          icon: Icons.account_balance_wallet_outlined,
          color: AppColors.green,
          background: AppColors.softGreen,
          highlight: true,
        ),
        const SizedBox(height: 12),
        // Box 2 + Box 3
        Row(
          children: [
            Expanded(
              child: _futureBox(
                title: 'Despesas fixas',
                value: fixedTotal,
                caption: 'Projeção do mês',
                icon: Icons.repeat,
                color: AppColors.orange,
                background: AppColors.lightOrange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _futureBox(
                title: 'Receitas',
                value: incomeTotal,
                caption: 'Fixas / recorrentes',
                icon: Icons.trending_up,
                color: AppColors.green,
                background: AppColors.softGreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Box 5 — Despesas do mês (fixas + cartão)
        _futureBox(
          title: 'Despesas do mês',
          value: expenseTotal,
          caption:
          'Fixas + cartão (R\$ ${_currency(cardDueTotal).replaceFirst('R\$ ', '')} de cartão)',
          icon: Icons.trending_down,
          color: AppColors.red,
          background: AppColors.softRed,
        ),
        const SizedBox(height: 12),
        // Box 4 — Resultado
        _buildResultBox(),
      ],
    );
  }

  Widget _buildResultBox() {
    final bool hasSurplus = isImmediateNextMonth
        ? projectedResult >= 0
        : projectedResult <= 0;
    final String caption = hasSurplus
        ? 'Sobra de ${_currency(projectedResult.abs())} após pagar as despesas do mês'
        : 'Falta ${_currency(projectedResult.abs())} para fechar o mês';
    return _futureBox(
      title: 'Resultado',
      value: projectedResult,
      caption: caption,
      icon: hasSurplus
          ? Icons.check_circle_outline
          : Icons.warning_amber_outlined,
      color: hasSurplus ? AppColors.green : AppColors.red,
      background: hasSurplus ? AppColors.softGreen : AppColors.softRed,
      highlight: true,
    );
  }

  Widget _futureBox({
    required String title,
    required double value,
    required String caption,
    required IconData icon,
    required Color color,
    required Color background,
    bool highlight = false,
  }) {
    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: highlight ? 16 : 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              alignment: Alignment.centerLeft,
              child: Text(
                _currency(value),
                style: TextStyle(
                  color: color,
                  fontSize: highlight ? 26 : 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              style: const TextStyle(color: AppColors.gray, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MÊS ATUAL / PASSADO — layout existente
  // ─────────────────────────────────────────────────────────────
  Widget _buildBalanceCard() {
    final isPositive = balance >= 0;
    return Card(
      color: isPositive ? AppColors.softGreen : AppColors.softRed,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPositive
                      ? Icons.account_balance_wallet_outlined
                      : Icons.warning_amber_outlined,
                  color: isPositive ? AppColors.green : AppColors.red,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Saldo do mês',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _currency(balance),
              style: TextStyle(
                color: isPositive ? AppColors.green : AppColors.red,
                fontSize: 27,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomeAndExpenseCards() {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            title: 'Receitas',
            value: _currency(incomeTotal),
            icon: Icons.trending_up,
            color: AppColors.green,
            background: AppColors.softGreen,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            title: 'Despesas',
            value: _currency(expenseTotal),
            icon: Icons.trending_down,
            color: AppColors.red,
            background: AppColors.softRed,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color background,
  }) {
    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(color: AppColors.gray, fontSize: 13),
            ),
            const SizedBox(height: 5),
            FittedBox(
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompositionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Composição das despesas do mês',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'O que sai da sua conta neste mês.',
              style: TextStyle(color: AppColors.gray, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _compositionLine(
              label: 'Despesas fixas',
              value: fixedTotal,
              color: AppColors.orange,
            ),
            const SizedBox(height: 12),
            _compositionLine(
              label: 'Despesas diárias (Pix/Débito)',
              value: variableTotal,
              color: AppColors.blue,
            ),
            const SizedBox(height: 12),
            _compositionLine(
              label: 'Cartão a pagar no mês',
              value: cardDueTotal,
              color: AppColors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _compositionLine({
    required String label,
    required double value,
    required Color color,
  }) {
    final percentage = expenseTotal <= 0
        ? 0.0
        : (value / expenseTotal).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(
              _currency(value),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: percentage,
          minHeight: 8,
          borderRadius: BorderRadius.circular(20),
          backgroundColor: color.withValues(alpha: .15),
          color: color,
        ),
      ],
    );
  }

  Widget _buildCategorySection() {
    final entries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final hasData = entries.isNotEmpty && entries.any((e) => e.value > 0);

    if (!hasData) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(
                Icons.pie_chart_outline,
                color: AppColors.orange,
                size: 40,
              ),
              const SizedBox(height: 8),
              const Text(
                'Ainda não existem gastos por categoria.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              const Text(
                'Cadastre uma despesa para visualizar a distribuição.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.gray),
              ),
            ],
          ),
        ),
      );
    }

    final total = entries.fold<double>(0, (sum, e) => sum + e.value);
    final slices = entries.map((entry) {
      final category = _categoryByName(entry.key);
      return _CategorySlice(
        name: entry.key,
        value: entry.value,
        color: category == null
            ? AppColors.orange
            : Color(category.colorValue),
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gastos por categoria',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Distribuição das despesas do mês (sem cartão).',
              style: TextStyle(color: AppColors.gray, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(painter: _PieChartPainter(slices)),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    children: [
                      for (final slice in slices.take(6))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: slice.color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  slice.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Text(
                                _percent(slice.value, total),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (slices.length > 6) ...[
              const SizedBox(height: 6),
              Text(
                'E mais ${slices.length - 6} categorias...',
                style: const TextStyle(color: AppColors.gray, fontSize: 12),
              ),
            ],
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total gasto nas categorias',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  _currency(total),
                  style: const TextStyle(
                    color: AppColors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _percent(double value, double total) {
    if (total <= 0) {
      return '0%';
    }
    final p = (value / total) * 100;
    return '${p.toStringAsFixed(p >= 10 ? 0 : 1)}%';
  }

  Category? _categoryByName(String name) {
    for (final category in categories) {
      if (category.name == name) {
        return category;
      }
    }
    return null;
  }
}
class _CategorySlice {
  final String name;
  final double value;
  final Color color;

  const _CategorySlice({
    required this.name,
    required this.value,
    required this.color,
  });
}

class _PieChartPainter extends CustomPainter {
  final List<_CategorySlice> slices;

  const _PieChartPainter(this.slices);

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (s, e) => s + e.value);
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2;

    if (total <= 0) {
      final paint = Paint()
        ..color = AppColors.lightOrange
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, paint);
      return;
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.butt;

    var startAngle = -math.pi / 2;
    for (final slice in slices) {
      final sweep = (slice.value / total) * 2 * math.pi;
      stroke.color = slice.color;
      canvas.drawArc(rect.deflate(11), startAngle, sweep, false, stroke);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.slices != slices;
  }
}