import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/pdf_export_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/category.dart';
import '../../models/expense.dart';
import '../../repositories/card_invoice_repository.dart';
import '../../repositories/card_repository.dart';
import '../../repositories/category_repository.dart';
import '../../repositories/expense_repository.dart';
import '../../repositories/income_repository.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

final PdfExportService exportService = PdfExportService();

class _ReportsScreenState extends State<ReportsScreen> {
  final IncomeRepository incomeRepository = IncomeRepository();
  final ExpenseRepository expenseRepository = ExpenseRepository();
  final CardRepository cardRepository = CardRepository();
  final CardInvoiceRepository invoiceRepository = CardInvoiceRepository();
  final CategoryRepository categoryRepository = CategoryRepository();

  DateTime selectedMonth = DateTime.now();
  bool isLoading = true;
  String? errorMessage;
  double incomeTotal = 0;
  double expenseTotal = 0;
  double fixedTotal = 0;
  double variableTotal = 0;
  double cardDueTotal = 0;
  Map<String, double> categoryTotals = {};
  List<MonthlyReport> monthlyReports = [];
  List<Category> categories = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _selectMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedMonth,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Selecione o mês do relatório',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      selectedMonth = DateTime(picked.year, picked.month, 1);
    });
  }

  Future<void> _exportPdf() async {
    try {
      final path = await exportService.exportAndShare(
        referenceMonth: selectedMonth,
      );
      if (!mounted) {
        return;
      }
      final message = (path == null || path.isEmpty)
          ? 'Exportação cancelada.'
          : 'Relatório salvo em: $path';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível gerar o arquivo: $error',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
    }
  }

  Future<void> _loadReports() async {
    if (!mounted) {
      return;
    }
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final results = await Future.wait([
        incomeRepository.totalByMonth(selectedMonth),
        _monthExpenseParts(selectedMonth),
        _loadLastSixMonths(),
        categoryRepository.findActive(),
      ]);
      final loadedIncome = results[0] as double;
      final parts = results[1] as _MonthParts;
      final loadedReports = results[2] as List<MonthlyReport>;
      final loadedCategories = results[3] as List<Category>;
      if (!mounted) {
        return;
      }
      setState(() {
        incomeTotal = loadedIncome;
        fixedTotal = parts.fixed;
        variableTotal = parts.variable;
        cardDueTotal = parts.cardDue;
        expenseTotal = parts.fixed + parts.variable + parts.cardDue;
        categoryTotals = parts.byCategory;
        monthlyReports = loadedReports;
        categories = loadedCategories;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorMessage = 'Não foi possível carregar os relatórios.';
        isLoading = false;
      });
    }
  }

  // Soma das faturas de cartão que vencem no mês informado.
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

  // Fixas + diárias (Pix/Débito) + cartão a pagar no mês + categorias.
  Future<_MonthParts> _monthExpenseParts(DateTime month) async {
    final results = await Future.wait([
      expenseRepository.findByMonthWithProjectedFixed(month),
      expenseRepository.findByMonth(month),
    ]);
    final List<Expense> projectedExpenses = results[0];
    final List<Expense> monthExpenses = results[1];
    final fixedList = projectedExpenses
        .where((expense) => expense.isFixed)
        .toList();
    final variableList = monthExpenses
        .where(
          (expense) =>
      expense.paymentMethod != 'card' && !expense.isFixed,
    )
        .toList();
    final fixed = fixedList.fold<double>(
      0,
          (sum, expense) => sum + expense.amount,
    );
    final variable = variableList.fold<double>(
      0,
          (sum, expense) => sum + expense.amount,
    );
    final cardDue = await _cardDueInMonth(month);

    // ── [CORREÇÃO #8] Converte o ID da categoria em NOME ──
    // Busca as categorias ativas para traduzir categoryId -> nome.
    final categoryRows = await categoryRepository.findActive();
    final idToName = <String, String>{};
    for (final category in categoryRows) {
      idToName[category.id] = category.name;
    }

    final byCategory = <String, double>{};
    for (final expense in [...fixedList, ...variableList]) {
      final name = idToName[expense.categoryId] ?? 'Categoria desconhecida';
      byCategory[name] = (byCategory[name] ?? 0) + expense.amount;
    }

    return _MonthParts(
      fixed: fixed,
      variable: variable,
      cardDue: cardDue,
      byCategory: byCategory,
    );
  }

  Future<List<MonthlyReport>> _loadLastSixMonths() async {
    final months = <DateTime>[];
    for (int index = 5; index >= 0; index--) {
      months.add(
        DateTime(selectedMonth.year, selectedMonth.month - index, 1),
      );
    }
    final reports = <MonthlyReport>[];
    for (int i = 0; i < months.length; i++) {
      final month = months[i];
      double income = 0;
      double expenses = 0;
      try {
        income = await incomeRepository.totalByMonth(month);
        final parts = await _monthExpenseParts(month);
        expenses = parts.fixed + parts.variable + parts.cardDue;
      } catch (_) {
        // Se um mês falhar, continua com 0 — nunca derruba a tela.
      }
      reports.add(
        MonthlyReport(
          month: month,
          income: income,
          expenses: expenses,
        ),
      );
    }
    return reports;
  }

  Future<void> _changeMonth(int amount) async {
    setState(() {
      selectedMonth = DateTime(
        selectedMonth.year,
        selectedMonth.month + amount,
        1,
      );
    });
    await _loadReports();
  }

  String _currency(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  String _monthLabel(DateTime month) {
    const months = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril',
      'Maio', 'Junho', 'Julho', 'Agosto',
      'Setembro', 'Outubro', 'Novembro', 'Dezembro',
    ];
    return '${months[month.month - 1]} de ${month.year}';
  }

  String _shortMonthLabel(DateTime month) {
    const months = [
      'Jan', 'Fev', 'Mar', 'Abr',
      'Mai', 'Jun', 'Jul', 'Ago',
      'Set', 'Out', 'Nov', 'Dez',
    ];
    return months[month.month - 1];
  }

  double get balance => incomeTotal - expenseTotal;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios'),
        actions: [
          TextButton.icon(
            onPressed: _selectMonth,
            icon: const Icon(Icons.calendar_month),
            label: Text(
              '${selectedMonth.month.toString().padLeft(2, '0')}/${selectedMonth.year}',
            ),
          ),
          IconButton(
            onPressed: _exportPdf,
            tooltip: 'Exportar PDF',
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            onPressed: _loadReports,
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.orange,
        onRefresh: _loadReports,
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
          const Center(
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
            onPressed: _loadReports,
            child: const Text('Tentar novamente'),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildMonthSelector(),
        const SizedBox(height: 16),
        _buildSummaryGrid(),
        const SizedBox(height: 16),
        _buildMonthlyChart(),
        const SizedBox(height: 16),
        _buildCompositionCard(),
        const SizedBox(height: 16),
        _buildCategoriesCard(),
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

  Widget _buildSummaryGrid() {
    return Column(
      children: [
        Row(
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
        ),
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                title: 'Saldo',
                value: _currency(balance),
                icon: Icons.account_balance_wallet_outlined,
                color: balance >= 0 ? AppColors.green : AppColors.red,
                background: balance >= 0
                    ? AppColors.softGreen
                    : AppColors.softRed,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summaryCard(
                title: 'Categorias',
                value: categoryTotals.length.toString(),
                icon: Icons.category_outlined,
                color: AppColors.orange,
                background: AppColors.lightOrange,
              ),
            ),
          ],
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
            const SizedBox(height: 9),
            Text(
              title,
              style: const TextStyle(color: AppColors.gray, fontSize: 12),
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

  Widget _buildMonthlyChart() {
    double maximum = 0;
    for (final report in monthlyReports) {
      if (report.income > maximum) {
        maximum = report.income;
      }
      if (report.expenses > maximum) {
        maximum = report.expenses;
      }
    }
    if (maximum <= 0) {
      maximum = 1;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Evolução dos últimos seis meses',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: monthlyReports.map((report) {
                  final incomeHeight = (report.income / maximum) * 145;
                  final expenseHeight = (report.expenses / maximum) * 145;
                  final isSelected =
                      report.month.year == selectedMonth.year &&
                          report.month.month == selectedMonth.month;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _bar(height: incomeHeight, color: AppColors.green),
                            const SizedBox(width: 3),
                            _bar(height: expenseHeight, color: AppColors.red),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _shortMonthLabel(report.month),
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.darkOrange
                              : AppColors.gray,
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendItem(color: AppColors.green, label: 'Receitas'),
                const SizedBox(width: 18),
                _legendItem(color: AppColors.red, label: 'Despesas'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar({required double height, required Color color}) {
    return Container(
      width: 10,
      height: height < 4 ? 4 : height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
      ),
    );
  }

  Widget _legendItem({required Color color, required String label}) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(label),
      ],
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
              'Composição das despesas',
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
            const SizedBox(height: 14),
            _compositionLine(
              label: 'Despesas diárias (Pix/Débito)',
              value: variableTotal,
              color: AppColors.blue,
            ),
            const SizedBox(height: 14),
            _compositionLine(
              label: 'Cartões (faturas do mês)',
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
        const SizedBox(height: 7),
        LinearProgressIndicator(
          value: percentage,
          minHeight: 9,
          borderRadius: BorderRadius.circular(20),
          backgroundColor: color.withValues(alpha: .15),
          color: color,
        ),
      ],
    );
  }

  // ── [CORREÇÃO #8] Gráfico de pizza + nomes corretos ──
  Widget _buildCategoriesCard() {
    final entries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final hasData = entries.isNotEmpty && entries.any((e) => e.value > 0);

    if (!hasData) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              const Icon(
                Icons.pie_chart_outline,
                color: AppColors.orange,
                size: 42,
              ),
              const SizedBox(height: 10),
              const Text(
                'Nenhum gasto por categoria neste mês.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    final total = entries.fold<double>(0, (sum, e) => sum + e.value);
    final slices = entries.map((entry) {
      return _CategorySlice(
        name: entry.key,
        value: entry.value,
        color: _categoryColor(entry.key),
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Despesas por categoria',
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

  Color _categoryColor(String name) {
    for (final category in categories) {
      if (category.name == name) {
        return Color(category.colorValue);
      }
    }
    return AppColors.orange;
  }

  String _percent(double value, double total) {
    if (total <= 0) {
      return '0%';
    }
    final p = (value / total) * 100;
    return '${p.toStringAsFixed(p >= 10 ? 0 : 1)}%';
  }
}

class MonthlyReport {
  final DateTime month;
  final double income;
  final double expenses;

  const MonthlyReport({
    required this.month,
    required this.income,
    required this.expenses,
  });
}

class _MonthParts {
  final double fixed;
  final double variable;
  final double cardDue;
  final Map<String, double> byCategory;

  const _MonthParts({
    required this.fixed,
    required this.variable,
    required this.cardDue,
    required this.byCategory,
  });
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