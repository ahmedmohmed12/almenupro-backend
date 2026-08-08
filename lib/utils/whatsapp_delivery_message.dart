class WhatsAppDeliveryMessage {
  WhatsAppDeliveryMessage._();

  static String build({
    required String restaurantName,
    required String customerName,
    String? invoiceNumber,
    double earnedCashback = 0,
    double walletBalance = 0,
    String personalPromoCode = '',
    double personalPromoDiscount = 0,
  }) {
    final name = restaurantName.trim().isEmpty ? 'المطعم' : restaurantName.trim();
    final customer = customerName.trim().isEmpty ? 'عميلنا' : customerName.trim();
    final invoice = invoiceNumber?.trim() ?? '';
    final invoiceLine =
        invoice.isNotEmpty ? '📌 *رقم الطلب / Order #:* #$invoice\n' : '';

    final rewardsAr = StringBuffer();
    final rewardsEn = StringBuffer();

    if (earnedCashback > 0) {
      rewardsAr.writeln(
        '🎉 *كاش باك:* تم إضافة ${earnedCashback.toStringAsFixed(3)} د.ك إلى محفظة الولاء الخاصة بك.',
      );
      rewardsEn.writeln(
        '🎉 *Cashback:* ${earnedCashback.toStringAsFixed(3)} KWD added to your loyalty wallet.',
      );
    }

    if (walletBalance > 0) {
      rewardsAr.writeln('💰 *رصيد محفظتك المتبقي:* ${walletBalance.toStringAsFixed(3)} د.ك');
      rewardsAr.writeln('   ↳ استخدمه في طلبك القادم من $name!');
      rewardsEn.writeln('💰 *Your remaining wallet balance:* ${walletBalance.toStringAsFixed(3)} KWD');
      rewardsEn.writeln('   ↳ Use it on your next order from $name!');
    }

    if (personalPromoCode.trim().isNotEmpty && personalPromoDiscount > 0) {
      rewardsAr.writeln(
        '🎁 *كود خصمك الشخصي للطلب القادم:* *$personalPromoCode*',
      );
      rewardsAr.writeln(
        '   ↳ خصم ${personalPromoDiscount.toStringAsFixed(3)} د.ك — استخدمه مباشرة عند الطلب القادم!',
      );
      rewardsEn.writeln('🎁 *Your personal promo for next order:* *$personalPromoCode*');
      rewardsEn.writeln(
        '   ↳ ${personalPromoDiscount.toStringAsFixed(3)} KWD off — use it on your next order!',
      );
    }

    if (rewardsAr.isEmpty) {
      rewardsAr.writeln('🙏 نتطلع لخدمتك مجدداً في طلبك القادم!');
      rewardsEn.writeln('🙏 We look forward to serving you again soon!');
    }

    return '''
✅ *تم توصيل طلبك — $name*
✅ *Your order has been delivered — $name*
----------------------------------
👋 مرحباً $customer،
👋 Hello $customer,

$invoiceLine❤️ *شكراً لطلبك من $name!*
❤️ *Thank you for ordering from $name!*

$rewardsAr

$rewardsEn
----------------------------------
نتمنى لك وجبة شهية 😋
Enjoy your meal 😋
''';
  }
}
