import 'package:cloud_firestore/cloud_firestore.dart';

import 'cart_item.dart';

enum OrderType {
  delivery,
  pickup;

  String get label => switch (this) {
        OrderType.delivery => 'Delivery',
        OrderType.pickup => 'Pickup',
      };

  static OrderType fromString(String? value) {
    return OrderType.values.firstWhere(
      (type) => type.name == value?.toLowerCase(),
      orElse: () => OrderType.delivery,
    );
  }
}

enum OrderStatus {
  pending,
  confirmed,
  preparing,
  ready,
  delivered,
  cancelled;

  static OrderStatus fromString(String? value) {
    return OrderStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => OrderStatus.pending,
    );
  }

  String get arabicLabel => switch (this) {
        OrderStatus.pending => 'طلب جديد',
        OrderStatus.confirmed => 'تم القبول',
        OrderStatus.preparing => 'في الطريق',
        OrderStatus.ready => 'جاهز للاستلام',
        OrderStatus.delivered => 'تم التوصيل',
        OrderStatus.cancelled => 'ملغي',
      };

  String? get nextActionLabel => switch (this) {
        OrderStatus.pending => 'قبول',
        OrderStatus.confirmed => 'في الطريق',
        OrderStatus.preparing => 'تم التوصيل',
        _ => null,
      };

  OrderStatus? get nextStatus => switch (this) {
        OrderStatus.pending => OrderStatus.confirmed,
        OrderStatus.confirmed => OrderStatus.preparing,
        OrderStatus.preparing => OrderStatus.delivered,
        _ => null,
      };
}

class OrderLineItem {
  const OrderLineItem({
    required this.menuItemId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.selectedOptions,
    this.specialNotes,
  });

  final String menuItemId;
  final String name;
  final double unitPrice;
  final int quantity;
  final List<SelectedOption> selectedOptions;
  final String? specialNotes;

  double get lineTotal => unitPrice * quantity;

  factory OrderLineItem.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['selectedOptions'] as List<dynamic>? ?? [];

    return OrderLineItem(
      menuItemId: map['menuItemId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      unitPrice: (map['unitPrice'] as num?)?.toDouble() ??
          (map['price'] as num?)?.toDouble() ??
          0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      selectedOptions: rawOptions
          .map((option) => SelectedOption.fromMap(option as Map<String, dynamic>))
          .toList(),
      specialNotes: map['specialNotes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'menuItemId': menuItemId,
      'name': name,
      'unitPrice': unitPrice,
      'quantity': quantity,
      'selectedOptions': selectedOptions.map((option) => option.toMap()).toList(),
      if (specialNotes != null && specialNotes!.isNotEmpty)
        'specialNotes': specialNotes,
      'lineTotal': lineTotal,
    };
  }

  factory OrderLineItem.fromCartItem(CartItem cartItem) {
    return OrderLineItem(
      menuItemId: cartItem.menuItem.id.toString(),
      name: cartItem.menuItem.name,
      unitPrice: cartItem.unitPrice,
      quantity: cartItem.quantity,
      selectedOptions: cartItem.selectedOptions,
      specialNotes: cartItem.specialNotes,
    );
  }
}

class Order {
  const Order({
    required this.id,
    required this.customerName,
    required this.phone,
    required this.address,
    required this.items,
    required this.totalPrice,
    required this.orderType,
    required this.status,
    required this.createdAt,
    this.invoiceNumber,
    this.paymentMethod,
  });

  final String id;
  final String customerName;
  final String phone;
  final String address;
  final List<OrderLineItem> items;
  final double totalPrice;
  final OrderType orderType;
  final OrderStatus status;
  final DateTime createdAt;
  final String? invoiceNumber;
  final String? paymentMethod;

  factory Order.fromMap(String id, Map<String, dynamic> map) {
    final rawItems = map['items'] as List<dynamic>? ?? [];

    return Order(
      id: id,
      customerName: map['customerName'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      address: map['address'] as String? ?? '',
      items: rawItems
          .map((item) => OrderLineItem.fromMap(item as Map<String, dynamic>))
          .toList(),
      totalPrice: (map['totalPrice'] as num?)?.toDouble() ?? 0,
      orderType: OrderType.fromString(map['orderType'] as String?),
      status: OrderStatus.fromString(map['status'] as String?),
      createdAt: _parseDateTime(map['createdAt']),
      invoiceNumber: map['invoiceNumber']?.toString(),
      paymentMethod: map['paymentMethod']?.toString(),
    );
  }

  Order copyWith({
    OrderStatus? status,
    String? invoiceNumber,
    String? paymentMethod,
  }) {
    return Order(
      id: id,
      customerName: customerName,
      phone: phone,
      address: address,
      items: items,
      totalPrice: totalPrice,
      orderType: orderType,
      status: status ?? this.status,
      createdAt: createdAt,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerName': customerName,
      'phone': phone,
      'address': address,
      'items': items.map((item) => item.toMap()).toList(),
      'totalPrice': totalPrice,
      'orderType': orderType.label,
      'status': status.name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (invoiceNumber != null && invoiceNumber!.isNotEmpty)
        'invoiceNumber': invoiceNumber,
      if (paymentMethod != null && paymentMethod!.isNotEmpty)
        'paymentMethod': paymentMethod,
    };
  }

  bool get isDemoOrder => id.startsWith('demo-');

  static DateTime _parseDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String) {
      return DateTime.parse(value).toUtc();
    }
    return DateTime.now().toUtc();
  }
}
