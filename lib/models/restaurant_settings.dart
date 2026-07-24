import '../models/working_hours.dart';

class RestaurantSettings {
  const RestaurantSettings({
    required this.whatsappNumber,
    required this.workingHours,
    this.updatedAt,
  });

  final String whatsappNumber;
  final WorkingHoursSettings workingHours;
  final DateTime? updatedAt;

  factory RestaurantSettings.defaults() {
    return RestaurantSettings(
      whatsappNumber: '96594774950',
      workingHours: WorkingHoursSettings.defaults(),
    );
  }

  factory RestaurantSettings.fromJson(Map<String, dynamic> json) {
    return RestaurantSettings(
      whatsappNumber:
          json['whatsappNumber']?.toString() ??
          json['whatsapp_number']?.toString() ??
          '96594774950',
      workingHours: WorkingHoursSettings.fromJsonList(
        json['workingHours'] as List<dynamic>? ??
            json['working_hours'] as List<dynamic>?,
      ),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  RestaurantSettings copyWith({
    String? whatsappNumber,
    WorkingHoursSettings? workingHours,
    DateTime? updatedAt,
  }) {
    return RestaurantSettings(
      whatsappNumber: whatsappNumber ?? this.whatsappNumber,
      workingHours: workingHours ?? this.workingHours,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'whatsappNumber': whatsappNumber,
        'workingHours': workingHours.toJsonList(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}
