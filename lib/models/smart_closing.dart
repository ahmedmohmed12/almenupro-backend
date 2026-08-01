import 'order.dart';

class SmartClosingRewards {
  const SmartClosingRewards({
    this.earnedCashback = 0,
    this.welcomeDiscountForNextOrder = 0,
    this.walletBalance = 0,
    this.isFirstOrder = false,
    this.qualifiesForCashback = false,
  });

  final double earnedCashback;
  final double welcomeDiscountForNextOrder;
  final double walletBalance;
  final bool isFirstOrder;
  final bool qualifiesForCashback;

  factory SmartClosingRewards.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SmartClosingRewards();
    return SmartClosingRewards(
      earnedCashback: (map['earnedCashback'] as num?)?.toDouble() ?? 0,
      welcomeDiscountForNextOrder:
          (map['welcomeDiscountForNextOrder'] as num?)?.toDouble() ??
              (map['welcome_discount_for_next_order'] as num?)?.toDouble() ??
              0,
      walletBalance: (map['walletBalance'] as num?)?.toDouble() ??
          (map['wallet_balance'] as num?)?.toDouble() ??
          0,
      isFirstOrder: map['isFirstOrder'] == true || map['is_first_order'] == true,
      qualifiesForCashback:
          map['qualifiesForCashback'] == true || map['qualifies_for_cashback'] == true,
    );
  }

  bool get hasAnyReward =>
      earnedCashback > 0 || welcomeDiscountForNextOrder > 0;
}

class SmartClosingPayload {
  const SmartClosingPayload({
    this.phase = 'checkout',
    this.urgencyType = 'standard',
    this.messageAr = '',
    this.messageEn = '',
    this.estimatedDeliveryMinutes = 30,
    this.estimatedDeliveryMaxMinutes = 45,
    this.estimatedDeliveryLabelAr = '',
    this.estimatedDeliveryLabelEn = '',
    this.orderType = 'delivery',
    this.rewards = const SmartClosingRewards(),
    this.postCheckoutMessageAr = '',
    this.postCheckoutMessageEn = '',
    this.projectedCashback = 0,
  });

  final String phase;
  final String urgencyType;
  final String messageAr;
  final String messageEn;
  final int estimatedDeliveryMinutes;
  final int estimatedDeliveryMaxMinutes;
  final String estimatedDeliveryLabelAr;
  final String estimatedDeliveryLabelEn;
  final String orderType;
  final SmartClosingRewards rewards;
  final String postCheckoutMessageAr;
  final String postCheckoutMessageEn;
  final double projectedCashback;

  String messageFor(String localeCode) =>
      localeCode.startsWith('ar') ? messageAr : messageEn;

  String etaLabelFor(String localeCode) => localeCode.startsWith('ar')
      ? estimatedDeliveryLabelAr
      : estimatedDeliveryLabelEn;

  String postCheckoutMessageFor(String localeCode) =>
      localeCode.startsWith('ar') ? postCheckoutMessageAr : postCheckoutMessageEn;

  factory SmartClosingPayload.fromMap(Map<String, dynamic> map) {
    return SmartClosingPayload(
      phase: map['phase']?.toString() ?? 'checkout',
      urgencyType: map['urgencyType']?.toString() ??
          map['urgency_type']?.toString() ??
          'standard',
      messageAr: map['messageAr']?.toString() ?? map['message_ar']?.toString() ?? '',
      messageEn: map['messageEn']?.toString() ?? map['message_en']?.toString() ?? '',
      estimatedDeliveryMinutes:
          (map['estimatedDeliveryMinutes'] as num?)?.toInt() ??
              (map['estimated_delivery_minutes'] as num?)?.toInt() ??
              30,
      estimatedDeliveryMaxMinutes:
          (map['estimatedDeliveryMaxMinutes'] as num?)?.toInt() ??
              (map['estimated_delivery_max_minutes'] as num?)?.toInt() ??
              45,
      estimatedDeliveryLabelAr:
          map['estimatedDeliveryLabelAr']?.toString() ??
              map['estimated_delivery_label_ar']?.toString() ??
              '',
      estimatedDeliveryLabelEn:
          map['estimatedDeliveryLabelEn']?.toString() ??
              map['estimated_delivery_label_en']?.toString() ??
              '',
      orderType: map['orderType']?.toString() ?? map['order_type']?.toString() ?? 'delivery',
      rewards: SmartClosingRewards.fromMap(
        map['rewards'] is Map
            ? Map<String, dynamic>.from(map['rewards'] as Map)
            : null,
      ),
      postCheckoutMessageAr: map['postCheckoutMessageAr']?.toString() ??
          map['post_checkout_message_ar']?.toString() ??
          '',
      postCheckoutMessageEn: map['postCheckoutMessageEn']?.toString() ??
          map['post_checkout_message_en']?.toString() ??
          '',
      projectedCashback: (map['projectedCashback'] as num?)?.toDouble() ??
          (map['projected_cashback'] as num?)?.toDouble() ??
          0,
    );
  }
}

class OrderCreationResult {
  const OrderCreationResult({
    required this.order,
    this.smartClosing,
  });

  final Order order;
  final SmartClosingPayload? smartClosing;
}
