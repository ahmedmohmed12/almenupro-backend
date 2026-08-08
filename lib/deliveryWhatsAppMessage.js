const { readStoredPromo } = require('./personalPromoCodes');
const { findCashbackForOrder } = require('./loyaltyCashback');

function round3(value) {
  return Number((Number(value) || 0).toFixed(3));
}

function buildDeliveryWhatsAppMessage({
  restaurantName,
  customerName,
  invoiceNumber,
  earnedCashback = 0,
  walletBalance = 0,
  personalPromoCode = '',
  personalPromoDiscount = 0,
}) {
  const name = String(restaurantName || 'المطعم').trim();
  const customer = String(customerName || 'عميلنا').trim();
  const invoice = String(invoiceNumber || '').trim();
  const cashback = round3(earnedCashback);
  const wallet = round3(walletBalance);
  const promoCode = String(personalPromoCode || '').trim();
  const promoDiscount = round3(personalPromoDiscount);

  const invoiceLine = invoice
    ? `📌 *رقم الطلب / Order #:* #${invoice}\n`
    : '';

  let rewardsAr = '';
  let rewardsEn = '';

  if (cashback > 0) {
    rewardsAr += `🎉 *كاش باك:* تم إضافة ${cashback.toFixed(3)} د.ك إلى محفظة الولاء الخاصة بك.\n`;
    rewardsEn += `🎉 *Cashback:* ${cashback.toFixed(3)} KWD added to your loyalty wallet.\n`;
  }

  if (wallet > 0) {
    rewardsAr += `💰 *رصيد محفظتك المتبقي:* ${wallet.toFixed(3)} د.ك\n`;
    rewardsAr += `   ↳ استخدمه في طلبك القادم من ${name}!\n`;
    rewardsEn += `💰 *Your remaining wallet balance:* ${wallet.toFixed(3)} KWD\n`;
    rewardsEn += `   ↳ Use it on your next order from ${name}!\n`;
  }

  if (promoCode && promoDiscount > 0) {
    rewardsAr +=
      `🎁 *كود خصمك الشخصي للطلب القادم:* *${promoCode}*\n` +
      `   ↳ خصم ${promoDiscount.toFixed(3)} د.ك — استخدمه مباشرة عند الطلب القادم!\n`;
    rewardsEn +=
      `🎁 *Your personal promo for next order:* *${promoCode}*\n` +
      `   ↳ ${promoDiscount.toFixed(3)} KWD off — use it on your next order!\n`;
  }

  if (!rewardsAr) {
    rewardsAr = '🙏 نتطلع لخدمتك مجدداً في طلبك القادم!\n';
    rewardsEn = '🙏 We look forward to serving you again soon!\n';
  }

  return (
    `✅ *تم توصيل طلبك — ${name}*\n` +
    `✅ *Your order has been delivered — ${name}*\n` +
    `----------------------------------\n` +
    `👋 مرحباً ${customer}،\n` +
    `👋 Hello ${customer},\n\n` +
    invoiceLine +
    `❤️ *شكراً لطلبك من ${name}!*\n` +
    `❤️ *Thank you for ordering from ${name}!*\n\n` +
    `${rewardsAr}\n` +
    `${rewardsEn}\n` +
    `----------------------------------\n` +
    `نتمنى لك وجبة شهية 😋\n` +
    `Enjoy your meal 😋`
  );
}

function buildDeliveryNotificationPayload({
  order,
  customer,
  restaurantName,
  restaurantWhatsapp,
  settings,
  previewEarnedCashback,
  restaurantId,
}) {
  const promo = readStoredPromo(customer);
  let earnedCashback = findCashbackForOrder(customer, order.id);

  if (earnedCashback <= 0 && typeof previewEarnedCashback === 'function') {
    const preview = previewEarnedCashback(
      Number(order.totalPrice ?? order.total_price ?? 0) || 0,
      settings || {},
    );
    earnedCashback = round3(preview?.earnedCashback ?? 0);
  }

  let walletBalance = round3(
    customer?.walletBalance ?? customer?.wallet_balance ?? 0,
  );
  const persistedCashback = findCashbackForOrder(customer, order.id);
  if (earnedCashback > 0 && persistedCashback <= 0) {
    walletBalance = round3(walletBalance + earnedCashback);
  }
  const personalPromoCode = promo.used ? '' : promo.code;
  const personalPromoDiscount = promo.used ? 0 : promo.discount;

  const message = buildDeliveryWhatsAppMessage({
    restaurantName,
    customerName: order.customerName || order.customer_name,
    invoiceNumber: order.invoiceNumber || order.invoice_number,
    earnedCashback,
    walletBalance,
    personalPromoCode,
    personalPromoDiscount,
  });

  return {
    customerPhone: String(order.phone || '').trim(),
    restaurantWhatsapp: String(restaurantWhatsapp || '').trim(),
    message,
    rewards: {
      earnedCashback,
      walletBalance,
      personalPromoCode,
      personalPromoDiscount,
    },
  };
}

module.exports = {
  buildDeliveryWhatsAppMessage,
  buildDeliveryNotificationPayload,
  findCashbackForOrder,
};
