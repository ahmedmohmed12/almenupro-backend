const crypto = require('crypto');
const { normalizePhoneDigits, findCustomerByPhone } = require('./customersStore');

function round3(value) {
  return Number((Number(value) || 0).toFixed(3));
}

function readWalletBalance(customer) {
  return round3(customer?.walletBalance ?? customer?.wallet_balance ?? 0);
}

/**
 * Deterministic wallet promo code — changes automatically when balance changes.
 */
function generateWalletPromoCode(restaurantId, phone, walletBalance) {
  const balance = round3(walletBalance);
  if (balance <= 0) return '';

  const phoneDigits = normalizePhoneDigits(phone);
  const suffix = phoneDigits.slice(-4) || '0000';
  const balanceToken = Math.round(balance * 1000)
    .toString(36)
    .toUpperCase()
    .padStart(3, '0')
    .slice(-3);
  const seed = `${String(restaurantId)}:${phoneDigits}:${balanceToken}`;
  const hash = crypto.createHash('sha256').update(seed).digest('hex').slice(0, 5).toUpperCase();
  return `W${suffix}${balanceToken}${hash}`.slice(0, 14);
}

function validateWalletAmount({
  customers,
  restaurantId,
  phone,
  amount,
  orderTotal = 0,
}) {
  const requestedAmount = round3(amount);
  if (requestedAmount <= 0) {
    return {
      valid: false,
      error: 'invalid_amount',
      message: 'Wallet amount must be greater than zero',
    };
  }

  const customer = findCustomerByPhone(customers, restaurantId, phone);
  if (!customer) {
    return {
      valid: false,
      error: 'customer_not_found',
      message: 'No customer profile found for this phone',
    };
  }

  const walletBalance = readWalletBalance(customer);
  if (walletBalance <= 0) {
    return {
      valid: false,
      error: 'empty_wallet',
      message: 'Wallet balance is empty',
    };
  }

  if (requestedAmount > walletBalance) {
    return {
      valid: false,
      error: 'insufficient_balance',
      message: 'Requested amount exceeds wallet balance',
    };
  }

  const total = round3(orderTotal);
  const discount = round3(
    Math.min(requestedAmount, total > 0 ? total : requestedAmount),
  );
  const remainingBalance = round3(Math.max(0, walletBalance - discount));

  return {
    valid: true,
    type: 'wallet',
    discount,
    walletAmount: discount,
    walletBalance,
    remainingBalance,
    coversFullOrder: discount >= total && total > 0,
    message: 'Wallet amount applied',
  };
}

function redeemWalletAmount(customers, { restaurantId, phone, amount, orderId }) {
  const redeemAmount = round3(amount);
  if (redeemAmount <= 0) return customers;

  const customer = findCustomerByPhone(customers, restaurantId, phone);
  if (!customer) return customers;

  const walletBalance = readWalletBalance(customer);
  if (redeemAmount > walletBalance) return customers;

  const index = customers.findIndex((entry) => entry.id === customer.id);
  if (index === -1) return customers;

  const now = new Date().toISOString();
  const history = Array.isArray(customer.walletHistory)
    ? [...customer.walletHistory]
    : Array.isArray(customer.wallet_history)
      ? [...customer.wallet_history]
      : [];

  history.unshift({
    type: 'redeem',
    orderId: orderId || null,
    amount: redeemAmount,
    createdAt: now,
  });

  const nextBalance = round3(walletBalance - redeemAmount);
  const next = [...customers];
  next[index] = syncWalletPromoFields(
    {
      ...customer,
      walletBalance: nextBalance,
      wallet_balance: nextBalance,
      walletHistory: history.slice(0, 50),
      wallet_history: history.slice(0, 50),
      updatedAt: now,
      updated_at: now,
    },
    restaurantId,
  );
  return next;
}

function validateWalletPromo({
  customers,
  restaurantId,
  phone,
  code,
  orderTotal = 0,
}) {
  const normalizedCode = String(code || '').trim().toUpperCase();
  if (!normalizedCode) {
    return { valid: false, error: 'missing_code', message: 'Wallet code required' };
  }

  const customer = findCustomerByPhone(customers, restaurantId, phone);
  if (!customer) {
    return {
      valid: false,
      error: 'customer_not_found',
      message: 'No customer profile found for this phone',
    };
  }

  const walletBalance = readWalletBalance(customer);
  if (walletBalance <= 0) {
    return {
      valid: false,
      error: 'empty_wallet',
      message: 'Wallet balance is empty',
    };
  }

  const expectedCode = generateWalletPromoCode(restaurantId, phone, walletBalance);
  if (!expectedCode || expectedCode.toUpperCase() !== normalizedCode) {
    return {
      valid: false,
      error: 'invalid_code',
      message: 'Invalid or outdated wallet code',
    };
  }

  const total = round3(orderTotal);
  const discount = round3(Math.min(walletBalance, total > 0 ? total : walletBalance));
  const remainingBalance = round3(Math.max(0, walletBalance - discount));
  const nextWalletCode = generateWalletPromoCode(restaurantId, phone, remainingBalance);

  return {
    valid: true,
    type: 'wallet',
    discount,
    walletCode: expectedCode,
    walletBalance,
    remainingBalance,
    nextWalletCode,
    coversFullOrder: discount >= total && total > 0,
    message: 'Wallet code applied',
  };
}

function redeemWalletPromo(customers, { restaurantId, phone, code, amount, orderId }) {
  const redeemAmount = round3(amount);
  if (redeemAmount <= 0) return customers;

  const customer = findCustomerByPhone(customers, restaurantId, phone);
  if (!customer) return customers;

  const walletBalance = readWalletBalance(customer);
  const expectedCode = generateWalletPromoCode(restaurantId, phone, walletBalance);
  const normalizedCode = String(code || '').trim().toUpperCase();
  if (!expectedCode || expectedCode.toUpperCase() !== normalizedCode) {
    return customers;
  }
  if (redeemAmount > walletBalance) return customers;

  const index = customers.findIndex((entry) => entry.id === customer.id);
  if (index === -1) return customers;

  const now = new Date().toISOString();
  const history = Array.isArray(customer.walletHistory)
    ? [...customer.walletHistory]
    : Array.isArray(customer.wallet_history)
      ? [...customer.wallet_history]
      : [];

  history.unshift({
    type: 'redeem',
    orderId: orderId || null,
    amount: redeemAmount,
    walletCode: expectedCode,
    createdAt: now,
  });

  const nextBalance = round3(walletBalance - redeemAmount);
  const next = [...customers];
  next[index] = {
    ...customer,
    walletBalance: nextBalance,
    wallet_balance: nextBalance,
    walletPromoCode: generateWalletPromoCode(restaurantId, phone, nextBalance),
    wallet_promo_code: generateWalletPromoCode(restaurantId, phone, nextBalance),
    walletHistory: history.slice(0, 50),
    wallet_history: history.slice(0, 50),
    updatedAt: now,
    updated_at: now,
  };
  return next;
}

function syncWalletPromoFields(customer, restaurantId) {
  if (!customer) return customer;
  const balance = readWalletBalance(customer);
  const code = generateWalletPromoCode(
    restaurantId,
    customer.phone,
    balance,
  );
  return {
    ...customer,
    walletPromoCode: code,
    wallet_promo_code: code,
  };
}

module.exports = {
  round3,
  readWalletBalance,
  generateWalletPromoCode,
  validateWalletPromo,
  validateWalletAmount,
  redeemWalletPromo,
  redeemWalletAmount,
  syncWalletPromoFields,
};
