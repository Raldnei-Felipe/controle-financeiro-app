import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'categories_screen.dart';
import '../../core/theme/app_theme.dart';
import '../../models/card_invoice.dart';
import '../../models/category.dart';
import '../../models/credit_card.dart';
import '../../models/expense.dart';
import '../../repositories/card_invoice_repository.dart';
import '../../repositories/card_repository.dart';
import '../../repositories/category_repository.dart';
import '../../repositories/expense_repository.dart';
import '../../repositories/income_repository.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final ExpenseRepository expenseRepository = ExpenseRepository();
  final CategoryRepository categoryRepository = CategoryRepository();
  final CardRepository cardRepository = CardRepository();
  final CardInvoiceRepository invoiceRepository = CardInvoiceRepository();
  final IncomeRepository incomeRepository = IncomeRepository();
  final Uuid uuid = const Uuid();

  List<Expense> variableExpenses = [];
  List<FixedExpenseWithStatus> fixedExpenses = [];
  List<Category> categories = [];
  List<_CardDisplay> cardDisplays = [];
  double incomeTotal = 0;
  double cardDueTotal = 0;
  double cardPaidTotal = 0;
  DateTime selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) {
      return;
    }
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final results = await Future.wait([
        categoryRepository.findActive(),
        incomeRepository.totalByMonth(selectedMonth),
        expenseRepository.findFixedWithStatus(selectedMonth),
        expenseRepository.findByMonth(selectedMonth),
        cardRepository.findAll(),
      ]);

      final loadedCategories = results[0] as List<Category>;
      final loadedIncomeTotal = results[1] as double;
      final loadedFixed = results[2] as List<FixedExpenseWithStatus>;
      final monthExpenses = results[3] as List<Expense>;
      final loadedCards = results[4] as List<CreditCard>;

      final loadedVariable = monthExpenses
          .where(
            (expense) =>
        expense.paymentMethod != 'card' && !expense.isFixed,
      )
          .toList();

      final loadedCardDisplays = <_CardDisplay>[];
      for (final card in loadedCards) {
        final invoices = await invoiceRepository.findByCard(card);
        double committed = 0;
        CardInvoice? current;
        for (final invoice in invoices) {
          if (!invoice.isPaid) {
            committed += invoice.total;
          }
          if (invoice.dueDate.year == selectedMonth.year &&
              invoice.dueDate.month == selectedMonth.month) {
            current = invoice;
          }
        }
        final available = (card.creditLimit - committed)
            .clamp(0.0, card.creditLimit);
        loadedCardDisplays.add(
          _CardDisplay(
            card: card,
            limit: card.creditLimit,
            available: available,
            openInvoice: current?.total ?? 0,
            isPaid: current?.isPaid ?? false,
          ),
        );
      }

      double loadedCardDue = 0;
      double loadedCardPaid = 0;
      for (final display in loadedCardDisplays) {
        loadedCardDue += display.openInvoice;
        if (display.isPaid) {
          loadedCardPaid += display.openInvoice;
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        categories = loadedCategories;
        incomeTotal = loadedIncomeTotal;
        fixedExpenses = loadedFixed;
        variableExpenses = loadedVariable;
        cardDisplays = loadedCardDisplays;
        cardDueTotal = loadedCardDue;
        cardPaidTotal = loadedCardPaid;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorMessage = 'Não foi possível carregar as despesas.';
        isLoading = false;
      });
    }
  }

  Future<void> _changeMonth(int amount) async {
    setState(() {
      selectedMonth = DateTime(
        selectedMonth.year,
        selectedMonth.month + amount,
        1,
      );
    });
    await _loadData();
  }

  // ── Getters de totais ──

  // Despesas fixas normais (valor fixo) — SEM as variáveis.
  double get totalFixed {
    return fixedExpenses
        .where((item) => !item.expense.isVariable)
        .fold<double>(0, (sum, item) => sum + item.expense.amount);
  }

  // Soma das despesas fixas variáveis (água, luz...) — valores informados.
  double get totalVariableFixed {
    return fixedExpenses
        .where((item) => item.expense.isVariable)
        .fold<double>(0, (sum, item) => sum + item.expense.amount);
  }

  double get totalVariable {
    return variableExpenses.fold<double>(
      0,
          (sum, expense) => sum + expense.amount,
    );
  }

  // Total geral: fixas normais + fixas variáveis + diárias + cartão.
  double get totalDespesas =>
      totalFixed + totalVariableFixed + totalVariable + cardDueTotal;

  double get jaPago {
    double paid = 0;
    for (final item in fixedExpenses) {
      if (item.isPaid) {
        paid += item.expense.amount;
      }
    }
    for (final expense in variableExpenses) {
      if (expense.status == 'paid') {
        paid += expense.amount;
      }
    }
    paid += cardPaidTotal;
    return paid;
  }

  double get faltante => totalDespesas - jaPago;

  double get saldoDisponivel => incomeTotal - totalDespesas;

  // ── Filtros ──
  List<FixedExpenseWithStatus> get _regularFixedItems =>
      fixedExpenses.where((item) => !item.expense.isVariable).toList();

  List<FixedExpenseWithStatus> get _variableFixedItems =>
      fixedExpenses.where((item) => item.expense.isVariable).toList();

  // ── Ações das despesas fixas ──
  Future<void> _toggleFixedPaid(FixedExpenseWithStatus item) async {
    final newStatus = !item.isPaid;
    try {
      await expenseRepository.setFixedPaid(
        expenseId: item.sourceId,
        month: selectedMonth,
        isPaid: newStatus,
      );
      await _loadData();
      _showMessage(
        newStatus
            ? 'Despesa marcada como paga.'
            : 'Despesa marcada como pendente.',
      );
    } catch (error) {
      _showMessage('Não foi possível atualizar o status.');
    }
  }

  Future<void> _toggleVariablePaid(Expense expense) async {
    final newStatus = expense.status != 'paid';
    try {
      await expenseRepository.setExpensePaid(
        expenseId: expense.id,
        isPaid: newStatus,
      );
      await _loadData();
      _showMessage(
        newStatus
            ? 'Despesa marcada como paga.'
            : 'Despesa marcada como pendente.',
      );
    } catch (error) {
      _showMessage('Não foi possível atualizar o status.');
    }
  }

  // ── Informar o valor mensal de uma despesa variável (água, luz...) ──
  Future<void> _informVariableValue(FixedExpenseWithStatus item) async {
    final controller = TextEditingController(
      text: item.expense.amount > 0
          ? item.expense.amount.toStringAsFixed(2)
          : '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Valor de ${item.expense.description}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Informe o valor para ${_monthLabel(selectedMonth)}.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Valor',
                  hintText: 'Ex.: 132,50',
                  prefixText: 'R\$ ',
                  prefixIcon: Icon(Icons.attach_money),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final normalized =
                controller.text.trim().replaceAll(',', '.');
                final value = double.tryParse(normalized);
                if (value == null || value <= 0) {
                  if (!dialogContext.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(dialogContext)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Informe um valor maior que zero.'),
                      ),
                    );
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }
    try {
      await expenseRepository.setFixedExpenseAmount(
        expenseId: item.sourceId,
        month: selectedMonth,
        amount: result,
      );
      await _loadData();
      // O diálogo só é removido de vez depois da animação de saída;
      // só descartamos o controller aqui, quando ele não é mais usado.
      controller.dispose();
      if (!mounted) {
        return;
      }
      _showMessage(
        'Valor de ${item.expense.description} salvo para '
            '${_monthLabel(selectedMonth)}.',
      );
    } catch (error) {
      controller.dispose();
      _showMessage('Não foi possível salvar o valor.');
    }
  }

  Future<void> _openExpenseForm({Expense? expense}) async {
    if (categories.isEmpty) {
      _showMessage('Cadastre uma categoria antes de criar uma despesa.');
      return;
    }
    final descriptionController = TextEditingController(
      text: expense?.description ?? '',
    );
    final amountController = TextEditingController(
      text: expense == null ? '' : expense.amount.toStringAsFixed(2),
    );
    DateTime selectedDate = expense?.date ?? DateTime.now();
    String selectedCategoryId = expense?.categoryId ?? categories.first.id;
    bool isFixed = expense?.isFixed ?? false;
    bool isVariable = expense?.isVariable ?? false;
    Map<String, Object?>? result;
    try {
      result = await showDialog<Map<String, Object?>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> selectDate() async {
                final pickedDate = await showDatePicker(
                  context: dialogContext,
                  initialDate: selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: 'Selecione a data da despesa',
                  cancelText: 'Cancelar',
                  confirmText: 'Confirmar',
                );
                if (pickedDate == null || !dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  selectedDate = pickedDate;
                });
              }

              void confirmForm() {
                final description = descriptionController.text.trim();
                final normalizedAmount =
                amountController.text.trim().replaceAll(',', '.');
                final amount = double.tryParse(normalizedAmount);
                if (description.isEmpty) {
                  _showMessage('Informe a descrição da despesa.');
                  return;
                }
                if (!isVariable && (amount == null || amount <= 0)) {
                  _showMessage('Informe um valor maior que zero.');
                  return;
                }
                final finalAmount = isVariable ? 0.0 : (amount ?? 0);
                Navigator.of(dialogContext).pop({
                  'description': description,
                  'amount': finalAmount,
                  'date': selectedDate,
                  'categoryId': selectedCategoryId,
                  'isFixed': isFixed,
                  'isVariable': isVariable,
                });
              }

              return AlertDialog(
                title: Text(
                  expense == null ? 'Adicionar despesa' : 'Editar despesa',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: descriptionController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Descrição',
                          hintText: 'Ex.: Conta de luz',
                          prefixIcon: Icon(Icons.description_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Valor',
                          hintText: 'Ex.: 150,00',
                          prefixText: 'R\$ ',
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategoryId,
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: categories.map((category) {
                          return DropdownMenuItem<String>(
                            value: category.id,
                            child: Text(category.name),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            selectedCategoryId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.calendar_month,
                          color: AppColors.orange,
                        ),
                        title: const Text('Data'),
                        subtitle: Text(
                          DateFormat('dd/MM/yyyy').format(selectedDate),
                        ),
                        trailing: TextButton(
                          onPressed: selectDate,
                          child: const Text('Alterar'),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Despesa fixa'),
                        subtitle: const Text(
                          'Indica uma despesa recorrente mensal.',
                        ),
                        value: isFixed,
                        onChanged: (value) {
                          setDialogState(() {
                            isFixed = value;
                            if (!value) {
                              isVariable = false;
                            }
                          });
                        },
                      ),
                      if (isFixed) ...[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Valor varia todo mês'),
                          subtitle: const Text(
                            'Para contas como água e luz: salva o título '
                                'e o valor é informado mensalmente.',
                          ),
                          value: isVariable,
                          onChanged: (value) {
                            setDialogState(() {
                              isVariable = value;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: confirmForm,
                    child: const Text('Salvar'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (result == null || !mounted) {
        return;
      }
      final description = result['description'] as String;
      final amount = result['amount'] as double;
      final date = result['date'] as DateTime;
      final categoryId = result['categoryId'] as String;
      final isFixedResult = result['isFixed'] as bool;
      final isVariableResult = result['isVariable'] as bool;
      if (expense == null) {
        final newExpense = Expense(
          id: uuid.v4(),
          description: description,
          amount: amount,
          date: date,
          categoryId: categoryId,
          isFixed: isFixedResult,
          isVariable: isVariableResult,
          status: 'pending',
          createdAt: DateTime.now(),
        );
        await expenseRepository.insert(newExpense);
      } else {
        final updatedExpense = expense.copyWith(
          description: description,
          amount: amount,
          date: date,
          categoryId: categoryId,
          isFixed: isFixedResult,
          isVariable: isVariableResult,
        );
        await expenseRepository.update(updatedExpense);
      }
      if (!mounted) {
        return;
      }
      await _loadData();
      if (!mounted) {
        return;
      }
      _showMessage(
        expense == null
            ? 'Despesa salva com sucesso.'
            : 'Despesa atualizada com sucesso.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Não foi possível salvar a despesa.');
    }
  }

  Future<void> _deleteExpense(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir despesa'),
          content: Text('Deseja excluir "${expense.description}"?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    try {
      await expenseRepository.deleteExpenseCompletely(expense);
      await _loadData();
      _showMessage('Despesa excluída com sucesso.');
    } catch (error) {
      _showMessage('Não foi possível excluir a despesa.');
    }
  }

  Future<void> _editFixedExpense(FixedExpenseWithStatus item) async {
    if (item.isProjected) {
      _showMessage('Nos meses futuros a despesa fixa só recebe baixa.');
      return;
    }
    await _openExpenseForm(expense: item.expense);
  }

  Future<void> _deleteFixedExpense(FixedExpenseWithStatus item) async {
    if (item.isProjected) {
      _showMessage('Nos meses futuros a despesa fixa só recebe baixa.');
      return;
    }
    await _deleteExpense(item.expense);
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

  Category? _categoryById(String id) {
    for (final category in categories) {
      if (category.id == id) {
        return category;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Despesas'),
        actions: [
          IconButton(
            onPressed: _loadData,
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CategoriesScreen()),
              );
              await _loadData();
            },
            tooltip: 'Gerenciar categorias',
            icon: const Icon(Icons.category_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openExpenseForm(),
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Despesa'),
      ),
      body: RefreshIndicator(
        color: AppColors.orange,
        onRefresh: _loadData,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 240),
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
          const SizedBox(height: 150),
          Text(errorMessage!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _loadData,
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
        const SizedBox(height: 12),
        _buildSummaryBox(),
        const SizedBox(height: 20),
        _buildCardsSection(),
        const SizedBox(height: 20),
        _buildFixedExpensesSection(),
        const SizedBox(height: 20),
        _buildVariableFixedExpensesSection(),
        const SizedBox(height: 20),
        _buildVariableExpensesSection(),
        const SizedBox(height: 90),
      ],
    );
  }

  Widget _buildMonthSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
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
    );
  }

  // ── Resumo do mês (inclui cartões no total) ──
  Widget _buildSummaryBox() {
    final paid = jaPago;
    final progress = totalDespesas <= 0
        ? 0.0
        : (paid / totalDespesas).clamp(0.0, 1.0);
    final isAllPaid = totalDespesas > 0 && paid >= totalDespesas - 0.01;

    String informative;
    if (totalDespesas <= 0) {
      informative = 'Nenhuma despesa para este mês.';
    } else if (isAllPaid) {
      informative = 'Tudo pago! Você está em dia.';
    } else if (progress >= 0.75) {
      informative = 'Quase tudo pago, falta pouco!';
    } else if (progress >= 0.5) {
      informative = 'Mais da metade paga. Continue assim!';
    } else if (paid > 0) {
      informative = 'Você ainda não pagou boa parte das despesas.';
    } else {
      informative = 'Nenhuma despesa paga ainda neste mês.';
    }

    final needsMoreMoney = totalDespesas > 0 && saldoDisponivel < 0;
    final Color accent = isAllPaid ? AppColors.green : AppColors.orange;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumo do mês',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            _summaryLine(
              'Despesas fixas',
              _currency(totalFixed),
              AppColors.orange,
            ),
            const SizedBox(height: 6),
            _summaryLine(
              'Despesas fixas variáveis',
              _currency(totalVariableFixed),
              AppColors.darkOrange,
            ),
            const SizedBox(height: 6),
            _summaryLine(
              'Despesas diárias (Pix/Débito)',
              _currency(totalVariable),
              AppColors.blue,
            ),
            const SizedBox(height: 6),
            _summaryLine(
              'Cartões (faturas do mês)',
              _currency(cardDueTotal),
              AppColors.purple,
            ),
            const Divider(height: 20),
            _summaryLine(
              'Total de despesas',
              _currency(totalDespesas),
              AppColors.red,
            ),
            const SizedBox(height: 8),
            _summaryLine('Já pago', _currency(paid), AppColors.green),
            const SizedBox(height: 8),
            _summaryLine('Falta pagar', _currency(faltante), AppColors.orange),
            const SizedBox(height: 8),
            _summaryLine(
              'Receitas do mês',
              _currency(incomeTotal),
              AppColors.blue,
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              borderRadius: BorderRadius.circular(20),
              backgroundColor: accent.withValues(alpha: .15),
              color: accent,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  isAllPaid ? Icons.check_circle : Icons.info_outline,
                  color: accent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    informative,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (needsMoreMoney) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_outlined,
                    color: AppColors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Precisa de mais dinheiro para pagar todas as despesas.',
                      style: TextStyle(
                        color: AppColors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryLine(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // ── Bloco Cartões (agora conta no resumo do mês) ──
  Widget _buildCardsSection() {
    if (cardDisplays.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(
                Icons.credit_card_outlined,
                color: AppColors.orange,
                size: 40,
              ),
              const SizedBox(height: 8),
              const Text(
                'Nenhum cartão cadastrado.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              const Text(
                'Cadastre um cartão na aba Cartões.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.gray),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cartões',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'As faturas do mês estão incluídas no Total de despesas '
                  'do Resumo do mês acima. Para detalhes das compras, '
                  'acesse a aba Cartões.',
              style: TextStyle(color: AppColors.gray, fontSize: 12),
            ),
            const SizedBox(height: 14),
            ...cardDisplays.map(_buildCardTile),
            const Divider(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total das faturas do mês',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  _currency(cardDueTotal),
                  style: const TextStyle(
                    color: AppColors.purple,
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

  Widget _buildCardTile(_CardDisplay display) {
    final color = Color(display.card.colorValue);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.credit_card, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  display.card.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              _statusChip(
                isPaid: display.isPaid,
                paidLabel: 'Pago',
                pendingLabel: 'Em aberto',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Limite: ${_currency(display.limit)}'),
          Text('Disponível: ${_currency(display.available)}'),
          Text(
            'Fatura a pagar: ${_currency(display.openInvoice)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ── Bloco Despesas Fixas (com valor fixo) ──
  Widget _buildFixedExpensesSection() {
    final items = _regularFixedItems;
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Despesas fixas',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...items.map(_buildFixedExpenseTile),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total despesas fixas',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  _currency(totalFixed),
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

  // ── Bloco Despesas Fixas Variáveis (água, luz...) ──
  Widget _buildVariableFixedExpensesSection() {
    final items = _variableFixedItems;
    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(
                Icons.water_drop_outlined,
                color: AppColors.orange,
                size: 40,
              ),
              const SizedBox(height: 8),
              const Text(
                'Nenhuma despesa fixa variável neste mês.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              const Text(
                'Crie uma despesa fixa e marque "Valor varia todo mês" '
                    '(ex.: conta de água, luz).',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.gray),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Despesas fixas variáveis',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Água, luz etc. — informe o valor de cada mês.',
              style: TextStyle(color: AppColors.gray, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ...items.map(_buildFixedExpenseTile),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total despesas fixas variáveis',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  _currency(totalVariableFixed),
                  style: const TextStyle(
                    color: AppColors.darkOrange,
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

  Widget _buildFixedExpenseTile(FixedExpenseWithStatus item) {
    final expense = item.expense;
    final category = _categoryById(expense.categoryId);
    final isVariable = expense.isVariable;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        backgroundColor: AppColors.softRed,
        child: Icon(Icons.arrow_upward, color: AppColors.red),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              expense.description,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          _statusChip(isPaid: item.isPaid),
        ],
      ),
      subtitle: Text(
        '${category?.name ?? 'Categoria desconhecida'}'
            ' • ${DateFormat('dd/MM/yyyy').format(expense.date)}'
            '${isVariable ? ' • Valor varia todo mês' : ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isVariable)
            Text(
              expense.amount > 0
                  ? _currency(expense.amount)
                  : 'Informar valor',
              style: TextStyle(
                color: expense.amount > 0 ? AppColors.red : AppColors.gray,
                fontSize: 13,
                fontWeight: expense.amount > 0
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            )
          else
            Text(
              _currency(expense.amount),
              style: const TextStyle(
                color: AppColors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (option) {
              if (option == 'value') {
                _informVariableValue(item);
              }
              if (option == 'toggle') {
                _toggleFixedPaid(item);
              }
              if (option == 'edit') {
                _editFixedExpense(item);
              }
              if (option == 'delete') {
                _deleteFixedExpense(item);
              }
            },
            itemBuilder: (context) => [
              if (isVariable)
                PopupMenuItem(
                  value: 'value',
                  child: Text(
                    expense.amount > 0
                        ? 'Alterar valor do mês'
                        : 'Informar valor do mês',
                  ),
                ),
              PopupMenuItem(
                value: 'toggle',
                child: Text(
                  item.isPaid ? 'Marcar como pendente' : 'Marcar como pago',
                ),
              ),
              if (!item.isProjected)
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
              if (!item.isProjected)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Excluir',
                    style: TextStyle(color: AppColors.red),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bloco Outras despesas (Pix/Débito) ──
  Widget _buildVariableExpensesSection() {
    if (variableExpenses.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.orange,
                size: 40,
              ),
              const SizedBox(height: 8),
              const Text(
                'Nenhuma despesa avulsa neste mês.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              const Text(
                'Despesas pagas via Pix, débito ou dinheiro aparecem aqui.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.gray),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Outras despesas (Pix/Débito)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...variableExpenses.map(_buildVariableExpenseTile),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total despesas variáveis',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  _currency(totalVariable),
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

  Widget _buildVariableExpenseTile(Expense expense) {
    final category = _categoryById(expense.categoryId);
    final isPaid = expense.status == 'paid';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        backgroundColor: AppColors.softRed,
        child: Icon(Icons.arrow_upward, color: AppColors.red),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              expense.description,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          _statusChip(isPaid: isPaid),
        ],
      ),
      subtitle: Text(
        '${category?.name ?? 'Categoria desconhecida'}'
            ' • ${DateFormat('dd/MM/yyyy').format(expense.date)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _currency(expense.amount),
            style: const TextStyle(
              color: AppColors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (option) {
              if (option == 'toggle') {
                _toggleVariablePaid(expense);
              }
              if (option == 'edit') {
                _openExpenseForm(expense: expense);
              }
              if (option == 'delete') {
                _deleteExpense(expense);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle',
                child: Text(
                  isPaid ? 'Marcar como pendente' : 'Marcar como pago',
                ),
              ),
              const PopupMenuItem(value: 'edit', child: Text('Editar')),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Excluir',
                  style: TextStyle(color: AppColors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip({
    required bool isPaid,
    String paidLabel = 'Pago',
    String pendingLabel = 'Pendente',
  }) {
    final color = isPaid ? AppColors.green : AppColors.orange;
    final label = isPaid ? paidLabel : pendingLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _CardDisplay {
  final CreditCard card;
  final double limit;
  final double available;
  final double openInvoice;
  final bool isPaid;

  const _CardDisplay({
    required this.card,
    required this.limit,
    required this.available,
    required this.openInvoice,
    required this.isPaid,
  });
}