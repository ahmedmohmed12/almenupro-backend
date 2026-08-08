import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/locale_provider.dart';

class AppStrings {
  const AppStrings(this.localeCode);

  final String localeCode;

  bool get isArabic => localeCode.startsWith('ar');

  static AppStrings of(BuildContext context) {
    final locale = context.watch<LocaleProvider>().localeCode;
    return AppStrings(locale);
  }

  String get all => isArabic ? 'الكل' : 'All';
  String get picksForYou =>
      isArabic ? 'اختيارات على ذوقك 🔥' : 'Picks for You 🔥';
  String get menuTagline => isArabic ? 'قائمة الطعام' : 'Menu';
  String menuTaglineFor(String restaurantName) =>
      isArabic ? 'قائمة الطعام — $restaurantName' : 'Menu — $restaurantName';
  String get defaultTagline =>
      isArabic ? 'قائمة الطعام — ميني بايتس وكوكيز' : 'Menu — Mini bites & cookies';
  String get refresh => isArabic ? 'تحديث' : 'Refresh';
  String get noDescription => isArabic ? 'لا يوجد وصف' : 'No description';
  String get noItemsInCategory =>
      isArabic ? 'لا توجد أصناف في هذا التصنيف' : 'No items in this category';
  String get noItemsAvailable =>
      isArabic ? 'لا توجد أصناف متاحة حالياً' : 'No items available right now';
  String get restaurantNotFound =>
      isArabic ? 'المطعم غير موجود أو الرابط غير صحيح' : 'Restaurant not found or invalid link';
  String addedToCart(String itemName) =>
      isArabic ? 'تمت إضافة "$itemName" إلى السلة' : '"$itemName" added to cart';
  String get continueOrder => isArabic ? 'متابعة الطلب' : 'Checkout';
  String get currency => isArabic ? 'د.ك' : 'KWD';
  String get cancel => isArabic ? 'إلغاء' : 'Cancel';
  String get addToCart => isArabic ? 'إضافة إلى السلة' : 'Add to cart';
  String get freeAddon => isArabic ? 'مجاني' : 'Free';
  String get noAddonSelected => isArabic ? 'بدون' : 'None';
  String get specialNotesLabel =>
      isArabic ? 'ملاحظات خاصة (اختياري)' : 'Special notes (optional)';
  String get specialNotesHint => isArabic
      ? 'مثال: بدون بصل، صوص إضافي...'
      : 'Example: no onions, extra sauce...';
  String basePriceLabel(String price) =>
      isArabic ? 'السعر الأساسي: $price د.ك' : 'Base price: $price KWD';
  String totalWithAddons(String total) =>
      isArabic ? 'الإجمالي: $total د.ك' : 'Total: $total KWD';
  String requiredAddonGroup(String groupName) => isArabic
      ? 'يرجى اختيار خيار من مجموعة "$groupName"'
      : 'Please choose an option from "$groupName"';

  String get impulseBumpsTitle =>
      isArabic ? 'حاجات تنور سفرتك ✨' : 'Complete your order ✨';
  String get impulseBumpsSubtitle => isArabic
      ? 'إضافات سريعة بسعر مناسب — اضغط + للإضافة'
      : 'Quick affordable add-ons — tap + to add';
  String get smartRecommendationsTitle =>
      isArabic ? 'يناسب طلبك 🎯' : 'Pairs with your order 🎯';
  String get smartRecommendationsSubtitle => isArabic
      ? 'اقتراحات ذكية بناءً على محتويات سلتك'
      : 'Smart picks based on what\'s in your cart';
  String get quickAddLabel => isArabic ? 'أضف +' : 'Add +';
  String get linkedSideItemsTitle =>
      isArabic ? 'إضافات مقترحة مع هذا الصنف' : 'Suggested with this item';
  String freeDeliveryRemaining(String amount) => isArabic
      ? 'أضف $amount د.ك أخرى للحصول على توصيل مجاني! 🚚'
      : 'Add $amount KWD more for FREE delivery! 🚚';
  String get freeDeliveryUnlocked =>
      isArabic ? '🎉 مبروك! حصلت على توصيل مجاني' : '🎉 You unlocked free delivery!';
  String freeDeliveryProgressHint(String current, String target) => isArabic
      ? 'مجموعك $current من $target د.ك'
      : 'Your total: $current of $target KWD';

  String get checkoutTitle => isArabic ? 'إتمام الطلب' : 'Complete Order';
  String get customerName => isArabic ? 'اسم العميل' : 'Customer name';
  String get phone => isArabic ? 'رقم الهاتف' : 'Phone number';
  String get deliveryAddress => isArabic ? 'عنوان التوصيل' : 'Delivery address';
  String get governorate => isArabic ? 'المحافظة' : 'Governorate';
  String get area => isArabic ? 'المنطقة' : 'Area';
  String get noAreasForGovernorate =>
      isArabic ? 'لا توجد مناطق لهذه المحافظة' : 'No areas for this governorate';
  String get block => isArabic ? 'القطعة (Block)' : 'Block';
  String get street => isArabic ? 'الشارع (Street)' : 'Street';
  String get avenue => isArabic ? 'الجادة (Avenue) — اختياري' : 'Avenue (optional)';
  String get houseNumber => isArabic ? 'رقم البيت / المبنى' : 'House / building number';
  String get floorApartment =>
      isArabic ? 'الطابق / الشقة — اختياري' : 'Floor / apartment (optional)';
  String get paymentMethod => isArabic ? 'طريقة الدفع' : 'Payment method';
  String get cash => isArabic ? 'كاش' : 'Cash';
  String get knet => 'K-Net';
  String get subtotal => isArabic ? 'المجموع الفرعي' : 'Subtotal';
  String get deliveryFee => isArabic ? 'رسوم التوصيل' : 'Delivery fee';
  String get grandTotal => isArabic ? 'الإجمالي النهائي' : 'Grand total';
  String sendOrder(String total) =>
      isArabic ? 'إرسال الطلب $total د.ك' : 'Send order $total KWD';
  String get required => isArabic ? 'مطلوب' : 'Required';
  String get selectGovernorateAndArea =>
      isArabic ? 'يرجى اختيار المحافظة والمنطقة' : 'Please select governorate and area';
  String get fillRequiredFields => isArabic
      ? 'يرجى تعبئة جميع الحقول الإجبارية (الاسم، الهاتف، العنوان، القطعة، الشارع، والمنزل)'
      : 'Please fill all required fields (name, phone, area, block, street, and house)';
  String get profileLoaded => isArabic
      ? 'تم استرجاع بياناتك السابقة تلقائياً'
      : 'Your saved details were loaded automatically';
  String get lookingUpProfile => isArabic
      ? 'جاري البحث عن بياناتك...'
      : 'Looking up your saved details...';
  String get whatsappNotConfiguredForCustomers => isArabic
      ? 'لا يمكن إتمام الطلب حالياً — لم يُعيَّن رقم واتساب للمطعم. يرجى التواصل مع إدارة المطعم.'
      : 'Checkout is unavailable — this restaurant has no WhatsApp number configured yet.';
  String get whatsappNotConfiguredCheckout => isArabic
      ? 'لم يُعيَّن رقم واتساب لهذا المطعم بعد. يرجى التواصل مع المطعم أو إعداد الرقم من لوحة التحكم.'
      : 'This restaurant has no WhatsApp number configured yet. Please contact the restaurant or set it in admin settings.';
  String get whatsappRequiredAdminHint => isArabic
      ? 'يجب حفظ رقم واتساب هنا ليتمكن العملاء من إرسال الطلبات.'
      : 'Save a WhatsApp number here so customers can complete orders.';
  String get orderSubmitFailed => isArabic
      ? 'حدث خطأ أثناء إرسال الطلب. يرجى المحاولة مرة أخرى.'
      : 'Could not send the order. Please try again.';
  String get orderSentViaWhatsapp =>
      isArabic ? 'تم إرسال الطلب عبر الواتساب' : 'Order sent via WhatsApp';
  String whatsappOpenFailed(String phone) => isArabic
      ? 'تعذر فتح الواتساب. رقم المطعم: $phone'
      : 'Could not open WhatsApp. Restaurant number: $phone';

  String get estimatedTimeTitle =>
      isArabic ? 'الوقت المتوقع' : 'Estimated time';
  String get estimatedTimeHint => isArabic
      ? 'نُحدّث الوقت حسب ضغط الطلبات ومنطقة التوصيل'
      : 'Updated based on order volume and delivery zone';
  String get orderConfirmedTitle =>
      isArabic ? 'تم تأكيد طلبك!' : 'Order confirmed!';
  String get loyaltyWalletLabel =>
      isArabic ? 'رصيد محفظة الولاء' : 'Loyalty wallet balance';
  String get cashbackEarnedLabel =>
      isArabic ? 'كاش باك مكتسب' : 'Cashback earned';
  String get nextOrderDiscountLabel =>
      isArabic ? 'خصم طلبك القادم' : 'Next order discount';
  String get gotIt => isArabic ? 'تمام' : 'Got it';
  String get closingDontLeaveTitle =>
      isArabic ? 'لا تفوّت طلبك!' : "Don't leave your order!";
  String get closingDontLeaveBody => isArabic
      ? 'سلتك جاهزة — أكّد الآن قبل تغيير الأسعار أو نفاد الأصناف'
      : 'Your cart is ready — confirm now before items sell out';

  String get checkoutStepReview =>
      isArabic ? 'مراجعة الطلب' : 'Review order';
  String get checkoutStepDetails =>
      isArabic ? 'بيانات التوصيل' : 'Delivery details';
  String get continueToDetails =>
      isArabic ? 'متابعة إلى بيانات التوصيل' : 'Continue to delivery details';
  String get backToReview =>
      isArabic ? 'رجوع لمراجعة الطلب' : 'Back to order review';
  String get promoCodeLabel =>
      isArabic ? 'كود الخصم الشخصي' : 'Personal promo code';
  String get promoCodeHint =>
      isArabic ? 'أدخل كود الخصم إن وُجد' : 'Enter your promo code if you have one';
  String get applyPromoCode =>
      isArabic ? 'تطبيق الكود' : 'Apply code';
  String get walletAmountLabel =>
      isArabic ? 'مبلغ الخصم من المحفظة' : 'Wallet amount to use';
  String get walletAmountHint =>
      isArabic ? 'أدخل المبلغ المراد خصمه' : 'Enter amount to deduct';
  String get applyWalletAmount =>
      isArabic ? 'تطبيق' : 'Apply';
  String get useFullWalletBalance =>
      isArabic ? 'استخدام الرصيد كاملاً' : 'Use full balance';
  String get walletApplied =>
      isArabic ? 'تم تطبيق رصيد المحفظة بنجاح' : 'Wallet balance applied successfully';
  String get walletInvalid =>
      isArabic ? 'المبلغ غير صالح أو يتجاوز الرصيد' : 'Invalid amount or exceeds balance';
  String get walletAmountRequired =>
      isArabic ? 'يرجى إدخال مبلغ من المحفظة' : 'Please enter a wallet amount';
  String get walletEmpty =>
      isArabic ? 'لا يوجد رصيد في المحفظة' : 'No wallet balance available';
  String get walletLoadingBalance => isArabic
      ? 'جاري جلب رصيد المحفظة...'
      : 'Loading wallet balance...';
  String get walletDiscountLabel =>
      isArabic ? 'خصم المحفظة' : 'Wallet discount';
  String walletAvailableBalance(String amount) => isArabic
      ? 'رصيد المحفظة المتاح: $amount د.ك'
      : 'Available wallet balance: $amount KWD';
  String walletPayRemainderHint(String amount) => isArabic
      ? 'يُخصم $amount د.ك من المحفظة — اختر طريقة دفع الباقي'
      : '$amount KWD from wallet — select payment for the remainder';
  String get walletCoversFullOrder => isArabic
      ? 'المبلغ مغطى بالكامل من المحفظة'
      : 'Order fully covered by wallet';
  String get promoApplied =>
      isArabic ? 'تم تطبيق كود الخصم بنجاح' : 'Promo code applied successfully';
  String get promoInvalid =>
      isArabic ? 'كود الخصم غير صالح' : 'Invalid promo code';
  String get promoDiscountLabel =>
      isArabic ? 'خصم الكود' : 'Promo discount';
  String get personalPromoCodeLabel =>
      isArabic ? 'كود خصمك الشخصي للطلب القادم' : 'Your personal promo for next order';
  String personalPromoHint(String code, String amount) => isArabic
      ? 'احفظ الكود *$code* — خصم $amount د.ك في طلبك القادم'
      : 'Save code *$code* — $amount KWD off your next order';
  String get copyPromoCode =>
      isArabic ? 'نسخ الكود' : 'Copy code';
  String get promoCodeCopied =>
      isArabic ? 'تم نسخ كود الخصم' : 'Promo code copied';
  String get savedPromoAvailable => isArabic
      ? 'لديك كود خصم شخصي — اضغط تطبيق'
      : 'You have a personal promo — tap Apply';
  String get phoneFirstHint => isArabic
      ? 'أدخل رقم هاتفك أولاً لاسترجاع بياناتك تلقائياً'
      : 'Enter your phone first to auto-fill your saved details';
  String get paymentSectionTitle =>
      isArabic ? 'الدفع والمحفظة' : 'Payment & wallet';
  String get walletPhoneHint => isArabic
      ? 'أدخل رقم هاتفك لجلب رصيد المحفظة'
      : 'Enter your phone to load wallet balance';
  String get orderNotesLabel =>
      isArabic ? 'ملاحظات الطلب (اختياري)' : 'Order notes (optional)';
  String get orderNotesHint => isArabic
      ? 'مثال: اتصل عند الوصول، بدون فلفل...'
      : 'Example: call on arrival, no pepper...';
  String get emptyCartCheckout =>
      isArabic ? 'السلة فارغة — أضف أصنافاً أولاً' : 'Cart is empty — add items first';

  String paymentLabel(String value) {
    if (value == 'كاش' || value == 'Cash') return cash;
    return knet;
  }

  String paymentValueForApi(String displayLabel) {
    if (displayLabel == cash || displayLabel == 'Cash') return 'كاش';
    return 'K-Net';
  }
}
