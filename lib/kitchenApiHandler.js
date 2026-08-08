const { DEFAULT_RESTAURANT_ID, resolveRestaurantId } = require('./adminAuth');
const {
  initDataStore,
  readKitchens,
  writeKitchens,
  readOrders,
} = require('./dataStore');
const { filterByRestaurant, assertRestaurantAccess } = require('./tenantStore');
const { handleKitchenRoutes } = require('./kitchenRoutes');
const {
  sendJson,
  readBody,
  requireAuth,
  rejectCashier,
  resolveScopedRestaurantId,
  buildRequestUrl,
  authError,
  parseAuthHeader,
} = require('./vercelApiUtils');

const storeReady = initDataStore();
const API_BASE = '/api/kitchens';

async function kitchenApiHandler(req, res) {
  try {
    await storeReady;
  } catch (error) {
    sendJson(res, 503, { error: 'Data store unavailable', details: error.message });
    return;
  }

  if (req.method === 'OPTIONS') {
    sendJson(res, 204, {});
    return;
  }

  const url = buildRequestUrl(req, API_BASE);

  const handled = await handleKitchenRoutes(req, res, url, {
    readBody,
    sendJson,
    authError,
    parseAuthHeader,
    requireAuth,
    rejectCashier,
    resolveScopedRestaurantId,
    resolveRestaurantId,
    assertRestaurantAccess,
    filterByRestaurant,
    readKitchens,
    writeKitchens,
    readOrders,
    DEFAULT_RESTAURANT_ID,
  });

  if (!handled) {
    sendJson(res, 404, { error: 'Kitchen route not found', path: url.pathname });
  }
}

module.exports = kitchenApiHandler;
