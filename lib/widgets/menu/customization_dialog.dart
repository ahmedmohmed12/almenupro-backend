import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/cart_item.dart';
import '../../models/menu_item.dart';
import '../../providers/cart_provider.dart';
import '../../theme/app_theme.dart';

Future<void> showCustomizationDialog(
  BuildContext context,
  MenuItem item,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _CustomizationDialog(item: item),
  );
}

class _CustomizationDialog extends StatefulWidget {
  const _CustomizationDialog({required this.item});

  final MenuItem item;

  @override
  State<_CustomizationDialog> createState() => _CustomizationDialogState();
}

class _CustomizationDialogState extends State<_CustomizationDialog> {
  final _notesController = TextEditingController();
  int _quantity = 1;
  final Map<String, String> _selectedByGroup = {};

  @override
  void initState() {
    super.initState();
    final groups = _groupedOptions.keys;
    for (final group in groups) {
      final options = _groupedOptions[group]!;
      final requiredOption = options.firstWhere(
        (option) => option.isRequired,
        orElse: () => options.first,
      );
      _selectedByGroup[group] = requiredOption.id;
    }
  }

  Map<String, List<MenuOption>> get _groupedOptions {
    final grouped = <String, List<MenuOption>>{};
    for (final option in widget.item.options) {
      grouped.putIfAbsent(option.group, () => []).add(option);
    }
    return grouped;
  }

  List<SelectedOption> get _selectedOptions {
    return _selectedByGroup.entries.map((entry) {
      final option = widget.item.options.firstWhere(
        (item) => item.id == entry.value,
      );
      return SelectedOption(
        group: option.group,
        name: option.name,
        price: option.price,
      );
    }).toList();
  }

  double get _unitPrice {
    final modifiers =
        _selectedOptions.fold<double>(0, (sum, option) => sum + option.price);
    return widget.item.price + modifiers;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _addToCart() {
    context.read<CartProvider>().addItem(
          menuItem: widget.item,
          selectedOptions: _selectedOptions,
          quantity: _quantity,
          specialNotes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.item.name} added to cart')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.item.name),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.item.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              ..._groupedOptions.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: entry.value.map((option) {
                          final selected =
                              _selectedByGroup[entry.key] == option.id;
                          final label = option.price > 0
                              ? '${option.name} (+\$${option.price.toStringAsFixed(2)})'
                              : option.name;

                          return ChoiceChip(
                            label: Text(label),
                            selected: selected,
                            onSelected: (_) {
                              setState(() {
                                _selectedByGroup[entry.key] = option.id;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Special notes',
                  hintText: 'No onions, extra sauce...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _quantity > 1
                        ? () => setState(() => _quantity--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(
                    '$_quantity',
                    style: theme.textTheme.titleLarge,
                  ),
                  IconButton(
                    onPressed: () => setState(() => _quantity++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              Text(
                'Total: \$${(_unitPrice * _quantity).toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppTheme.brandPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _addToCart,
          child: const Text('Add to cart'),
        ),
      ],
    );
  }
}
