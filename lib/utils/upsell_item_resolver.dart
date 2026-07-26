import '../models/menu_item.dart';
import '../models/restaurant_settings.dart';

class UpsellItemResolver {
  static const _impulseKeywords = [
    'مشرو',
    'عصير',
    'قهو',
    'شاي',
    'صوص',
    'صلص',
    'سauce',
    'drink',
    'tea',
    'coffee',
    'حلو',
    'dessert',
    'cookie',
    'كوك',
  ];

  static List<MenuItem> impulseBumpItems({
    required List<MenuItem> allItems,
    required RestaurantSettings settings,
    required Set<int> cartItemIds,
  }) {
    if (!settings.smartUpsellEnabled) return const [];

    Iterable<MenuItem> candidates;

    if (settings.impulseBumpItemIds.isNotEmpty) {
      final idSet = settings.impulseBumpItemIds.toSet();
      candidates = allItems.where(
        (item) => idSet.contains(item.id) && item.isAvailable,
      );
    } else {
      candidates = allItems.where(
        (item) =>
            item.isAvailable &&
            item.price > 0 &&
            item.price <= settings.impulseBumpMaxPrice &&
            (_matchesImpulseKeyword(item) || item.price <= 1),
      );
    }

    return candidates
        .where((item) => !cartItemIds.contains(item.id))
        .take(12)
        .toList();
  }

  static bool _matchesImpulseKeyword(MenuItem item) {
    final haystack =
        '${item.categoryName} ${item.name} ${item.nameAr} ${item.nameEn}'
            .toLowerCase();
    return _impulseKeywords.any((keyword) => haystack.contains(keyword));
  }
}
