import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'card_detail_screen.dart';
import '../../core/theme/app_theme.dart';
import '../../models/credit_card.dart';
import '../../repositories/card_repository.dart';
import '../../repositories/card_invoice_repository.dart';

class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  final CardRepository repository = CardRepository();
  final CardInvoiceRepository invoiceRepository = CardInvoiceRepository();
  final Uuid uuid = const Uuid();

  final List<Color> availableColors = const [
    AppColors.orange,
    AppColors.blue,
    AppColors.green,
    AppColors.purple,
    AppColors.red,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
  ];

  List<CreditCard> cards = [];
  // Limite disponível por cartão (limite - comprometido).
  final Map<String, double> availableByCard = {};
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    if (!mounted) {
      return;
    }
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final result = await repository.findAll();
      // Calcula o disponível de cada cartão em paralelo.
      final availables = await Future.wait(
        result.map((card) => invoiceRepository.committedAmount(card)),
      );
      final map = <String, double>{};
      for (int i = 0; i < result.length; i++) {
        final card = result[i];
        final committed = availables[i];
        final available = (card.creditLimit - committed)
            .clamp(0.0, card.creditLimit);
        map[card.id] = available;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        cards = result;
        availableByCard
          ..clear()
          ..addAll(map);
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorMessage = 'Não foi possível carregar os cartões.';
        isLoading = false;
      });
    }
  }

  Future<void> _openCardForm({CreditCard? card}) async {
    final nameController = TextEditingController(text: card?.name ?? '');
    final issuerController = TextEditingController(text: card?.issuer ?? '');
    final limitController = TextEditingController(
      text: card == null ? '' : card.creditLimit.toStringAsFixed(2),
    );
    final closingDayController = TextEditingController(
      text: card?.closingDay.toString() ?? '',
    );
    final dueDayController = TextEditingController(
      text: card?.dueDay.toString() ?? '',
    );
    int selectedColor = card?.colorValue ?? availableColors.first.toARGB32();
    Map<String, Object?>? result;
    try {
      result = await showDialog<Map<String, Object?>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              void confirmForm() {
                final name = nameController.text.trim();
                final issuer = issuerController.text.trim();
                final normalizedLimit = limitController.text.trim().replaceAll(
                  ',',
                  '.',
                );
                final limit = double.tryParse(normalizedLimit);
                final closingDay = int.tryParse(
                  closingDayController.text.trim(),
                );
                final dueDay = int.tryParse(dueDayController.text.trim());
                if (name.isEmpty) {
                  _showMessage('Informe o nome do cartão.');
                  return;
                }
                if (issuer.isEmpty) {
                  _showMessage('Informe o banco ou emissor.');
                  return;
                }
                if (limit == null || limit <= 0) {
                  _showMessage('Informe um limite maior que zero.');
                  return;
                }
                if (closingDay == null || closingDay < 1 || closingDay > 31) {
                  _showMessage('O dia de fechamento deve estar entre 1 e 31.');
                  return;
                }
                if (dueDay == null || dueDay < 1 || dueDay > 31) {
                  _showMessage('O dia de vencimento deve estar entre 1 e 31.');
                  return;
                }
                Navigator.of(dialogContext).pop({
                  'name': name,
                  'issuer': issuer,
                  'limit': limit,
                  'closingDay': closingDay,
                  'dueDay': dueDay,
                  'colorValue': selectedColor,
                });
              }

              return AlertDialog(
                title: Text(
                  card == null ? 'Adicionar cartão' : 'Editar cartão',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nome do cartão',
                          hintText: 'Ex.: Cartão principal',
                          prefixIcon: Icon(Icons.credit_card),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: issuerController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Banco ou emissor',
                          hintText: 'Ex.: Banco Central',
                          prefixIcon: Icon(Icons.account_balance_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: limitController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Limite total',
                          hintText: 'Ex.: 5000,00',
                          prefixText: 'R\$ ',
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: closingDayController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Fechamento',
                                hintText: 'Dia',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: dueDayController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Vencimento',
                                hintText: 'Dia',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Cor do cartão',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: availableColors.map((color) {
                          final isSelected = selectedColor == color.toARGB32();
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedColor = color.toARGB32();
                              });
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.text
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 18,
                              )
                                  : null,
                            ),
                          );
                        }).toList(),
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
      final name = result['name'] as String;
      final issuer = result['issuer'] as String;
      final limit = result['limit'] as double;
      final closingDay = result['closingDay'] as int;
      final dueDay = result['dueDay'] as int;
      final colorValue = result['colorValue'] as int;
      final duplicateName = cards.any(
            (existingCard) =>
        existingCard.name.toLowerCase() == name.toLowerCase() &&
            existingCard.id != card?.id,
      );
      if (duplicateName) {
        _showMessage('Já existe um cartão com esse nome.');
        return;
      }
      if (card == null) {
        final newCard = CreditCard(
          id: uuid.v4(),
          name: name,
          issuer: issuer,
          creditLimit: limit,
          closingDay: closingDay,
          dueDay: dueDay,
          colorValue: colorValue,
          isActive: true,
          createdAt: DateTime.now(),
        );
        await repository.insert(newCard);
      } else {
        final updatedCard = card.copyWith(
          name: name,
          issuer: issuer,
          creditLimit: limit,
          closingDay: closingDay,
          dueDay: dueDay,
          colorValue: colorValue,
        );
        await repository.update(updatedCard);
      }
      if (!mounted) {
        return;
      }
      await _loadCards();
      if (!mounted) {
        return;
      }
      _showMessage(
        card == null
            ? 'Cartão salvo com sucesso.'
            : 'Cartão atualizado com sucesso.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Não foi possível salvar o cartão.');
    } finally {
      nameController.dispose();
      issuerController.dispose();
      limitController.dispose();
      closingDayController.dispose();
      dueDayController.dispose();
    }
  }

  Future<void> _changeCardStatus(CreditCard card) async {
    final actionLabel = card.isActive ? 'desativar' : 'reativar';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(card.isActive ? 'Desativar cartão' : 'Reativar cartão'),
          content: Text('Deseja $actionLabel o cartão "${card.name}"?'),
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
              child: Text(card.isActive ? 'Desativar' : 'Reativar'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    try {
      if (card.isActive) {
        await repository.deactivate(card.id);
      } else {
        await repository.reactivate(card.id);
      }
      await _loadCards();
      _showMessage(card.isActive ? 'Cartão desativado.' : 'Cartão reativado.');
    } catch (error) {
      _showMessage('Não foi possível atualizar o cartão.');
    }
  }

  // ── NOVO: excluir cartão definitivamente (com compras e faturas) ──
  Future<void> _deleteCard(CreditCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir cartão'),
          content: Text(
            'Deseja excluir definitivamente o cartão "${card.name}"? '
                'Todas as compras e faturas vinculadas a ele também serão '
                'excluídas. Essa ação não pode ser desfeita.',
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
      await repository.delete(card);
      await _loadCards();
      _showMessage('Cartão excluído com sucesso.');
    } catch (error) {
      _showMessage('Não foi possível excluir o cartão.');
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

  String _currency(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cartões'),
        actions: [
          IconButton(
            onPressed: _loadCards,
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCardForm(),
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Cartão'),
      ),
      body: RefreshIndicator(
        color: AppColors.orange,
        onRefresh: _loadCards,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return ListView(
        physics: AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 250),
          Center(child: CircularProgressIndicator(color: AppColors.orange)),
        ],
      );
    }
    if (errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 180),
          Text(errorMessage!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _loadCards,
            child: const Text('Tentar novamente'),
          ),
        ],
      );
    }
    final activeCards = cards.where((card) => card.isActive).toList();
    final inactiveCards = cards.where((card) => !card.isActive).toList();
    if (cards.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          const Icon(
            Icons.credit_card_outlined,
            size: 64,
            color: AppColors.orange,
          ),
          const SizedBox(height: 16),
          const Text(
            'Nenhum cartão cadastrado.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cadastre um cartão para manter os dados '
                'de limite, fechamento e vencimento.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.gray),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => _openCardForm(),
            child: const Text('Cadastrar cartão'),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Cartões ativos',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...activeCards.map(_buildCard),
        if (inactiveCards.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'Cartões desativados',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...inactiveCards.map(_buildCard),
        ],
        const SizedBox(height: 90),
      ],
    );
  }

  Widget _buildCard(CreditCard card) {
    final color = Color(card.colorValue);
    final available = availableByCard[card.id] ?? card.creditLimit;
    final used = card.creditLimit <= 0
        ? 0.0
        : ((card.creditLimit - available) / card.creditLimit).clamp(0.0, 1.0);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            color: color,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.credit_card, color: Colors.white),
                    const Spacer(),
                    Text(
                      card.issuer,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  card.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                // Limite total
                Text(
                  'Limite total: ${_currency(card.creditLimit)}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 4),
                // Disponível (limite - comprometido)
                Text(
                  'Disponível: ${_currency(available)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                // Barra de uso do limite
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: used,
                    minHeight: 6,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CardDetailScreen(card: card),
                ),
              );
              if (!mounted) {
                return;
              }
              await _loadCards();
            },
            leading: const Icon(Icons.event_available_outlined),
            title: Text(
              'Fecha dia ${card.closingDay}  •  '
                  'Vence dia ${card.dueDay}',
            ),
            subtitle: Text(card.isActive ? 'Ativo' : 'Desativado'),
            trailing: PopupMenuButton<String>(
              onSelected: (option) {
                if (option == 'edit') {
                  _openCardForm(card: card);
                }
                if (option == 'status') {
                  _changeCardStatus(card);
                }
                if (option == 'delete') {
                  _deleteCard(card);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(
                  value: 'status',
                  child: Text(card.isActive ? 'Desativar' : 'Reativar'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Excluir',
                    style: TextStyle(color: AppColors.red),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}