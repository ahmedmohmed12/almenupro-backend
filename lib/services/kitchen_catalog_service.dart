import 'package:flutter/foundation.dart';

import '../models/kitchen.dart';

/// Shared kitchen list so delivery zones pick up newly created kitchens.
class KitchenCatalogService extends ChangeNotifier {
  KitchenCatalogService._();

  static final KitchenCatalogService instance = KitchenCatalogService._();

  List<Kitchen> _kitchens = const [];

  List<Kitchen> get kitchens => List.unmodifiable(_kitchens);

  void publish(List<Kitchen> kitchens) {
    _kitchens = List<Kitchen>.from(kitchens);
    notifyListeners();
  }
}
