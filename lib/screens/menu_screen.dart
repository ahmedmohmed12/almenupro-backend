import 'package:flutter/material.dart';

import '../models/menu_item.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  late Future<List<MenuItem>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _itemsFuture = ApiService.instance.fetchItems();
  }

  Future<void> _reload() async {
    setState(() {
      _itemsFuture = ApiService.instance.fetchItems();
    });
    await _itemsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.brandBackground,
      appBar: AppBar(
        title: const Text('قائمة الطعام'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<MenuItem>>(
        future: _itemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.brandMaroon),
            );
          }

          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return _ErrorState(
              message: 'لا توجد أصناف متاحة حالياً',
              onRetry: _reload,
            );
          }

          return RefreshIndicator(
            color: AppTheme.brandMaroon,
            onRefresh: _reload,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 720;
                final crossAxisCount = isWide ? 3 : 2;

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: isWide ? 0.78 : 0.72,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    return _MenuItemCard(item: items[index]);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  const _MenuItemCard({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: _MenuItemImage(imageUrl: item.imageUrl),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.categoryName.isNotEmpty)
                    Text(
                      item.categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.brandMaroon,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      item.description.isNotEmpty
                          ? item.description
                          : 'لا يوجد وصف',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                            height: 1.3,
                          ),
                    ),
                  ),
                  Text(
                    '${item.price.toStringAsFixed(3)} د.ك',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.brandOrange,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItemImage extends StatelessWidget {
  const _MenuItemImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return _placeholder();
    }

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: AppTheme.brandSurface,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.brandMaroon,
          ),
        );
      },
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppTheme.brandSurface,
      alignment: Alignment.center,
      child: const Icon(
        Icons.restaurant,
        size: 42,
        color: AppTheme.brandMaroon,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 56,
              color: AppTheme.brandMaroon,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
