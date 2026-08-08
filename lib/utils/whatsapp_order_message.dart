import '../models/cart_item.dart';
import '../models/delivery_address_details.dart';

class WhatsAppOrderMessage {
  static String build({
    required String restaurantName,
    required String invoiceNumber,
    required String customerName,
    required String phone,
    required String paymentMethod,
    required String orderTime,
    required List<CartItem> cartItems,
    required double subtotal,
    required double deliveryFee,
    required double grandTotal,
    required String addressArabic,
    required String addressEnglish,
    double promoDiscount = 0,
    String? promoCodeApplied,
    double walletDiscount = 0,
    String? personalPromoCodeGranted,
    double personalPromoDiscount = 0,
    String orderNotes = '',
  }) {
    final itemsAr = StringBuffer();
    final itemsEn = StringBuffer();

    for (final item in cartItems) {
      final nameAr = item.menuItem.localizedName('ar');
      final nameEn = item.menuItem.localizedName('en');
      final lineTotal = item.totalPrice.toStringAsFixed(3);
      final addonsAr = item.selectedOptions
          .map((option) => '   ↳ ${option.group}: ${option.name}')
          .join('\n');
      final addonsEn = item.selectedOptions
          .map((option) => '   ↳ ${option.group}: ${option.name}')
          .join('\n');

      itemsAr.writeln('• $nameAr x${item.quantity} ($lineTotal د.ك)');
      if (addonsAr.isNotEmpty) itemsAr.writeln(addonsAr);
      itemsEn.writeln('• $nameEn x${item.quantity} ($lineTotal KWD)');
      if (addonsEn.isNotEmpty) itemsEn.writeln(addonsEn);
    }

    final paymentAr = paymentMethod == 'K-Net'
        ? 'K-Net'
        : paymentMethod == 'محفظة'
            ? 'محفظة الولاء'
            : 'كاش';
    final paymentEn = paymentMethod == 'K-Net'
        ? 'K-Net'
        : paymentMethod == 'محفظة'
            ? 'Loyalty wallet'
            : 'Cash';
    final notesBlock = orderNotes.trim().isEmpty
        ? ''
        : '\n📝 *ملاحظات / Notes:* $orderNotes\n';
    final promoAppliedBlock = promoDiscount > 0
        ? '\n🏷️ *كود الخصم / Promo:* ${promoCodeApplied ?? ''}\n💸 *خصم / Discount:* -${promoDiscount.toStringAsFixed(3)} د.ك / KWD'
        : '';
    final walletAppliedBlock = walletDiscount > 0
        ? '\n💼 *خصم المحفظة / Wallet discount:* -${walletDiscount.toStringAsFixed(3)} د.ك / KWD'
        : '';
    final promoGrantedBlock = personalPromoCodeGranted != null &&
            personalPromoCodeGranted.trim().isNotEmpty &&
            personalPromoDiscount > 0
        ? '''

🎁 *كود خصمك الشخصي للطلب القادم / Your personal promo for next order:*
   *$personalPromoCodeGranted* — ${personalPromoDiscount.toStringAsFixed(3)} د.ك / KWD off'''
        : '';

    return '''
🧾 *فاتورة طلب جديدة - $restaurantName*
🧾 *New Order Invoice - $restaurantName*
----------------------------------
📌 *رقم الفاتورة / Invoice #:* #$invoiceNumber
👤 *اسم العميل / Customer:* $customerName
📞 *رقم الهاتف / Phone:* $phone
📍 *عنوان التوصيل / Delivery address:*
   🇰🇼 $addressArabic
   🇬🇧 $addressEnglish
🚚 *رسوم التوصيل / Delivery fee:* ${deliveryFee.toStringAsFixed(3)} د.ك / KWD
💳 *طريقة الدفع / Payment:* $paymentAr / $paymentEn
$notesBlock
🕒 *وقت الطلب / Order time:* $orderTime

🛒 *تفاصيل الطلب / Order details:*
$itemsAr
$itemsEn
----------------------------------
🧮 *المجموع الفرعي / Subtotal:* ${subtotal.toStringAsFixed(3)} د.ك / KWD
🚚 *التوصيل / Delivery:* ${deliveryFee.toStringAsFixed(3)} د.ك / KWD$promoAppliedBlock$walletAppliedBlock
💰 *الإجمالي النهائي / Grand total:* ${grandTotal.toStringAsFixed(3)} د.ك / KWD
$promoGrantedBlock
----------------------------------
شكراً لطلبكم من $restaurantName! ❤️
Thank you for ordering from $restaurantName! ❤️
''';
  }

  static String formatAddressEnglish({
    required DeliveryAddressDetails details,
    required String governorate,
    required String areaName,
  }) {
    return details.formatEnglish(
      governorate: governorate,
      areaName: areaName,
    );
  }
}
