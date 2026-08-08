enum KitchenStatus {
  active,
  paused,
  archived;

  static KitchenStatus fromString(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'paused':
        return KitchenStatus.paused;
      case 'archived':
        return KitchenStatus.archived;
      default:
        return KitchenStatus.active;
    }
  }

  String get apiValue => name;
}

class Kitchen {
  const Kitchen({
    required this.id,
    required this.name,
    this.nameAr = '',
    this.nameEn = '',
    this.code = '',
    this.status = KitchenStatus.active,
    this.isDefault = false,
    this.restaurantId,
    this.sortOrder = 0,
    this.kdsEnabled = true,
  });

  final String id;
  final String name;
  final String nameAr;
  final String nameEn;
  final String code;
  final KitchenStatus status;
  final bool isDefault;
  final String? restaurantId;
  final int sortOrder;
  final bool kdsEnabled;

  bool get isActive => status == KitchenStatus.active;

  String localizedName(String localeCode) {
    if (localeCode.startsWith('en')) {
      if (nameEn.trim().isNotEmpty) return nameEn.trim();
      if (nameAr.trim().isNotEmpty) return nameAr.trim();
      return name;
    }
    if (nameAr.trim().isNotEmpty) return nameAr.trim();
    if (nameEn.trim().isNotEmpty) return nameEn.trim();
    return name;
  }

  factory Kitchen.fromMap(Map<String, dynamic> map) {
    return Kitchen(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      nameAr: map['name_ar']?.toString() ?? map['nameAr']?.toString() ?? '',
      nameEn: map['name_en']?.toString() ?? map['nameEn']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      status: KitchenStatus.fromString(map['status']?.toString()),
      isDefault: map['is_default'] == true || map['isDefault'] == true,
      restaurantId:
          map['restaurant_id']?.toString() ?? map['restaurantId']?.toString(),
      sortOrder: (map['sort_order'] as num?)?.toInt() ??
          (map['sortOrder'] as num?)?.toInt() ??
          0,
      kdsEnabled: map['kds_enabled'] != false && map['kdsEnabled'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': nameAr.isNotEmpty ? nameAr : name,
      if (nameAr.isNotEmpty) 'name_ar': nameAr,
      if (nameEn.isNotEmpty) 'name_en': nameEn,
      if (code.isNotEmpty) 'code': code,
      'status': status.apiValue,
      'is_default': isDefault,
      'sort_order': sortOrder,
      'kds_enabled': kdsEnabled,
      if (restaurantId != null) 'restaurant_id': restaurantId,
    };
  }

  Kitchen copyWith({
    String? name,
    String? nameAr,
    String? nameEn,
    String? code,
    KitchenStatus? status,
    bool? isDefault,
    int? sortOrder,
    bool? kdsEnabled,
  }) {
    return Kitchen(
      id: id,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      code: code ?? this.code,
      status: status ?? this.status,
      isDefault: isDefault ?? this.isDefault,
      restaurantId: restaurantId,
      sortOrder: sortOrder ?? this.sortOrder,
      kdsEnabled: kdsEnabled ?? this.kdsEnabled,
    );
  }
}
