import 'admin_role.dart';

class Restaurant {
  const Restaurant({
    required this.id,
    required this.slug,
    required this.name,
    this.status = 'active',
    this.createdAt,
  });

  final String id;
  final String slug;
  final String name;
  final String status;
  final DateTime? createdAt;

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    return Restaurant(
      id: json['id']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'name': name,
        'status': status,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };
}

class AdminSession {
  const AdminSession({
    required this.token,
    required this.role,
    this.restaurantId,
    this.restaurantName,
  });

  final String token;
  final AdminRole role;
  final String? restaurantId;
  final String? restaurantName;

  bool get isSuperAdmin => role.isSuperAdmin;
  bool get isRestaurantAdmin => role.isRestaurantAdmin;

  factory AdminSession.fromJson(Map<String, dynamic> json) {
    return AdminSession(
      token: json['token']?.toString() ?? '',
      role: AdminRole.fromStorageKey(json['role']?.toString()) ??
          AdminRole.restaurantAdmin,
      restaurantId: json['restaurantId']?.toString(),
      restaurantName: json['restaurantName']?.toString(),
    );
  }
}
