import 'app_strings.dart';

/// Admin / Super Admin chrome, navigation, tables, restaurants.
extension AppStringsAdmin on AppStrings {
  String get save => isArabic ? 'حفظ' : 'Save';
  String get delete => isArabic ? 'حذف' : 'Delete';
  String get edit => isArabic ? 'تعديل' : 'Edit';
  String get add => isArabic ? 'إضافة' : 'Add';
  String get retry => isArabic ? 'إعادة المحاولة' : 'Retry';
  String get confirm => isArabic ? 'تأكيد' : 'Confirm';
  String get done => isArabic ? 'تم' : 'Done';
  String get logout => isArabic ? 'تسجيل الخروج' : 'Log out';
  String get account => isArabic ? 'الحساب' : 'Account';
  String get menu => isArabic ? 'القائمة' : 'Menu';
  String get loading => isArabic ? 'جاري التحميل...' : 'Loading...';
  String get search => isArabic ? 'بحث' : 'Search';
  String get notesOptional => isArabic ? 'ملاحظات (اختياري)' : 'Notes (optional)';
  String get yes => isArabic ? 'نعم' : 'Yes';
  String get no => isArabic ? 'لا' : 'No';

  String get superAdminWelcome =>
      isArabic ? 'لوحة AlMenuPro — Super Admin' : 'AlMenuPro — Super Admin';
  String welcomeRestaurant(String name) =>
      isArabic ? 'مرحباً بك، $name' : 'Welcome, $name';
  String get welcomeGeneric => isArabic ? 'مرحباً بك' : 'Welcome';
  String get superAdminHint => isArabic
      ? 'اختر المطعم من القائمة لإدارة المنيو والإعدادات'
      : 'Select a restaurant to manage menu and settings';
  String get newOrdersTooltip =>
      isArabic ? 'الطلبات الجديدة' : 'New orders';
  String welcomeCashierPos(String label) => label;

  String get navPos => isArabic ? 'نقطة البيع POS' : 'POS';
  String get navOrders => isArabic ? 'الطلبات' : 'Orders';
  String get navKitchen => isArabic ? 'المطبخ' : 'Kitchen';
  String get kitchenMonitorTitle =>
      isArabic ? 'مراقب المطبخ' : 'Kitchen monitor';
  String get kitchenMonitorSubtitle => isArabic
      ? 'الطلبات المرسلة للمطبخ — تتحدث تلقائياً كل 3 ثوانٍ'
      : 'Orders sent to kitchen — auto-refreshes every 3 seconds';
  String get kitchenEmptyTitle =>
      isArabic ? 'لا توجد طلبات في المطبخ' : 'No kitchen tickets yet';
  String get kitchenEmptyHint => isArabic
      ? 'عند إرسال طلب للمطبخ من شاشة الطلبات سيظهر هنا فوراً'
      : 'Orders appear here as soon as they are sent to kitchen';
  String get unassignedKitchen =>
      isArabic ? 'بدون مطبخ' : 'Unassigned kitchen';
  String get navKitchens => isArabic ? 'المطابخ' : 'Kitchens';
  String get kitchensPanelTitle =>
      isArabic ? 'إدارة المطابخ' : 'Kitchen management';
  String get kitchensPanelSubtitle => isArabic
      ? 'أنشئ مطابخ متعددة واربطها بمناطق التوصيل.'
      : 'Create multiple kitchens and map them to delivery zones.';
  String get markReady => isArabic ? 'جاهز' : 'Ready';
  String get markDelivered => isArabic ? 'تم التوصيل' : 'Delivered';
  String get newKitchenTicket =>
      isArabic ? 'تذكرة مطبخ جديدة' : 'New kitchen ticket';
  String get incomingOrdersBar =>
      isArabic ? 'طلبات جديدة بانتظار المعالجة' : 'New orders awaiting action';
  String get websiteMenuSource =>
      isArabic ? 'منيو الموقع' : 'Website menu';
  String get navCustomers => isArabic ? 'العملاء' : 'Customers';
  String get navMenu =>
      isArabic ? 'إدارة المنيو والأصناف' : 'Menu & items';
  String get navDeliveryZones =>
      isArabic ? 'مناطق التوصيل ورسومها' : 'Delivery zones & fees';
  String get navSettings =>
      isArabic ? 'إعدادات المحل والواتساب' : 'Store & WhatsApp settings';
  String get tableManagementDisabledError => isArabic
      ? 'إدارة الطاولات غير مفعّلة لهذا المطعم'
      : 'Table management is disabled for this restaurant';
  String get unexpectedError =>
      isArabic ? 'حدث خطأ غير متوقع' : 'An unexpected error occurred';
}
