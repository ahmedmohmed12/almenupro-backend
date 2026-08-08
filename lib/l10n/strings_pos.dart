import 'app_strings.dart';
import 'strings_admin.dart';

/// Cashier POS strings including kitchen routing.
extension AppStringsPos on AppStrings {
  String get posArea => isArabic ? 'المنطقة' : 'Area';
  String get posGovernorate => isArabic ? 'المحافظة' : 'Governorate';
  String get posBlock => isArabic ? 'القطعة' : 'Block';
  String get posStreet => isArabic ? 'الشارع' : 'Street';
  String get posAvenue => isArabic ? 'الجادة' : 'Avenue';
  String get posHouse => isArabic ? 'البيت' : 'House / building';
  String get posPickupAddress =>
      isArabic ? 'استلام من المحل' : 'Pickup from store';
  String get posSelectDeliveryZone => isArabic
      ? 'يرجى اختيار منطقة التوصيل'
      : 'Please select a delivery zone';
  String get posSelectTargetKitchen => isArabic
      ? 'يرجى اختيار المطبخ المستهدف'
      : 'Please select a target kitchen';
  String get posTargetKitchen =>
      isArabic ? 'المطبخ المستهدف' : 'Target kitchen';
  String get posKitchenAutoSuggested => isArabic
      ? 'مقترح تلقائياً حسب منطقة التوصيل'
      : 'Auto-suggested from delivery area';
  String get posKitchenManualOverride => isArabic
      ? 'تجاوز يدوي — تأكد من المطبخ الصحيح'
      : 'Manual override — confirm the correct kitchen';
  String get auto => isArabic ? 'تلقائي' : 'Auto';
  String get posAllKitchens => isArabic ? 'كل المطابخ' : 'All kitchens';
  String get quickPrintKitchen => isArabic ? 'طباعة مطبخ' : 'Print kitchen';
}
