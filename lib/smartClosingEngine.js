const { findCustomerByPhone } = require('./customersStore');
const {
  previewEarnedCashback,
  creditCustomerWallet,
  normalizeLoyaltySettings,
} = require('./loyaltyCashback');
const {
  assignPersonalPromoToCustomer,
  readStoredPromo,
} = require('./personalPromoCodes');

function round3(value) {
  return Number((Number(value) || 0).toFixed(3));
}

function isSmartClosingEnabled(settings = {}) {
  return (
    settings.smartClosingEnabled !== false &&
    settings.smart_closing_enabled !== false
  );
}

function getOrderTotal(order) {
  return (
    Number(order.totalPrice ?? order.total_price ?? order.totalAmount ?? order.total_amount) ||
    0
  );
}

function isPickupOrder(order) {
  const value = String(order.orderType ?? order.order_type ?? '').trim().toLowerCase();
  return value === 'pickup' || value === 'استلام';
}

function estimateEtaMinutes(order) {
  const itemCount = Array.isArray(order.items) ? order.items.length : 0;
  const loadBonus = Math.min(Math.max(itemCount, 1) * 2, 12);
  const deliveryFee = Number(order.deliveryFee ?? order.delivery_fee ?? 0) || 0;
  const zoneBonus = deliveryFee > 2 ? 10 : deliveryFee > 0 ? 5 : 0;

  if (isPickupOrder(order)) {
    const minMinutes = 12 + loadBonus;
    return {
      minMinutes,
      maxMinutes: minMinutes + 8,
      orderType: 'pickup',
    };
  }

  const minMinutes = 28 + zoneBonus + loadBonus;
  return {
    minMinutes,
    maxMinutes: minMinutes + 12,
    orderType: 'delivery',
  };
}

function formatEtaLabel(eta, isArabic = true) {
  if (isArabic) {
    return eta.orderType === 'pickup'
      ? `${eta.minMinutes}–${eta.maxMinutes} دقيقة للاستلام`
      : `${eta.minMinutes}–${eta.maxMinutes} دقيقة للتوصيل`;
  }
  return eta.orderType === 'pickup'
    ? `${eta.minMinutes}–${eta.maxMinutes} min pickup`
    : `${eta.minMinutes}–${eta.maxMinutes} min delivery`;
}

function buildCheckoutUrgency({
  customer,
  settings = {},
  subtotal = 0,
  cartItemCount = 0,
}) {
  const totalOrders = Number(customer?.totalOrders ?? customer?.total_orders ?? 0);
  const isFirstOrder = totalOrders <= 0;
  const threshold = Number(settings.freeDeliveryThreshold ?? settings.free_delivery_threshold ?? 0);
  const remaining =
    threshold > 0 ? round3(Math.max(0, threshold - Number(subtotal || 0))) : 0;
  const hour = new Date().getHours();
  const isPeak = hour >= 18 && hour <= 22;

  let urgencyType = 'standard';
  let messageAr = 'أكمل طلبك الآن — نبدأ التحضير فور التأكيد!';
  let messageEn = 'Complete your order — we start preparing right after confirmation!';

  if (isFirstOrder) {
    urgencyType = 'first_order';
    messageAr = '🎁 طلبك الأول؟ مفاجأة ترحيبية تنتظرك بعد التأكيد!';
    messageEn = '🎁 First order? A welcome surprise awaits after confirmation!';
  } else if (remaining > 0 && remaining <= 2) {
    urgencyType = 'almost_free_delivery';
    messageAr = `🔥 باقي ${remaining.toFixed(3)} د.ك فقط للتوصيل المجاني — لا تفوّت الفرصة!`;
    messageEn = `🔥 Only ${remaining.toFixed(3)} KWD left for FREE delivery — don't miss it!`;
  } else if (isPeak && cartItemCount >= 2) {
    urgencyType = 'peak_hour';
    messageAr = '⏰ وقت الذروة — أكّد الآن لتحصل على أسرع توصيل ممكن';
    messageEn = '⏰ Peak hour — confirm now for the fastest delivery';
  } else if (totalOrders >= 5) {
    urgencyType = 'returning_vip';
    messageAr = '⭐ عميل مميز! طلبك محل اهتمامنا — أكّد الآن';
    messageEn = '⭐ VIP customer! Your order gets priority — confirm now';
  }

  return {
    urgencyType,
    messageAr,
    messageEn,
    isFirstOrder,
    remainingForFreeDelivery: remaining,
  };
}

function buildSmartClosingPayload({
  order,
  customer,
  settings = {},
  rewards = {},
  phase = 'post_checkout',
}) {
  const eta = estimateEtaMinutes(order);
  const urgency = buildCheckoutUrgency({
    customer,
    settings,
    subtotal: order.subtotal ?? getOrderTotal(order) - (order.deliveryFee || 0),
    cartItemCount: Array.isArray(order.items) ? order.items.length : 0,
  });

  const earnedCashback = round3(rewards.earnedCashback ?? 0);
  const welcomeDiscount = round3(rewards.welcomeDiscountForNextOrder ?? 0);
  const walletBalance = round3(rewards.walletBalance ?? 0);
  const personalPromoCode = String(rewards.personalPromoCode ?? '').trim();
  const isFirstOrder = rewards.isFirstOrder === true || urgency.isFirstOrder;

  let postCheckoutMessageAr = 'شكراً لطلبك! نجهّزه الآن بكل حب ❤️';
  let postCheckoutMessageEn = 'Thanks for your order! We are preparing it with care ❤️';

  if (earnedCashback > 0 && welcomeDiscount > 0 && personalPromoCode) {
    postCheckoutMessageAr =
      `🎉 تم إضافة ${earnedCashback.toFixed(3)} د.ك كاش باك! كود خصمك الشخصي للطلب القادم: *${personalPromoCode}* (${welcomeDiscount.toFixed(3)} د.ك)`;
    postCheckoutMessageEn =
      `🎉 ${earnedCashback.toFixed(3)} KWD cashback added! Your personal promo for next order: *${personalPromoCode}* (${welcomeDiscount.toFixed(3)} KWD off)`;
  } else if (earnedCashback > 0 && welcomeDiscount > 0) {
    postCheckoutMessageAr =
      `🎉 تم إضافة ${earnedCashback.toFixed(3)} د.ك كاش باك + خصم ${welcomeDiscount.toFixed(3)} د.ك لطلبك القادم!`;
    postCheckoutMessageEn =
      `🎉 ${earnedCashback.toFixed(3)} KWD cashback added + ${welcomeDiscount.toFixed(3)} KWD off your next order!`;
  } else if (welcomeDiscount > 0 && personalPromoCode) {
    postCheckoutMessageAr =
      `🎁 كود خصمك الشخصي: *${personalPromoCode}* — استخدمه في طلبك القادم للحصول على ${welcomeDiscount.toFixed(3)} د.ك خصم`;
    postCheckoutMessageEn =
      `🎁 Your personal promo code: *${personalPromoCode}* — use it on your next order for ${welcomeDiscount.toFixed(3)} KWD off`;
  } else if (earnedCashback > 0) {
    postCheckoutMessageAr =
      `🎉 تم إضافة ${earnedCashback.toFixed(3)} د.ك إلى محفظة الولاء الخاصة بك`;
    postCheckoutMessageEn =
      `🎉 ${earnedCashback.toFixed(3)} KWD added to your loyalty wallet`;
  } else if (welcomeDiscount > 0) {
    postCheckoutMessageAr =
      `🎁 مبروك! خصم ${welcomeDiscount.toFixed(3)} د.ك ينتظرك في طلبك القادم`;
    postCheckoutMessageEn =
      `🎁 Congrats! ${welcomeDiscount.toFixed(3)} KWD off awaits you on your next order`;
  } else if (isFirstOrder) {
    postCheckoutMessageAr = '🎁 شكراً لانضمامك! نراك قريباً في طلبك القادم';
    postCheckoutMessageEn = '🎁 Thanks for joining us! See you on your next order';
  }

  return {
    phase,
    urgencyType: urgency.urgencyType,
    messageAr: phase === 'checkout' ? urgency.messageAr : postCheckoutMessageAr,
    messageEn: phase === 'checkout' ? urgency.messageEn : postCheckoutMessageEn,
    estimatedDeliveryMinutes: eta.minMinutes,
    estimatedDeliveryMaxMinutes: eta.maxMinutes,
    estimatedDeliveryLabelAr: formatEtaLabel(eta, true),
    estimatedDeliveryLabelEn: formatEtaLabel(eta, false),
    orderType: eta.orderType,
    rewards: {
      earnedCashback,
      welcomeDiscountForNextOrder: welcomeDiscount,
      walletBalance,
      isFirstOrder,
      qualifiesForCashback: rewards.qualifiesForCashback === true,
      personalPromoCode,
      personalPromoDiscount: welcomeDiscount,
    },
    postCheckoutMessageAr,
    postCheckoutMessageEn,
  };
}

function applyWelcomeDiscountToCustomer(customers, order, restaurantId, amount) {
  const discount = round3(amount);
  if (discount <= 0) return customers;

  const { customers: nextCustomers } = assignPersonalPromoToCustomer(customers, {
    restaurantId,
    phone: order.phone,
    discountAmount: discount,
  });
  return nextCustomers;
}

function applyPostCheckoutRewards({ customers, order, restaurantId, settings, customerBefore }) {
  if (!isSmartClosingEnabled(settings)) {
    return {
      customers,
      rewards: {
        earnedCashback: 0,
        welcomeDiscountForNextOrder: 0,
        walletBalance: round3(
          customerBefore?.walletBalance ?? customerBefore?.wallet_balance ?? 0,
        ),
        isFirstOrder: false,
        qualifiesForCashback: false,
      },
      smartClosing: null,
    };
  }

  const orderTotal = getOrderTotal(order);
  const loyaltyPreview = previewEarnedCashback(orderTotal, settings);
  const totalOrders = Number(customerBefore?.totalOrders ?? customerBefore?.total_orders ?? 1);
  const isFirstOrder = totalOrders === 1;

  let nextCustomers = customers;
  let earnedCashback = 0;
  let welcomeDiscount = 0;

  if (loyaltyPreview.qualifies && loyaltyPreview.earnedCashback > 0) {
    earnedCashback = round3(loyaltyPreview.earnedCashback);
    nextCustomers = creditCustomerWallet(nextCustomers, order, restaurantId, earnedCashback);
  }

  if (isFirstOrder) {
    welcomeDiscount = round3(Math.min(1, Math.max(0.25, orderTotal * 0.1)));
    nextCustomers = applyWelcomeDiscountToCustomer(
      nextCustomers,
      order,
      restaurantId,
      welcomeDiscount,
    );
  }

  const customerAfter = findCustomerByPhone(nextCustomers, restaurantId, order.phone);
  const walletBalance = round3(
    customerAfter?.walletBalance ?? customerAfter?.wallet_balance ?? 0,
  );
  const storedPromo = readStoredPromo(customerAfter);

  const rewards = {
    earnedCashback,
    welcomeDiscountForNextOrder: welcomeDiscount,
    walletBalance,
    isFirstOrder,
    qualifiesForCashback: loyaltyPreview.qualifies === true,
    personalPromoCode: storedPromo.code,
    personalPromoDiscount: storedPromo.discount,
  };

  const smartClosing = buildSmartClosingPayload({
    order,
    customer: customerAfter || customerBefore,
    settings,
    rewards,
    phase: 'post_checkout',
  });

  return {
    customers: nextCustomers,
    rewards,
    smartClosing,
  };
}

function buildCheckoutPreview({ customer, settings, body = {} }) {
  if (!isSmartClosingEnabled(settings)) {
    return {
      enabled: false,
      phase: 'checkout',
      urgencyType: 'disabled',
      messageAr: '',
      messageEn: '',
      loyaltyEnabled: false,
      projectedCashback: 0,
    };
  }

  const subtotal = Number(body.subtotal ?? body.sub_total ?? 0) || 0;
  const deliveryFee = Number(body.deliveryFee ?? body.delivery_fee ?? 0) || 0;
  const cartItemCount = Number(body.cartItemCount ?? body.cart_item_count ?? 0) || 0;
  const orderType = String(body.orderType ?? body.order_type ?? 'Delivery');

  const previewOrder = {
    subtotal,
    deliveryFee,
    totalPrice: subtotal + deliveryFee,
    orderType,
    items: Array(cartItemCount).fill({}),
  };

  const urgency = buildCheckoutUrgency({
    customer,
    settings,
    subtotal,
    cartItemCount,
  });

  const eta = estimateEtaMinutes(previewOrder);
  const loyalty = normalizeLoyaltySettings(settings);
  const cashbackPreview = previewEarnedCashback(subtotal + deliveryFee, settings);

  return {
    enabled: true,
    ...buildSmartClosingPayload({
      order: previewOrder,
      customer,
      settings,
      rewards: {
        earnedCashback: cashbackPreview.earnedCashback,
        welcomeDiscountForNextOrder:
          Number(customer?.totalOrders ?? customer?.total_orders ?? 0) <= 0
            ? round3(Math.min(1, Math.max(0.25, (subtotal + deliveryFee) * 0.1)))
            : round3(
                customer?.nextOrderDiscount ?? customer?.next_order_discount ?? 0,
              ),
        walletBalance: round3(
          customer?.walletBalance ?? customer?.wallet_balance ?? 0,
        ),
        isFirstOrder: urgency.isFirstOrder,
        qualifiesForCashback: cashbackPreview.qualifies,
      },
      phase: 'checkout',
    }),
    urgencyType: urgency.urgencyType,
    messageAr: urgency.messageAr,
    messageEn: urgency.messageEn,
    loyaltyEnabled: loyalty.loyaltyEnabled && isSmartClosingEnabled(settings),
    projectedCashback: round3(cashbackPreview.earnedCashback),
  };
}

module.exports = {
  estimateEtaMinutes,
  formatEtaLabel,
  buildCheckoutUrgency,
  buildSmartClosingPayload,
  applyPostCheckoutRewards,
  buildCheckoutPreview,
  getOrderTotal,
  isSmartClosingEnabled,
};
