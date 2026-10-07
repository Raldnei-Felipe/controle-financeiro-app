import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../models/card_invoice.dart';
import '../../models/category.dart' as app_category;
import '../../models/credit_card.dart';
import '../../models/expense.dart';
import '../../repositories/card_invoice_repository.dart';
import '../../repositories/category_repository.dart';
import '../../repositories/expense_repository.dart';

class CardDetailScreen extends StatefulWidget {
  final CreditCard card;

  const CardDetailScreen({super.key, required this.card});

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  final CardInvoiceRepository invoiceRepository = CardInvoiceRepository();
  final ExpenseRepository expenseRepository = ExpenseRepository();
  final CategoryRepository categoryRepository = CategoryRepository();
  final Uuid uuid = const Uuid();

  List<CardInvoice> invoices = [];
  List<app_category.Category> categories = [];
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
      final loadedInvoices = await invoiceRepository.findByCard(widget.card);
      final loadedCategories = await categoryRepository.findActive();
      if (!mounted) {
        return;
      }
      setState(() {
        invoices = loadedInvoices;
        categories = loadedCategories;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorMessage = 'Não foi possível carregar as faturas.';
        isLoading = false;
      });
    }
  }

  void _changeMonth(int amount) {
    setState(() {
      selectedMonth = DateTime(
        selectedMonth.year,
        selectedMonth.month + amount,
        1,
      );
    });
  }

  CardInvoice? _invoiceForSelectedMonth() {
    for (final invoice in invoices) {
      if (invoice.referenceMonth.year == selectedMonth.year &&
          invoice.referenceMonth.month == selectedMonth.month) {
        return invoice;
      }
    }
    return null;
  }

  Future<void> _addPurchase() async {
    if (categories.isEmpty) {
      _showMessage('Cadastre uma categoria antes de adicionar uma compra.');
      return;
    }
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();
    final installmentsController = TextEditingController(text: '1');
    DateTime purchaseDate = DateTime.now();
    String categoryId = categories.first.id;
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
                  initialDate: purchaseDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: 'Data da compra',
                  cancelText: 'Cancelar',
                  confirmText: 'Confirmar',
                );
                if (pickedDate == null || !dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  purchaseDate = pickedDate;
                });
              }

              void confirmForm() {
                final description = descriptionController.text.trim();
                final normalizedAmount = amountController.text
                    .trim()
                    .replaceAll(',', '.');
                final amount = double.tryParse(normalizedAmount);
                final installmentCount = int.tryParse(
                  installmentsController.text.trim(),
                );
                if (description.isEmpty) {
                  _showMessage('Informe a descrição da compra.');
                  return;
                }
                if (amount == null || amount <= 0) {
                  _showMessage('Informe um valor maior que zero.');
                  return;
                }
                if (installmentCount == null ||
                    installmentCount < 1 ||
                    installmentCount > 48) {
                  _showMessage('Informe de 1 a 48 parcelas.');
                  return;
                }
                final totalCents = (amount * 100).round();
                if (totalCents < installmentCount) {
                  _showMessage(
                    'O valor é pequeno demais para essa quantidade de parcelas.',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop({
                  'description': description,
                  'amount': amount,
                  'date': purchaseDate,
                  'categoryId': categoryId,
                  'installmentCount': installmentCount,
                });
              }

              return AlertDialog(
                title: const Text('Adicionar compra'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: descriptionController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Descrição',
                          hintText: 'Ex.: Compra no mercado',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Valor total com juros',
                          hintText: 'Ex.: 1250,00',
                          prefixText: 'R\$ ',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: installmentsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Número de parcelas',
                          hintText: 'De 1 a 48',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: categoryId,
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                        ),
                        items: categories
                            .whereType<app_category.Category>()
                            .map((category) {
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
                            categoryId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Data da compra'),
                        subtitle: Text(
                          DateFormat('dd/MM/yyyy').format(purchaseDate),
                        ),
                        trailing: TextButton(
                          onPressed: selectDate,
                          child: const Text('Alterar'),
                        ),
                      ),
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
                    child: const Text('Salvar compra'),
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
      final totalAmount = result['amount'] as double;
      final firstDate = result['date'] as DateTime;
      final selectedCategoryId = result['categoryId'] as String;
      final installmentCount = result['installmentCount'] as int;
      final totalCents = (totalAmount * 100).round();
      final baseCents = totalCents ~/ installmentCount;
      final extraCents = totalCents % installmentCount;
      final groupId = installmentCount > 1 ? uuid.v4() : null;
      final createdAt = DateTime.now();
      final installments = <Expense>[];
      for (int index = 0; index < installmentCount; index++) {
        final installmentCents = baseCents + (index < extraCents ? 1 : 0);
        final installmentDate = _dateForInstallment(firstDate, index);
        final installmentDescription = installmentCount == 1
            ? description
            : '$description (${index + 1}/$installmentCount)';
        installments.add(
          Expense(
            id: uuid.v4(),
            description: installmentDescription,
            amount: installmentCents / 100,
            date: installmentDate,
            categoryId: selectedCategoryId,
            isFixed: false,
            status: 'pending',
            createdAt: createdAt,
            paymentMethod: 'card',
            cardId: widget.card.id,
            installmentGroupId: groupId,
            installmentNumber: index + 1,
            installmentCount: installmentCount,
          ),
        );
      }
      await expenseRepository.insertMany(installments);
      if (!mounted) {
        return;
      }
      await _loadData();
      if (!mounted) {
        return;
      }
      _showMessage(
        installmentCount == 1
            ? 'Compra salva e adicionada à fatura.'
            : 'Compra salva em $installmentCount parcelas.',
      );
    } catch (error, stackTrace) {
      debugPrint('Erro ao salvar compra: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      _showMessage('Não foi possível salvar a compra.');
    } finally {
      descriptionController.dispose();
      amountController.dispose();
      installmentsController.dispose();
    }
  }

  DateTime _dateForInstallment(DateTime firstDate, int offset) {
    final targetMonth = DateTime(firstDate.year, firstDate.month + offset, 1);
    final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
    final day = firstDate.day > lastDay ? lastDay : firstDate.day;
    return DateTime(targetMonth.year, targetMonth.month, day);
  }

  // ── NOVO: excluir compra (parcelada exclui o grupo inteiro) ──
  Future<void> _deletePurchase(Expense purchase) async {
    final isParcelada = purchase.installmentCount > 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir compra'),
          content: Text(
            isParcelada
                ? 'Deseja excluir todas as ${purchase.installmentCount} '
                'parcelas de "${purchase.description}"?'
                : 'Deseja excluir "${purchase.description}"?',
          ),
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
      await expenseRepository.deletePurchase(purchase);
      await _loadData();
      _showMessage(
        isParcelada
            ? 'Compra e todas as parcelas excluídas.'
            : 'Compra excluída.',
      );
    } catch (error) {
      _showMessage('Não foi possível excluir a compra.');
    }
  }

  Future<void> _toggleInvoiceStatus(CardInvoice invoice) async {
    final newStatus = !invoice.isPaid;
    try {
      await invoiceRepository.setPaid(invoice: invoice, isPaid: newStatus);
      if (!mounted) {
        return;
      }
      await _loadData();
      if (!mounted) {
        return;
      }
      _showMessage(
        newStatus
            ? 'Fatura marcada como paga.'
            : 'Fatura marcada como pendente.',
      );
    } catch (error) {
      _showMessage('Não foi possível atualizar a fatura.');
    }
  }

  String _currency(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  String _monthLabel(DateTime date) {
    const months = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril',
      'Maio', 'Junho', 'Julho', 'Agosto',
      'Setembro', 'Outubro', 'Novembro', 'Dezembro',
    ];
    return '${months[date.month - 1]} de ${date.year}';
  }

  String _categoryName(String categoryId) {
    for (final category in categories) {
      if (category.id == categoryId) {
        return category.name;
      }
    }
    return 'Categoria desconhecida';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Color(widget.card.colorValue);
    return Scaffold(
      appBar: AppBar(title: Text(widget.card.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPurchase,
        backgroundColor: cardColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Compra'),
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
        physics: AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 240),
          Center(child: CircularProgressIndicator(color: AppColors.orange)),
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
    if (invoices.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          const Icon(
            Icons.receipt_long_outlined,
            color: AppColors.orange,
            size: 54,
          ),
          const SizedBox(height: 14),
          const Text(
            'Ainda não há compras neste cartão.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Adicione uma compra para criar a primeira fatura.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.gray),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _addPurchase,
            child: const Text('Adicionar compra'),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildCardSummary(),
        const SizedBox(height: 16),
        _buildMonthSelector(),
        const SizedBox(height: 16),
        const Text(
          'Fatura',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildSelectedMonthInvoice(),
        const SizedBox(height: 90),
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

  Widget _buildSelectedMonthInvoice() {
    final invoice = _invoiceForSelectedMonth();
    if (invoice == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.orange,
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                'Nenhuma compra neste mês.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Navegue pelos meses para ver as faturas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.gray),
              ),
            ],
          ),
        ),
      );
    }
    return _buildInvoiceCard(invoice);
  }

  Widget _buildCardSummary() {
    final cardColor = Color(widget.card.colorValue);
    return Card(
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.card.issuer,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              widget.card.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Fecha dia ${widget.card.closingDay}'
                  ' • Vence dia ${widget.card.dueDay}',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceCard(CardInvoice invoice) {
    final statusColor = invoice.isPaid ? AppColors.green : AppColors.orange;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  color: AppColors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _monthLabel(invoice.referenceMonth),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  invoice.isPaid ? 'Paga' : 'Pendente',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Vencimento: '
                  '${DateFormat('dd/MM/yyyy').format(invoice.dueDate)}',
            ),
            const SizedBox(height: 4),
            Text(
              _currency(invoice.total),
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 24),
            ...invoice.purchases.map(_buildPurchaseTile),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _toggleInvoiceStatus(invoice),
                child: Text(
                  invoice.isPaid ? 'Marcar como pendente' : 'Marcar como paga',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Compra com menu de excluir ──
  Widget _buildPurchaseTile(Expense purchase) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(purchase.description),
      subtitle: Text(
        '${_categoryName(purchase.categoryId)}'
            ' • ${DateFormat('dd/MM/yyyy').format(purchase.date)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _currency(purchase.amount),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          PopupMenuButton<String>(
            onSelected: (option) {
              if (option == 'delete') {
                _deletePurchase(purchase);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
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
}