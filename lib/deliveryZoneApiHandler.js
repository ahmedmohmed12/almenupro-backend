const { DEFAULT_RESTAURANT_ID, resolveRestaurantId } = require('./adminAuth');
const {
  initDataStore,
  readDeliveryZones,
  writeDeliveryZones,
} = require('./dataStore');
const { filterByRestaurant, assertRestaurantAccess } = require('./tenantStore');
const { handleDeliveryZoneRoutes } = require('./deliveryZoneRoutes');
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
const API_BASE = '/api/delivery-zones';

async function deliveryZoneApiHandler(req, res) {
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

  const handled = await handleDeliveryZoneRoutes(req, res, url, {
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
    readDeliveryZones,
    writeDeliveryZones,
    DEFAULT_RESTAURANT_ID,
  });

  if (!handled) {
    sendJson(res, 404, { error: 'Delivery zone route not found', path: url.pathname });
  }
}

module.exports = deliveryZoneApiHandler;
