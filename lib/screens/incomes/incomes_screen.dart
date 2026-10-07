import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../models/income.dart';
import '../../repositories/income_repository.dart';

class IncomesScreen extends StatefulWidget {
  const IncomesScreen({super.key});

  @override
  State<IncomesScreen> createState() => _IncomesScreenState();
}

class _IncomesScreenState extends State<IncomesScreen> {
  final IncomeRepository repository = IncomeRepository();
  final Uuid uuid = const Uuid();

  List<Income> incomes = [];
  bool isLoading = true;
  String? errorMessage;

  DateTime selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  @override
  void initState() {
    super.initState();
    _loadIncomes();
  }

  Future<void> _loadIncomes() async {
    if (!mounted) {
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final result = await repository.findByMonth(selectedMonth);

      if (!mounted) {
        return;
      }

      setState(() {
        incomes = result;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage = 'Não foi possível carregar as receitas.';
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

    await _loadIncomes();
  }

  Future<void> _openIncomeForm({Income? income}) async {
    final descriptionController = TextEditingController(
      text: income?.description ?? '',
    );

    final amountController = TextEditingController(
      text: income == null ? '' : income.amount.toStringAsFixed(2),
    );

    DateTime selectedDate = income?.date ?? DateTime.now();
    bool isRecurring = income?.isRecurring ?? false;

    Map<String, Object?>? result;

    try {
      result = await showDialog<Map<String, Object?>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          bool isSaving = false;

          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> selectDate() async {
                final pickedDate = await showDatePicker(
                  context: dialogContext,
                  initialDate: selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: 'Selecione a data da receita',
                  cancelText: 'Cancelar',
                  confirmText: 'Confirmar',
                );

                if (pickedDate == null) {
                  return;
                }

                if (!dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  selectedDate = pickedDate;
                });
              }

              void confirmForm() {
                final description = descriptionController.text.trim();

                final normalizedAmount = amountController.text
                    .trim()
                    .replaceAll(',', '.');

                final amount = double.tryParse(normalizedAmount);

                if (description.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Informe a descrição da receita.'),
                    ),
                  );
                  return;
                }

                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Informe um valor maior que zero.'),
                    ),
                  );
                  return;
                }

                setDialogState(() {
                  isSaving = true;
                });

                Navigator.of(dialogContext).pop({
                  'description': description,
                  'amount': amount,
                  'date': selectedDate,
                  'isRecurring': isRecurring,
                });
              }

              return AlertDialog(
                title: Text(
                  income == null ? 'Adicionar receita' : 'Editar receita',
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
                          hintText: 'Ex.: Salário',
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
                          hintText: 'Ex.: 5000,00',
                          prefixText: 'R\$ ',
                          prefixIcon: Icon(Icons.attach_money),
                        ),
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
                          onPressed: isSaving ? null : selectDate,
                          child: const Text('Alterar'),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Receita recorrente'),
                        subtitle: const Text(
                          'A recorrência será configurada depois.',
                        ),
                        value: isRecurring,
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setDialogState(() {
                                  isRecurring = value;
                                });
                              },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () {
                            Navigator.of(dialogContext).pop();
                          },
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: isSaving ? null : confirmForm,
                    child: isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Salvar'),
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
      final recurring = result['isRecurring'] as bool;

      if (income == null) {
        final newIncome = Income(
          id: uuid.v4(),
          description: description,
          amount: amount,
          date: date,
          isRecurring: recurring,
          status: 'received',
          createdAt: DateTime.now(),
        );

        await repository.insert(newIncome);
      } else {
        final updatedIncome = income.copyWith(
          description: description,
          amount: amount,
          date: date,
          isRecurring: recurring,
        );

        await repository.update(updatedIncome);
      }

      if (!mounted) {
        return;
      }

      await _loadIncomes();

      if (!mounted) {
        return;
      }

      _showMessage(
        income == null
            ? 'Receita salva com sucesso.'
            : 'Receita atualizada com sucesso.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Não foi possível salvar a receita.');
    } finally {
      descriptionController.dispose();
      amountController.dispose();
    }
  }

  Future<void> _deleteIncome(Income income) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir receita'),
          content: Text('Deseja excluir "${income.description}"?'),
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
      await repository.delete(income.id);
      await _loadIncomes();

      _showMessage('Receita excluída com sucesso.');
    } catch (error) {
      _showMessage('Não foi possível excluir a receita.');
    }
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
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];

    return '${months[date.month - 1]} de ${date.year}';
  }

  double get total {
    return incomes.fold<double>(0, (sum, income) => sum + income.amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receitas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openIncomeForm(),
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Receita'),
      ),
      body: RefreshIndicator(
        color: AppColors.orange,
        onRefresh: _loadIncomes,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildMonthSelector(),
            const SizedBox(height: 12),
            _buildTotalCard(),
            const SizedBox(height: 16),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.orange),
                ),
              )
            else if (errorMessage != null)
              _buildError()
            else if (incomes.isEmpty)
              _buildEmptyState()
            else
              ...incomes.map(_buildIncomeCard),
            const SizedBox(height: 90),
          ],
        ),
      ),
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

  Widget _buildTotalCard() {
    final formattedTotal = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    ).format(total);

    return Card(
      color: AppColors.softGreen,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.green,
              child: Icon(Icons.trending_up, color: Colors.white),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Total de receitas',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              formattedTotal,
              style: const TextStyle(
                color: AppColors.green,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomeCard(Income income) {
    final formattedAmount = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    ).format(income.amount);

    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.softGreen,
          child: Icon(Icons.arrow_downward, color: AppColors.green),
        ),
        title: Text(
          income.description,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${DateFormat('dd/MM/yyyy').format(income.date)}'
          '${income.isRecurring ? ' • Recorrente' : ''}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formattedAmount,
              style: const TextStyle(
                color: AppColors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (option) {
                if (option == 'edit') {
                  _openIncomeForm(income: income);
                }

                if (option == 'delete') {
                  _deleteIncome(income);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(value: 'delete', child: Text('Excluir')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              color: AppColors.orange,
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              'Nenhuma receita neste mês.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Toque no botão Receita para cadastrar a primeira.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.gray),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _openIncomeForm(),
              child: const Text('Cadastrar receita'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadIncomes,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
