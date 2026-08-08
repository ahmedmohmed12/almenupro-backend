#!/usr/bin/env node
const assert = require('assert');
const {
  buildDeliveryWhatsAppMessage,
  buildDeliveryNotificationPayload,
} = require('../lib/deliveryWhatsAppMessage');

function test(name, fn) {
  try {
    fn();
    console.log(`✓ ${name}`);
  } catch (error) {
    console.error(`✗ ${name}`);
    throw error;
  }
}

test('buildDeliveryWhatsAppMessage includes remaining wallet balance', () => {
  const message = buildDeliveryWhatsAppMessage({
    restaurantName: 'Molton Cookies',
    customerName: 'Ahmed',
    invoiceNumber: '123456',
    earnedCashback: 0.5,
    walletBalance: 1.25,
    personalPromoCode: 'VIP4951A3F2',
    personalPromoDiscount: 0.75,
  });

  assert.ok(message.includes('Molton Cookies'));
  assert.ok(message.includes('1.250'));
  assert.ok(message.includes('VIP4951A3F2'));
  assert.ok(message.includes('رصيد محفظتك المتبقي'));
  assert.ok(message.includes('شكراً'));
});

test('buildDeliveryNotificationPayload uses customer rewards', () => {
  const payload = buildDeliveryNotificationPayload({
    order: {
      id: 'ord_1',
      phone: '96594774951',
      customerName: 'Ahmed',
      invoiceNumber: '999',
      totalPrice: 7,
    },
    customer: {
      phone: '96594774951',
      walletBalance: 2,
      walletHistory: [{ orderId: 'ord_1', amount: 0.7 }],
      personalPromoCode: 'VIP4951ZZZZ',
      personalPromoDiscount: 0.7,
      personalPromoUsed: false,
    },
    restaurantName: 'Molton Cookies',
    restaurantWhatsapp: '96594774950',
    settings: {},
    previewEarnedCashback: () => ({ earnedCashback: 0 }),
    restaurantId: 'rest_molton',
  });

  assert.strictEqual(payload.customerPhone, '96594774951');
  assert.strictEqual(payload.rewards.earnedCashback, 0.7);
  assert.strictEqual(payload.rewards.walletBalance, 2);
  assert.strictEqual(payload.rewards.personalPromoCode, 'VIP4951ZZZZ');
  assert.ok(payload.message.includes('VIP4951ZZZZ'));
  assert.ok(payload.message.includes('رصيد محفظتك المتبقي'));
});

console.log('\nAll delivery WhatsApp tests passed.');
