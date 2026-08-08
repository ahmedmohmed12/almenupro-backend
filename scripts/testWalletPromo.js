const assert = require('assert');
const {
  validateWalletAmount,
  redeemWalletAmount,
  readWalletBalance,
} = require('../lib/walletPromoCodes');

const restaurantId = 'rest_test_wallet';
const phone = '96599887766';

function makeCustomer(balance) {
  return {
    id: 'cust_1',
    restaurant_id: restaurantId,
    phone,
    walletBalance: balance,
  };
}

function run() {
  let customers = [makeCustomer(5.5)];

  const fullOrder = validateWalletAmount({
    customers,
    restaurantId,
    phone,
    amount: 3,
    orderTotal: 3,
  });
  assert.strictEqual(fullOrder.valid, true);
  assert.strictEqual(fullOrder.discount, 3);
  assert.strictEqual(fullOrder.coversFullOrder, true);

  const partialOrder = validateWalletAmount({
    customers,
    restaurantId,
    phone,
    amount: 2,
    orderTotal: 8,
  });
  assert.strictEqual(partialOrder.valid, true);
  assert.strictEqual(partialOrder.discount, 2);
  assert.strictEqual(partialOrder.coversFullOrder, false);

  const overBalance = validateWalletAmount({
    customers,
    restaurantId,
    phone,
    amount: 10,
    orderTotal: 8,
  });
  assert.strictEqual(overBalance.valid, false);

  customers = redeemWalletAmount(customers, {
    restaurantId,
    phone,
    amount: 3,
    orderId: 'ord_1',
  });
  assert.strictEqual(readWalletBalance(customers[0]), 2.5);

  const tenantMismatch = validateWalletAmount({
    customers,
    restaurantId: 'rest_other',
    phone,
    amount: 1,
    orderTotal: 2,
  });
  assert.strictEqual(tenantMismatch.valid, false);

  console.log('testWalletPromo: all assertions passed');
}

run();
