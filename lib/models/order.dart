import 'package:cloud_firestore/cloud_firestore.dart';

import 'cart_item.dart';
import 'delivery_address_details.dart';
import 'order_platform.dart';

enum OrderType {
  delivery,
  pickup;

  String get label => switch (this) {
        OrderType.delivery => 'Delivery',
        OrderType.pickup => 'Pickup',
      };

  String get labelAr => switch (this) {
        OrderType.delivery => 'توصيل',
        OrderType.pickup => 'استلام',
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

  /// Active orders shown under "الطلبات الجديدة".
  bool get isActiveForAdmin =>
      this == OrderStatus.pending ||
      this == OrderStatus.confirmed ||
      this == OrderStatus.preparing ||
      this == OrderStatus.ready;

  /// Completed orders shown under "الطلبات السابقة".
  bool get isArchivedForAdmin =>
      this == OrderStatus.delivered || this == OrderStatus.cancelled;
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
    this.subtotal,
    this.deliveryFee,
    this.governorate,
    this.areaName,
    this.deliveryZoneId,
    this.addressDetails = const DeliveryAddressDetails(),
    this.orderSource,
    this.externalOrderId,
    this.platformGrossTotal,
    this.platformCommission,
    this.platformCommissionPercent,
    this.promoCode,
    this.promoDiscount,
    this.walletCode,
    this.walletDiscount,
    this.targetKitchenId,
    this.targetKitchenName,
    this.cashierId,
    this.cashierName,
    this.kitchenAssignedByName,
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
  final double? subtotal;
  final double? deliveryFee;
  final String? governorate;
  final String? areaName;
  final String? deliveryZoneId;
  final DeliveryAddressDetails addressDetails;
  final String? orderSource;
  final String? externalOrderId;
  final double? platformGrossTotal;
  final double? platformCommission;
  final double? platformCommissionPercent;
  final String? promoCode;
  final double? promoDiscount;
  final String? walletCode;
  final double? walletDiscount;
  final String? targetKitchenId;
  final String? targetKitchenName;
  final String? cashierId;
  final String? cashierName;
  final String? kitchenAssignedByName;

  String get sourceLabelAr =>
      OrderPlatform.fromStorage(orderSource).arabicLabel;

  String get receivedByLabel {
    final cashier = cashierName?.trim();
    if (cashier != null && cashier.isNotEmpty) return cashier;
    final assigned = kitchenAssignedByName?.trim();
    if (assigned != null && assigned.isNotEmpty) return assigned;
    return '—';
  }

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
      subtotal: (map['subtotal'] as num?)?.toDouble(),
      deliveryFee: (map['deliveryFee'] as num?)?.toDouble() ??
          (map['delivery_fee'] as num?)?.toDouble(),
      governorate: map['governorate']?.toString(),
      areaName: map['areaName']?.toString() ?? map['area_name']?.toString(),
      deliveryZoneId:
          map['deliveryZoneId']?.toString() ?? map['delivery_zone_id']?.toString(),
      addressDetails: DeliveryAddressDetails.fromMap(
        map['addressDetails'] as Map<String, dynamic>? ??
            map['address_details'] as Map<String, dynamic>?,
      ),
      orderSource:
          map['orderSource']?.toString() ?? map['order_source']?.toString(),
      externalOrderId: map['externalOrderId']?.toString() ??
          map['external_order_id']?.toString(),
      platformGrossTotal: (map['platformGrossTotal'] as num?)?.toDouble() ??
          (map['platform_gross_total'] as num?)?.toDouble(),
      platformCommission: (map['platformCommission'] as num?)?.toDouble() ??
          (map['platform_commission'] as num?)?.toDouble(),
      platformCommissionPercent:
          (map['platformCommissionPercent'] as num?)?.toDouble() ??
              (map['platform_commission_percent'] as num?)?.toDouble(),
      promoCode: map['promoCode']?.toString() ?? map['promo_code']?.toString(),
      promoDiscount: (map['promoDiscount'] as num?)?.toDouble() ??
          (map['promo_discount'] as num?)?.toDouble(),
      walletCode: map['walletCode']?.toString() ?? map['wallet_code']?.toString(),
      walletDiscount: (map['walletDiscount'] as num?)?.toDouble() ??
          (map['wallet_discount'] as num?)?.toDouble(),
      targetKitchenId: map['targetKitchenId']?.toString() ??
          map['target_kitchen_id']?.toString(),
      targetKitchenName: map['targetKitchenName']?.toString() ??
          map['target_kitchen_name']?.toString(),
      cashierId: map['cashierId']?.toString() ?? map['cashier_id']?.toString(),
      cashierName:
          map['cashierName']?.toString() ?? map['cashier_name']?.toString(),
      kitchenAssignedByName: _readKitchenAssignedByName(map),
    );
  }

  static String? _readKitchenAssignedByName(Map<String, dynamic> map) {
    final assignment =
        map['kitchenAssignment'] ?? map['kitchen_assignment'];
    if (assignment is Map) {
      final name = assignment['assignedByName']?.toString() ??
          assignment['assigned_by_name']?.toString();
      if (name != null && name.trim().isNotEmpty) return name.trim();
    }
    return null;
  }

  Order copyWith({
    OrderStatus? status,
    String? invoiceNumber,
    String? paymentMethod,
    double? subtotal,
    double? deliveryFee,
    double? totalPrice,
  }) {
    return Order(
      id: id,
      customerName: customerName,
      phone: phone,
      address: address,
      items: items,
      totalPrice: totalPrice ?? this.totalPrice,
      orderType: orderType,
      status: status ?? this.status,
      createdAt: createdAt,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      subtotal: subtotal ?? this.subtotal,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      governorate: governorate,
      areaName: areaName,
      deliveryZoneId: deliveryZoneId,
      addressDetails: addressDetails,
      orderSource: orderSource,
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
      if (subtotal != null) 'subtotal': subtotal,
      if (deliveryFee != null) 'deliveryFee': deliveryFee,
      if (governorate != null && governorate!.isNotEmpty) 'governorate': governorate,
      if (areaName != null && areaName!.isNotEmpty) 'areaName': areaName,
      if (deliveryZoneId != null && deliveryZoneId!.isNotEmpty)
        'deliveryZoneId': deliveryZoneId,
      if (!addressDetails.isEmpty) 'addressDetails': addressDetails.toMap(),
      if (invoiceNumber != null && invoiceNumber!.isNotEmpty)
        'invoiceNumber': invoiceNumber,
      if (paymentMethod != null && paymentMethod!.isNotEmpty)
        'paymentMethod': paymentMethod,
      if (orderSource != null && orderSource!.isNotEmpty) 'orderSource': orderSource,
      if (externalOrderId != null && externalOrderId!.isNotEmpty)
        'externalOrderId': externalOrderId,
      if (platformGrossTotal != null) 'platformGrossTotal': platformGrossTotal,
      if (platformCommission != null) 'platformCommission': platformCommission,
      if (platformCommissionPercent != null)
        'platformCommissionPercent': platformCommissionPercent,
      if (promoCode != null && promoCode!.isNotEmpty) 'promoCode': promoCode,
      if (promoDiscount != null && promoDiscount! > 0) 'promoDiscount': promoDiscount,
      if (walletDiscount != null && walletDiscount! > 0) 'walletDiscount': walletDiscount,
      if (walletDiscount != null && walletDiscount! > 0) 'walletAmount': walletDiscount,
      if (targetKitchenId != null && targetKitchenId!.isNotEmpty)
        'targetKitchenId': targetKitchenId,
      if (targetKitchenName != null && targetKitchenName!.isNotEmpty)
        'targetKitchenName': targetKitchenName,
      if (cashierId != null && cashierId!.isNotEmpty) 'cashierId': cashierId,
      if (cashierName != null && cashierName!.isNotEmpty)
        'cashierName': cashierName,
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
