import '../utils/image_url.dart';

class MenuOption {
  const MenuOption({
    required this.id,
    required this.name,
    required this.group,
    this.price = 0,
    this.isRequired = false,
  });

  final String id;
  final String name;
  final String group;
  final double price;
  final bool isRequired;

  factory MenuOption.fromMap(Map<String, dynamic> map) {
    return MenuOption(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      group: map['group'] as String? ?? 'Options',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      isRequired: map['isRequired'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'group': group,
      'price': price,
      'isRequired': isRequired,
    };
  }
}

class MenuItem {
  final int id;
  final int categoryId;
  final String categoryName;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final int? talabatId;
  final bool isAvailable;
  final List<MenuOption> options;

  MenuItem({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    this.talabatId,
    required this.isAvailable,
    this.options = const [],
  });

  /// Backward-compatible alias used by older screens.
  String get category => categoryName;

  /// Local Almenupro image path or absolute URL (`image_url` in API JSON).
  String get image_url => imageUrl;

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] is int ? json['id'] as int : int.parse(json['id'].toString()),
      categoryId: json['category_id'] is int
          ? json['category_id'] as int
          : int.parse(json['category_id']?.toString() ?? '0'),
      categoryName: json['category_name']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      price: double.parse(json['price'].toString()),
      imageUrl: normalizeMenuImageUrl(json['image_url'] ?? json['imageUrl']),
      talabatId: json['talabat_id'] is int
          ? json['talabat_id'] as int
          : int.tryParse(json['talabat_id']?.toString() ?? ''),
      isAvailable: json['is_available'] == 1 || json['is_available'] == true,
      options: (json['options'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((option) => MenuOption.fromMap(Map<String, dynamic>.from(option)))
          .toList(),
    );
  }

  factory MenuItem.fromMap(String documentId, Map<String, dynamic> map) {
    final rawOptions = map['options'] as List<dynamic>? ?? [];

    return MenuItem(
      id: int.tryParse(documentId) ?? documentId.hashCode,
      categoryId: map['categoryId'] is int
          ? map['categoryId'] as int
          : int.tryParse(map['categoryId']?.toString() ?? '') ??
              int.tryParse(map['category_id']?.toString() ?? '') ??
              0,
      categoryName:
          (map['categoryName'] ?? map['category_name'] ?? map['category'] ?? '')
              .toString(),
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      price: (map['price'] as num?)?.toDouble() ??
          double.tryParse(map['price']?.toString() ?? '') ??
          0,
      imageUrl: normalizeMenuImageUrl(map['imageUrl'] ?? map['image_url']),
      talabatId: map['talabat_id'] is int
          ? map['talabat_id'] as int
          : int.tryParse(map['talabat_id']?.toString() ?? ''),
      isAvailable: map['is_available'] == 1 ||
          map['is_available'] == true ||
          map['isAvailable'] == true ||
          map['isAvailable'] == 1,
      options: rawOptions
          .whereType<Map>()
          .map((option) => MenuOption.fromMap(Map<String, dynamic>.from(option)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'category_name': categoryName,
      'name': name,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      if (talabatId != null) 'talabat_id': talabatId,
      'is_available': isAvailable ? 1 : 0,
      if (options.isNotEmpty)
        'options': options.map((option) => option.toMap()).toList(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'price': price,
      'imageUrl': imageUrl,
      'categoryName': categoryName,
      'categoryId': categoryId,
      'options': options.map((option) => option.toMap()).toList(),
      'isAvailable': isAvailable,
    };
  }
}
