import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../models/category.dart';
import '../../repositories/category_repository.dart';
import '../../repositories/recurring_repository.dart';
import '../../services/recurring_service.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  final RecurringRepository repository = RecurringRepository();
  final CategoryRepository categoryRepository = CategoryRepository();
  final RecurringService recurringService = RecurringService();

  List<Map<String, Object?>> rules = [];
  List<Category> categories = [];

  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      await recurringService.generateDueTransactions();

      final loadedRules = await repository.findAll();
      final loadedCategories = await categoryRepository.findActive();

      if (!mounted) return;

      setState(() {
        rules = loadedRules;
        categories = loadedCategories;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Não foi possível carregar as recorrências.';
        isLoading = false;
      });
    }
  }

  Future<void> _addRule() async {
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();

    String transactionType = 'expense';
    String? categoryId = categories.isEmpty ? null : categories.first.id;
    bool isFixed = true;
    DateTime startDate = DateTime.now();

    Map<String, Object?>? result;

    try {
      result = await showDialog<Map<String, Object?>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> selectDate() async {
                final picked = await showDatePicker(
                  context: dialogContext,
                  initialDate: startDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: 'Data do primeiro lançamento',
                );

                if (picked == null || !dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  startDate = picked;
                });
              }

              void save() {
                final description = descriptionController.text.trim();

                final amount = double.tryParse(
                  amountController.text.trim().replaceAll(',', '.'),
                );

                if (description.isEmpty) {
                  _showMessage('Informe uma descrição.');
                  return;
                }

                if (amount == null || amount <= 0) {
                  _showMessage('Informe um valor maior que zero.');
                  return;
                }

                if (transactionType == 'expense' && categoryId == null) {
                  _showMessage('Cadastre uma categoria antes de continuar.');
                  return;
                }

                Navigator.of(dialogContext).pop({
                  'description': description,
                  'amount': amount,
                  'type': transactionType,
                  'categoryId': categoryId,
                  'isFixed': isFixed,
                  'startDate': startDate,
                });
              }

              return AlertDialog(
                title: const Text('Nova recorrência'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: transactionType,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de lançamento',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'expense',
                            child: Text('Despesa'),
                          ),
                          DropdownMenuItem(
                            value: 'income',
                            child: Text('Receita'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            transactionType = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Descrição',
                          hintText: 'Ex.: Aluguel ou salário',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Valor mensal',
                          prefixText: 'R\$ ',
                        ),
                      ),
                      if (transactionType == 'expense') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: categoryId,
                          decoration: const InputDecoration(
                            labelText: 'Categoria',
                          ),
                          items: categories.map((category) {
                            return DropdownMenuItem<String>(
                              value: category.id,
                              child: Text(category.name),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              categoryId = value;
                            });
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Despesa fixa'),
                          value: isFixed,
                          onChanged: (value) {
                            setDialogState(() {
                              isFixed = value;
                            });
                          },
                        ),
                      ],
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Data do primeiro lançamento'),
                        subtitle: Text(
                          DateFormat('dd/MM/yyyy').format(startDate),
                        ),
                        trailing: TextButton(
                          onPressed: selectDate,
                          child: const Text('Alterar'),
                        ),
                      ),
                      const Text(
                        'Depois, o lançamento se repetirá '
                        'mensalmente no mesmo dia.',
                        style: TextStyle(color: AppColors.gray, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(onPressed: save, child: const Text('Salvar')),
                ],
              );
            },
          );
        },
      );

      if (result == null || !mounted) return;

      await repository.insert(
        id: const Uuid().v4(),
        transactionType: result['type'] as String,
        description: result['description'] as String,
        amount: result['amount'] as double,
        categoryId: result['categoryId'] as String?,
        isFixed: result['isFixed'] as bool,
        startDate: result['startDate'] as DateTime,
      );

      await _loadData();

      if (!mounted) return;
      _showMessage('Recorrência salva.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Não foi possível salvar a recorrência.');
    } finally {
      descriptionController.dispose();
      amountController.dispose();
    }
  }

  Future<void> _deactivate(String id) async {
    await repository.deactivate(id);
    await _loadData();

    if (!mounted) return;
    _showMessage('Recorrência desativada.');
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorrências mensais'),
        actions: [
          IconButton(
            onPressed: _loadData,
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRule,
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Recorrência'),
      ),
      body: RefreshIndicator(onRefresh: _loadData, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return ListView(
        physics: AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 230),
          Center(child: CircularProgressIndicator(color: AppColors.orange)),
        ],
      );
    }

    if (errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 140),
          Text(errorMessage!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _loadData,
            child: const Text('Tentar novamente'),
          ),
        ],
      );
    }

    if (rules.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 130),
          Icon(Icons.event_repeat, size: 56, color: AppColors.orange),
          SizedBox(height: 14),
          Text(
            'Nenhuma recorrência cadastrada.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Cadastre uma receita ou despesa mensal.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: rules.map(_ruleCard).toList(),
    );
  }

  Widget _ruleCard(Map<String, Object?> rule) {
    final active = (rule['is_active'] as num).toInt() == 1;
    final type = rule['transaction_type'] as String;
    final date = DateTime.parse(rule['next_due_date'] as String);
    final amount = (rule['amount'] as num).toDouble();

    final categoryId = rule['category_id'] as String?;
    String categoryName = '';

    for (final category in categories) {
      if (category.id == categoryId) {
        categoryName = ' • ${category.name}';
        break;
      }
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: type == 'income'
              ? AppColors.softGreen
              : AppColors.softRed,
          child: Icon(
            type == 'income' ? Icons.trending_up : Icons.event_repeat,
            color: type == 'income' ? AppColors.green : AppColors.red,
          ),
        ),
        title: Text(rule['description'] as String),
        subtitle: Text(
          '${type == 'income' ? 'Receita' : 'Despesa'}'
          '$categoryName'
          ' • Próximo lançamento: ${DateFormat('dd/MM/yyyy').format(date)}'
          '${active ? '' : ' • Desativada'}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              NumberFormat.currency(
                locale: 'pt_BR',
                symbol: 'R\$',
              ).format(amount),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (active)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'deactivate') {
                    _deactivate(rule['id'] as String);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'deactivate', child: Text('Desativar')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
