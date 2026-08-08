import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/menu_item.dart';

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  String? _restaurantId;
  String? _restaurantSlug;

  List<CartItem> get items => List.unmodifiable(_items);

  String? get restaurantId => _restaurantId;
  String? get restaurantSlug => _restaurantSlug;

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get totalPrice =>
      _items.fold(0, (sum, item) => sum + item.totalPrice);

  bool get isEmpty => _items.isEmpty;

  bool get hasRestaurantScope =>
      _restaurantId != null && _restaurantSlug != null;

  bool matchesRestaurant({required String restaurantId, required String slug}) {
    if (!hasRestaurantScope) return true;
    return _restaurantId == restaurantId &&
        _restaurantSlug == slug.trim().toLowerCase();
  }

  void setRestaurantScope({
    required String restaurantId,
    required String slug,
  }) {
    final cleanSlug = slug.trim().toLowerCase();
    if (_restaurantId == restaurantId && _restaurantSlug == cleanSlug) {
      return;
    }
    _restaurantId = restaurantId;
    _restaurantSlug = cleanSlug;
    if (_items.isNotEmpty) {
      _items.clear();
    }
    notifyListeners();
  }

  void addMenuItem(
    MenuItem menuItem, {
    int quantity = 1,
    String? restaurantId,
    String? restaurantSlug,
  }) {
    if (restaurantId != null &&
        restaurantSlug != null &&
        restaurantSlug.trim().isNotEmpty) {
      if (!matchesRestaurant(
        restaurantId: restaurantId,
        slug: restaurantSlug,
      )) {
        setRestaurantScope(
          restaurantId: restaurantId,
          slug: restaurantSlug,
        );
      } else if (!hasRestaurantScope) {
        _restaurantId = restaurantId;
        _restaurantSlug = restaurantSlug.trim().toLowerCase();
      }
    }

    final existingIndex =
        _items.indexWhere((item) => item.menuItem.id == menuItem.id);

    if (existingIndex != -1) {
      final existing = _items[existingIndex];
      _items[existingIndex] = existing.copyWith(
        quantity: existing.quantity + quantity,
      );
    } else {
      _items.add(
        CartItem(
          id: '${menuItem.id}_${DateTime.now().microsecondsSinceEpoch}',
          menuItem: menuItem,
          selectedOptions: const [],
          quantity: quantity,
        ),
      );
    }
    notifyListeners();
  }

  void addItem({
    required MenuItem menuItem,
    required List<SelectedOption> selectedOptions,
    required int quantity,
    String? specialNotes,
    String? restaurantId,
    String? restaurantSlug,
  }) {
    if (restaurantId != null &&
        restaurantSlug != null &&
        restaurantSlug.trim().isNotEmpty) {
      if (!matchesRestaurant(
        restaurantId: restaurantId,
        slug: restaurantSlug,
      )) {
        setRestaurantScope(
          restaurantId: restaurantId,
          slug: restaurantSlug,
        );
      } else if (!hasRestaurantScope) {
        _restaurantId = restaurantId;
        _restaurantSlug = restaurantSlug.trim().toLowerCase();
      }
    }

    _items.add(
      CartItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        menuItem: menuItem,
        selectedOptions: selectedOptions,
        quantity: quantity,
        specialNotes: specialNotes,
      ),
    );
    notifyListeners();
  }

  void removeItem(String cartItemId) {
    _items.removeWhere((item) => item.id == cartItemId);
    notifyListeners();
  }

  void updateQuantity(String cartItemId, int quantity) {
    if (quantity <= 0) {
      removeItem(cartItemId);
      return;
    }

    final index = _items.indexWhere((item) => item.id == cartItemId);
    if (index == -1) {
      return;
    }

    _items[index] = _items[index].copyWith(quantity: quantity);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  void resetScope() {
    _items.clear();
    _restaurantId = null;
    _restaurantSlug = null;
    notifyListeners();
  }
}
