import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/menu_item.dart';
import '../../theme/app_theme.dart';
import '../network_menu_image.dart';

class CheckoutImpulseBumps extends StatelessWidget {
  const CheckoutImpulseBumps({
    super.key,
    required this.items,
    required this.localeCode,
    required this.strings,
    required this.onAddItem,
  });

  final List<MenuItem> items;
  final String localeCode;
  final AppStrings strings;
  final ValueChanged<MenuItem> onAddItem;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                color: AppTheme.brandOrange,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.impulseBumpsTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.brandMaroon,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return _ImpulseBumpCard(
                item: item,
                localeCode: localeCode,
                strings: strings,
                onAdd: () => onAddItem(item),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _ImpulseBumpCard extends StatelessWidget {
  const _ImpulseBumpCard({
    required this.item,
    required this.localeCode,
    required this.strings,
    required this.onAdd,
  });

  final MenuItem item;
  final String localeCode;
  final AppStrings strings;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final name = item.localizedName(localeCode);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAdd,
        child: Container(
          width: 118,
          decoration: BoxDecoration(
            border: Border.all(
              color: AppTheme.brandMaroon.withValues(alpha: 0.12),
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.imageUrl.isNotEmpty)
                      NetworkMenuImage(
                        imageUrl: item.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    else
                      _placeholder(),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Material(
                        color: AppTheme.brandOrange,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onAdd,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.price.toStringAsFixed(3)} ${strings.currency}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.brandMaroon,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppTheme.brandMaroon.withValues(alpha: 0.06),
      child: const Icon(Icons.restaurant, color: AppTheme.brandMaroon),
    );
  }
}
