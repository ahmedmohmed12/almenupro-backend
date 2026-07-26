import '../models/working_hours.dart';
import '../utils/whatsapp_phone.dart';

class RestaurantSettings {
  const RestaurantSettings({
    required this.whatsappNumber,
    required this.workingHours,
    this.whatsappCountryCode = WhatsAppPhone.defaultCountryCode,
    this.whatsappPhone = '',
    this.updatedAt,
  });

  final String whatsappNumber;
  final String whatsappCountryCode;
  final String whatsappPhone;
  final WorkingHoursSettings workingHours;
  final DateTime? updatedAt;

  String get fullWhatsappNumber {
    final combined = WhatsAppPhone.combine(whatsappCountryCode, whatsappPhone);
    if (combined.isNotEmpty) return combined;
    return WhatsAppPhone.digitsOnly(whatsappNumber);
  }

  bool get hasWhatsappNumber => fullWhatsappNumber.isNotEmpty;

  factory RestaurantSettings.defaults() {
    return RestaurantSettings(
      whatsappCountryCode: WhatsAppPhone.defaultCountryCode,
      whatsappPhone: '',
      whatsappNumber: '',
      workingHours: WorkingHoursSettings.defaults(),
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

    return RestaurantSettings(
      whatsappCountryCode: countryCode,
      whatsappPhone: phone,
      whatsappNumber: fullNumber,
      workingHours: WorkingHoursSettings.fromJsonList(
        json['workingHours'] as List<dynamic>? ??
            json['working_hours'] as List<dynamic>?,
      ),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  RestaurantSettings copyWith({
    String? whatsappNumber,
    String? whatsappCountryCode,
    String? whatsappPhone,
    WorkingHoursSettings? workingHours,
    DateTime? updatedAt,
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
    );
  }

  Map<String, dynamic> toJson() => {
        'whatsappCountryCode': whatsappCountryCode,
        'whatsappPhone': whatsappPhone,
        'whatsappNumber': fullWhatsappNumber,
        'workingHours': workingHours.toJsonList(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}
