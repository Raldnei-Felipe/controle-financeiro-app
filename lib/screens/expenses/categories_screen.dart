import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../models/category.dart';
import '../../repositories/category_repository.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final CategoryRepository repository = CategoryRepository();
  final Uuid uuid = const Uuid();

  List<Category> categories = [];
  bool isLoading = true;
  String? errorMessage;

  final List<Color> availableColors = const [
    AppColors.orange,
    AppColors.red,
    AppColors.green,
    AppColors.blue,
    AppColors.purple,
    Colors.teal,
    Colors.pink,
    Colors.brown,
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    if (!mounted) {
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final result = await repository.findAll();

      if (!mounted) {
        return;
      }

      setState(() {
        categories = result;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage = 'Não foi possível carregar as categorias.';
        isLoading = false;
      });
    }
  }

  Future<void> _openCategoryForm({Category? category}) async {
    final nameController = TextEditingController(text: category?.name ?? '');

    int selectedColor =
        category?.colorValue ?? availableColors.first.toARGB32();

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

                if (name.isEmpty) {
                  _showMessage('Informe o nome da categoria.');
                  return;
                }

                Navigator.of(dialogContext)
                    .pop({'name': name, 'colorValue': selectedColor});
              }

              return AlertDialog(
                title: Text(
                  category == null ? 'Nova categoria' : 'Editar categoria',
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nome da categoria',
                        hintText: 'Ex.: Saúde',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Escolha uma cor',
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
                            width: 38,
                            height: 38,
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
                                    size: 20,
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
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
      final colorValue = result['colorValue'] as int;

      final duplicated = categories.any(
        (item) =>
            item.name.toLowerCase() == name.toLowerCase() &&
            item.id != category?.id,
      );

      if (duplicated) {
        _showMessage('Já existe uma categoria com esse nome.');
        return;
      }

      if (category == null) {
        await repository.insert(
          Category(
            id: uuid.v4(),
            name: name,
            colorValue: colorValue,
            isActive: true,
          ),
        );
      } else {
        await repository.update(
          category.copyWith(name: name, colorValue: colorValue),
        );
      }

      if (!mounted) {
        return;
      }

      await _loadCategories();

      if (!mounted) {
        return;
      }

      _showMessage(
        category == null
            ? 'Categoria criada com sucesso.'
            : 'Categoria atualizada com sucesso.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Não foi possível salvar a categoria.');
    }
  }

  Future<void> _deactivateCategory(Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Desativar categoria'),
          content: Text(
            'A categoria "${category.name}" não aparecerá '
            'em novos cadastros. As despesas antigas serão preservadas.',
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
              child: const Text('Desativar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await repository.deactivate(category.id);
      await _loadCategories();

      _showMessage('Categoria desativada.');
    } catch (error) {
      _showMessage('Não foi possível desativar a categoria.');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorias'),
        actions: [
          IconButton(
            onPressed: _loadCategories,
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCategoryForm(),
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Categoria'),
      ),
      body: RefreshIndicator(
        color: AppColors.orange,
        onRefresh: _loadCategories,
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
            onPressed: _loadCategories,
            child: const Text('Tentar novamente'),
          ),
        ],
      );
    }

    final activeCategories = categories
        .where((category) => category.isActive)
        .toList();

    final inactiveCategories = categories
        .where((category) => !category.isActive)
        .toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Categorias ativas',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (activeCategories.isEmpty) _emptyCard('Nenhuma categoria ativa.'),
        ...activeCategories.map(_categoryCard),
        if (inactiveCategories.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'Categorias desativadas',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...inactiveCategories.map(_categoryCard),
        ],
        const SizedBox(height: 90),
      ],
    );
  }

  Widget _categoryCard(Category category) {
    final color = Color(category.colorValue);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .18),
          child: Icon(Icons.category_outlined, color: color),
        ),
        title: Text(
          category.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          category.isActive ? 'Ativa' : 'Desativada',
          style: TextStyle(
            color: category.isActive ? AppColors.green : AppColors.gray,
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (option) {
            if (option == 'edit') {
              _openCategoryForm(category: category);
            }

            if (option == 'deactivate' && category.isActive) {
              _deactivateCategory(category);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Editar')),
            if (category.isActive)
              const PopupMenuItem(
                value: 'deactivate',
                child: Text('Desativar'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(message, style: const TextStyle(color: AppColors.gray)),
        ),
      ),
    );
  }
}
