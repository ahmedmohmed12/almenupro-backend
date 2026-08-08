class DeliveryNotificationRewards {
  const DeliveryNotificationRewards({
    this.earnedCashback = 0,
    this.walletBalance = 0,
    this.walletPromoCode = '',
    this.personalPromoCode = '',
    this.personalPromoDiscount = 0,
  });

  final double earnedCashback;
  final double walletBalance;
  final String walletPromoCode;
  final String personalPromoCode;
  final double personalPromoDiscount;

  factory DeliveryNotificationRewards.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const DeliveryNotificationRewards();
    return DeliveryNotificationRewards(
      earnedCashback: (map['earnedCashback'] as num?)?.toDouble() ?? 0,
      walletBalance: (map['walletBalance'] as num?)?.toDouble() ??
          (map['wallet_balance'] as num?)?.toDouble() ??
          0,
      walletPromoCode: map['walletPromoCode']?.toString() ??
          map['wallet_promo_code']?.toString() ??
          '',
      personalPromoCode: map['personalPromoCode']?.toString() ??
          map['personal_promo_code']?.toString() ??
          '',
      personalPromoDiscount:
          (map['personalPromoDiscount'] as num?)?.toDouble() ??
              (map['personal_promo_discount'] as num?)?.toDouble() ??
              0,
    );
  }
}

class DeliveryNotification {
  const DeliveryNotification({
    required this.customerPhone,
    required this.message,
    this.restaurantWhatsapp = '',
    this.rewards = const DeliveryNotificationRewards(),
  });

  final String customerPhone;
  final String restaurantWhatsapp;
  final String message;
  final DeliveryNotificationRewards rewards;

  factory DeliveryNotification.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const DeliveryNotification(customerPhone: '', message: '');
    }
    return DeliveryNotification(
      customerPhone:
          map['customerPhone']?.toString() ?? map['customer_phone']?.toString() ?? '',
      restaurantWhatsapp: map['restaurantWhatsapp']?.toString() ??
          map['restaurant_whatsapp']?.toString() ??
          '',
      message: map['message']?.toString() ?? '',
      rewards: DeliveryNotificationRewards.fromMap(
        map['rewards'] is Map
            ? Map<String, dynamic>.from(map['rewards'] as Map)
            : null,
      ),
    );
  }

  bool get hasCustomerPhone => customerPhone.trim().isNotEmpty;
  bool get hasMessage => message.trim().isNotEmpty;
}

class OrderStatusUpdateResult {
  const OrderStatusUpdateResult({
    required this.orderId,
    this.deliveryNotification,
  });

  final String orderId;
  final DeliveryNotification? deliveryNotification;
}
