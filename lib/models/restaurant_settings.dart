import 'loyalty_cashback.dart';
import 'payment_method_config.dart';
import 'pos_role.dart';
import 'sales_platform_config.dart';
import 'working_hours.dart';
import '../utils/whatsapp_phone.dart';

class RestaurantSettings {
  const RestaurantSettings({
    required this.whatsappNumber,
    required this.workingHours,
    this.whatsappCountryCode = WhatsAppPhone.defaultCountryCode,
    this.whatsappPhone = '',
    this.updatedAt,
    this.smartUpsellEnabled = true,
    this.freeDeliveryThreshold = 0,
    this.impulseBumpItemIds = const [],
    this.impulseBumpMaxPrice = 2,
    this.smartRecommendationsEnabled = true,
    this.smartClosingEnabled = true,
    this.logoUrl = '',
    this.restaurantDescription = '',
    this.cashbackType = CashbackType.percentage,
    this.cashbackValue = 0,
    this.minOrderForLoyalty = 0,
    this.paymentMethods = const [],
    this.salesPlatforms = const [],
    this.posRoles = const [],
    this.posAutoLockMinutes = 5,
    this.notificationEmail = '',
    this.notifyOnNewOrderEmail = true,
    this.notifyOnShiftCloseEmail = false,
  });

  final String whatsappNumber;
  final String whatsappCountryCode;
  final String whatsappPhone;
  final WorkingHoursSettings workingHours;
  final DateTime? updatedAt;
  final bool smartUpsellEnabled;
  final double freeDeliveryThreshold;
  final List<int> impulseBumpItemIds;
  final double impulseBumpMaxPrice;
  final bool smartRecommendationsEnabled;
  final bool smartClosingEnabled;
  final String logoUrl;
  final String restaurantDescription;
  final CashbackType cashbackType;
  final double cashbackValue;
  final double minOrderForLoyalty;
  final List<PaymentMethodConfig> paymentMethods;
  final List<SalesPlatformConfig> salesPlatforms;
  final List<PosRole> posRoles;
  final int posAutoLockMinutes;
  final String notificationEmail;
  final bool notifyOnNewOrderEmail;
  final bool notifyOnShiftCloseEmail;

  String get fullWhatsappNumber {
    final combined = WhatsAppPhone.combine(whatsappCountryCode, whatsappPhone);
    if (combined.isNotEmpty) return combined;
    return WhatsAppPhone.digitsOnly(whatsappNumber);
  }

  bool get hasWhatsappNumber => fullWhatsappNumber.isNotEmpty;

  bool get hasFreeDeliveryGoal =>
      smartUpsellEnabled && freeDeliveryThreshold > 0;

  bool qualifiesForFreeDelivery(double subtotal) =>
      hasFreeDeliveryGoal && subtotal >= freeDeliveryThreshold;

  /// Applies free-delivery threshold: returns 0 when subtotal qualifies.
  double effectiveDeliveryFee({
    required double subtotal,
    required double zoneDeliveryFee,
  }) {
    if (zoneDeliveryFee <= 0) return 0;
    if (qualifiesForFreeDelivery(subtotal)) return 0;
    return zoneDeliveryFee;
  }

  bool get hasClosingAndRewards =>
      smartClosingEnabled && smartUpsellEnabled;

  bool get loyaltyEnabled =>
      smartClosingEnabled && cashbackValue > 0;

  List<PaymentMethodConfig> get configuredPaymentMethods =>
      PaymentMethodCatalog.mergeWithDefaults(paymentMethods);

  List<SalesPlatformConfig> get resolvedSalesPlatforms =>
      PlatformCatalog.mergeWithDefaults(salesPlatforms);

  List<PosRole> get resolvedPosRoles {
    if (posRoles.isEmpty) return PosRole.defaults();
    return posRoles;
  }

  factory RestaurantSettings.defaults() {
    return RestaurantSettings(
      whatsappCountryCode: WhatsAppPhone.defaultCountryCode,
      whatsappPhone: '',
      whatsappNumber: '',
      workingHours: WorkingHoursSettings.defaults(),
      paymentMethods: PaymentMethodConfig.defaults(),
      salesPlatforms: SalesPlatformConfig.defaults(),
      posRoles: PosRole.defaults(),
    );
  }

  factory RestaurantSettings.fromJson(Map<String, dynamic> json) {
    final legacyNumber =
        json['whatsappNumber']?.toString() ?? json['whatsapp_number']?.toString() ?? '';
    final explicitCountry = WhatsAppPhone.digitsOnly(
      json['whatsappCountryCode']?.toString() ??
          json['whatsapp_country_code']?.toString() ??
          '',
    );
    final explicitPhone = WhatsAppPhone.digitsOnly(
      json['whatsappPhone']?.toString() ?? json['whatsapp_phone']?.toString() ?? '',
    );

    String countryCode = explicitCountry.isNotEmpty
        ? explicitCountry
        : WhatsAppPhone.defaultCountryCode;
    String phone = explicitPhone;
    String fullNumber = WhatsAppPhone.digitsOnly(legacyNumber);

    if (phone.isNotEmpty) {
      fullNumber = WhatsAppPhone.combine(countryCode, phone);
    } else if (fullNumber.isNotEmpty) {
      final split = WhatsAppPhone.split(fullNumber);
      countryCode = split.countryCode;
      phone = split.phone;
    }

    final rawBumpIds = json['impulseBumpItemIds'] as List<dynamic>? ??
        json['impulse_bump_item_ids'] as List<dynamic>? ??
        [];

    final rawPaymentMethods = json['paymentMethods'] as List<dynamic>? ??
        json['payment_methods'] as List<dynamic>? ??
        [];
    final rawSalesPlatforms = json['salesPlatforms'] as List<dynamic>? ??
        json['sales_platforms'] as List<dynamic>? ??
        [];
    final rawPosRoles = json['posRoles'] as List<dynamic>? ??
        json['pos_roles'] as List<dynamic>? ??
        [];

    return RestaurantSettings(
      whatsappCountryCode: countryCode,
      whatsappPhone: phone,
      whatsappNumber: fullNumber,
      workingHours: WorkingHoursSettings.fromJsonList(
        json['workingHours'] as List<dynamic>? ??
            json['working_hours'] as List<dynamic>?,
      ),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      smartUpsellEnabled: json['smartUpsellEnabled'] != false,
      freeDeliveryThreshold:
          (json['freeDeliveryThreshold'] as num?)?.toDouble() ??
              (json['free_delivery_threshold'] as num?)?.toDouble() ??
              0,
      impulseBumpItemIds: rawBumpIds
          .map((id) => int.tryParse(id.toString()))
          .whereType<int>()
          .toList(),
      impulseBumpMaxPrice:
          (json['impulseBumpMaxPrice'] as num?)?.toDouble() ??
              (json['impulse_bump_max_price'] as num?)?.toDouble() ??
              2,
      smartRecommendationsEnabled: json['smartRecommendationsEnabled'] != false,
      smartClosingEnabled: json['smartClosingEnabled'] != false &&
          json['smart_closing_enabled'] != false,
      logoUrl: json['logoUrl']?.toString() ?? json['logo_url']?.toString() ?? '',
      restaurantDescription: json['restaurantDescription']?.toString() ??
          json['restaurant_description']?.toString() ??
          json['description']?.toString() ??
          '',
      cashbackType: CashbackType.fromStorage(
        json['cashbackType']?.toString() ?? json['cashback_type']?.toString(),
      ),
      cashbackValue: (json['cashbackValue'] as num?)?.toDouble() ??
          (json['cashback_value'] as num?)?.toDouble() ??
          0,
      minOrderForLoyalty: (json['minOrderForLoyalty'] as num?)?.toDouble() ??
          (json['min_order_for_loyalty'] as num?)?.toDouble() ??
          0,
      paymentMethods: rawPaymentMethods
          .whereType<Map>()
          .map((row) => PaymentMethodConfig.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      salesPlatforms: rawSalesPlatforms
          .whereType<Map>()
          .map((row) => SalesPlatformConfig.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      posRoles: rawPosRoles
          .whereType<Map>()
          .map((row) => PosRole.fromJson(Map<String, dynamic>.from(row)))
          .where((role) => role.id.isNotEmpty)
          .toList(),
      posAutoLockMinutes: (json['posAutoLockMinutes'] as num?)?.toInt() ??
          (json['pos_auto_lock_minutes'] as num?)?.toInt() ??
          5,
      notificationEmail: json['notificationEmail']?.toString() ??
          json['notification_email']?.toString() ??
          '',
      notifyOnNewOrderEmail: json['notifyOnNewOrderEmail'] != false,
      notifyOnShiftCloseEmail: json['notifyOnShiftCloseEmail'] == true,
    );
  }

  RestaurantSettings copyWith({
    String? whatsappNumber,
    String? whatsappCountryCode,
    String? whatsappPhone,
    WorkingHoursSettings? workingHours,
    DateTime? updatedAt,
    bool? smartUpsellEnabled,
    double? freeDeliveryThreshold,
    List<int>? impulseBumpItemIds,
    double? impulseBumpMaxPrice,
    bool? smartRecommendationsEnabled,
    bool? smartClosingEnabled,
    String? logoUrl,
    String? restaurantDescription,
    CashbackType? cashbackType,
    double? cashbackValue,
    double? minOrderForLoyalty,
    List<PaymentMethodConfig>? paymentMethods,
    List<SalesPlatformConfig>? salesPlatforms,
    List<PosRole>? posRoles,
    int? posAutoLockMinutes,
    String? notificationEmail,
    bool? notifyOnNewOrderEmail,
    bool? notifyOnShiftCloseEmail,
  }) {
    final nextCountry = whatsappCountryCode ?? this.whatsappCountryCode;
    final nextPhone = whatsappPhone ?? this.whatsappPhone;
    final nextFull = WhatsAppPhone.combine(nextCountry, nextPhone);

    return RestaurantSettings(
      whatsappCountryCode: nextCountry,
      whatsappPhone: nextPhone,
      whatsappNumber: nextFull.isNotEmpty
          ? nextFull
          : (whatsappNumber ?? this.whatsappNumber),
      workingHours: workingHours ?? this.workingHours,
      updatedAt: updatedAt ?? this.updatedAt,
      smartUpsellEnabled: smartUpsellEnabled ?? this.smartUpsellEnabled,
      freeDeliveryThreshold: freeDeliveryThreshold ?? this.freeDeliveryThreshold,
      impulseBumpItemIds: impulseBumpItemIds ?? this.impulseBumpItemIds,
      impulseBumpMaxPrice: impulseBumpMaxPrice ?? this.impulseBumpMaxPrice,
      smartRecommendationsEnabled:
          smartRecommendationsEnabled ?? this.smartRecommendationsEnabled,
      smartClosingEnabled: smartClosingEnabled ?? this.smartClosingEnabled,
      logoUrl: logoUrl ?? this.logoUrl,
      restaurantDescription: restaurantDescription ?? this.restaurantDescription,
      cashbackType: cashbackType ?? this.cashbackType,
      cashbackValue: cashbackValue ?? this.cashbackValue,
      minOrderForLoyalty: minOrderForLoyalty ?? this.minOrderForLoyalty,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      salesPlatforms: salesPlatforms ?? this.salesPlatforms,
      posRoles: posRoles ?? this.posRoles,
      posAutoLockMinutes: posAutoLockMinutes ?? this.posAutoLockMinutes,
      notificationEmail: notificationEmail ?? this.notificationEmail,
      notifyOnNewOrderEmail: notifyOnNewOrderEmail ?? this.notifyOnNewOrderEmail,
      notifyOnShiftCloseEmail:
          notifyOnShiftCloseEmail ?? this.notifyOnShiftCloseEmail,
    );
  }

  Map<String, dynamic> toJson() => {
        'whatsappCountryCode': whatsappCountryCode,
        'whatsappPhone': whatsappPhone,
        'whatsappNumber': fullWhatsappNumber,
        'workingHours': workingHours.toJsonList(),
        'smartUpsellEnabled': smartUpsellEnabled,
        'freeDeliveryThreshold': freeDeliveryThreshold,
        'impulseBumpItemIds': impulseBumpItemIds,
        'impulseBumpMaxPrice': impulseBumpMaxPrice,
        'smartRecommendationsEnabled': smartRecommendationsEnabled,
        'smartClosingEnabled': smartClosingEnabled,
        'logoUrl': logoUrl,
        'restaurantDescription': restaurantDescription,
        'cashbackType': cashbackType.storageValue,
        'cashbackValue': cashbackValue,
        'minOrderForLoyalty': minOrderForLoyalty,
        'paymentMethods': configuredPaymentMethods.map((m) => m.toJson()).toList(),
        'salesPlatforms': resolvedSalesPlatforms.map((p) => p.toJson()).toList(),
        'posRoles': resolvedPosRoles.map((role) => role.toJson()).toList(),
        'posAutoLockMinutes': posAutoLockMinutes,
        'notificationEmail': notificationEmail,
        'notifyOnNewOrderEmail': notifyOnNewOrderEmail,
        'notifyOnShiftCloseEmail': notifyOnShiftCloseEmail,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}
