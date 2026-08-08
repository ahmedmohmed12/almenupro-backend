#!/usr/bin/env node
const assert = require('assert');
const {
  generatePersonalPromoCode,
  assignPersonalPromoToCustomer,
  validatePersonalPromo,
  redeemPersonalPromo,
} = require('../lib/personalPromoCodes');
const { normalizeCustomer } = require('../lib/customersStore');

function test(name, fn) {
  try {
    fn();
    console.log(`✓ ${name}`);
  } catch (error) {
    console.error(`✗ ${name}`);
    throw error;
  }
}

const restaurantId = 'rest_test';
const phone = '96594774951';
const customers = [
  normalizeCustomer(
    {
      phone,
      customerName: 'Test Customer',
      totalOrders: 1,
    },
    'cust_test_1',
    restaurantId,
  ),
];

test('generatePersonalPromoCode returns unique uppercase code', () => {
  const code = generatePersonalPromoCode(phone, 0.75);
  assert.ok(code.startsWith('VIP'));
  assert.ok(code.length >= 8);
});

test('assignPersonalPromoToCustomer stores discount on customer', () => {
  const result = assignPersonalPromoToCustomer(customers, {
    restaurantId,
    phone,
    discountAmount: 0.75,
  });
  assert.ok(result.promoCode);
  assert.strictEqual(result.promoDiscount, 0.75);
  const stored = result.customers[0];
  assert.strictEqual(stored.personalPromoCode, result.promoCode);
});

test('validatePersonalPromo accepts valid code for phone', () => {
  const assigned = assignPersonalPromoToCustomer(customers, {
    restaurantId,
    phone,
    discountAmount: 0.5,
  });
  const validation = validatePersonalPromo({
    customers: assigned.customers,
    restaurantId,
    phone,
    code: assigned.promoCode,
    orderTotal: 5,
  });
  assert.strictEqual(validation.valid, true);
  assert.strictEqual(validation.discount, 0.5);
});

test('redeemPersonalPromo marks code as used', () => {
  const assigned = assignPersonalPromoToCustomer(customers, {
    restaurantId,
    phone,
    discountAmount: 0.5,
  });
  const redeemed = redeemPersonalPromo(assigned.customers, {
    restaurantId,
    phone,
    code: assigned.promoCode,
  });
  const validation = validatePersonalPromo({
    customers: redeemed,
    restaurantId,
    phone,
    code: assigned.promoCode,
    orderTotal: 5,
  });
  assert.strictEqual(validation.valid, false);
  assert.strictEqual(validation.error, 'already_used');
});

console.log('\nAll personal promo tests passed.');
