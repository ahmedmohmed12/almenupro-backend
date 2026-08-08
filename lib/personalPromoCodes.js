const { normalizePhoneDigits, findCustomerByPhone } = require('./customersStore');

function round3(value) {
  return Number((Number(value) || 0).toFixed(3));
}

function generatePersonalPromoCode(phone, discountAmount) {
  const suffix = normalizePhoneDigits(phone).slice(-4) || '0000';
  const token = Math.random().toString(36).slice(2, 6).toUpperCase();
  const amountPart = Math.round(round3(discountAmount) * 1000)
    .toString(36)
    .toUpperCase()
    .padStart(2, '0')
    .slice(-2);
  return `VIP${suffix}${amountPart}${token}`.slice(0, 16);
}

function readStoredPromo(customer) {
  if (!customer) {
    return {
      code: '',
      discount: 0,
      used: false,
    };
  }

  return {
    code: String(
      customer.personalPromoCode ?? customer.personal_promo_code ?? '',
    ).trim(),
    discount: round3(
      customer.personalPromoDiscount ??
        customer.personal_promo_discount ??
        customer.nextOrderDiscount ??
        customer.next_order_discount ??
        0,
    ),
    used:
      customer.personalPromoUsed === true ||
      customer.personal_promo_used === true,
  };
}

function assignPersonalPromoToCustomer(customers, { restaurantId, phone, discountAmount }) {
  const discount = round3(discountAmount);
  if (discount <= 0) {
    return { customers, promoCode: null, promoDiscount: 0 };
  }

  const customer = findCustomerByPhone(customers, restaurantId, phone);
  if (!customer) {
    return { customers, promoCode: null, promoDiscount: 0 };
  }

  const code = generatePersonalPromoCode(phone, discount);
  const index = customers.findIndex((entry) => entry.id === customer.id);
  if (index === -1) {
    return { customers, promoCode: null, promoDiscount: 0 };
  }

  const now = new Date().toISOString();
  const next = [...customers];
  next[index] = {
    ...customer,
    personalPromoCode: code,
    personal_promo_code: code,
    personalPromoDiscount: discount,
    personal_promo_discount: discount,
    personalPromoUsed: false,
    personal_promo_used: false,
    personalPromoCreatedAt: now,
    personal_promo_created_at: now,
    nextOrderDiscount: discount,
    next_order_discount: discount,
    updatedAt: now,
    updated_at: now,
  };

  return {
    customers: next,
    promoCode: code,
    promoDiscount: discount,
  };
}

function validatePersonalPromo({
  customers,
  restaurantId,
  phone,
  code,
  orderTotal = 0,
}) {
  const normalizedCode = String(code || '').trim().toUpperCase();
  if (!normalizedCode) {
    return { valid: false, error: 'missing_code', message: 'Promo code required' };
  }

  const customer = findCustomerByPhone(customers, restaurantId, phone);
  if (!customer) {
    return {
      valid: false,
      error: 'customer_not_found',
      message: 'No customer profile found for this phone',
    };
  }

  const stored = readStoredPromo(customer);
  if (!stored.code || stored.code.toUpperCase() !== normalizedCode) {
    return { valid: false, error: 'invalid_code', message: 'Invalid promo code' };
  }
  if (stored.used) {
    return {
      valid: false,
      error: 'already_used',
      message: 'This promo code was already used',
    };
  }
  if (stored.discount <= 0) {
    return {
      valid: false,
      error: 'no_discount',
      message: 'Promo code has no remaining discount',
    };
  }

  const total = round3(orderTotal);
  const discount = round3(Math.min(stored.discount, total > 0 ? total : stored.discount));

  return {
    valid: true,
    discount,
    promoCode: stored.code,
    message: 'Promo code applied',
  };
}

function redeemPersonalPromo(customers, { restaurantId, phone, code }) {
  const normalizedCode = String(code || '').trim().toUpperCase();
  if (!normalizedCode) return customers;

  const customer = findCustomerByPhone(customers, restaurantId, phone);
  if (!customer) return customers;

  const stored = readStoredPromo(customer);
  if (!stored.code || stored.code.toUpperCase() !== normalizedCode || stored.used) {
    return customers;
  }

  const index = customers.findIndex((entry) => entry.id === customer.id);
  if (index === -1) return customers;

  const now = new Date().toISOString();
  const next = [...customers];
  next[index] = {
    ...customer,
    personalPromoUsed: true,
    personal_promo_used: true,
    personalPromoRedeemedAt: now,
    personal_promo_redeemed_at: now,
    nextOrderDiscount: 0,
    next_order_discount: 0,
    updatedAt: now,
    updated_at: now,
  };
  return next;
}

module.exports = {
  round3,
  generatePersonalPromoCode,
  readStoredPromo,
  assignPersonalPromoToCustomer,
  validatePersonalPromo,
  redeemPersonalPromo,
};
