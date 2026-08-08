const {
  DEFAULT_RESTAURANT_ID,
  parseAuthHeader,
  resolveRestaurantId,
  authError,
  isCashier,
} = require('../lib/adminAuth');
const {
  initDataStore,
  readKitchens,
  writeKitchens,
  readOrders,
  readRestaurants,
} = require('../lib/dataStore');
const {
  filterByRestaurant,
  assertRestaurantAccess,
  resolveRestaurantFromQuery,
} = require('../lib/tenantStore');
const { handleKitchenRoutes } = require('../lib/kitchenRoutes');

const storeReady = initDataStore();

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Restaurant-Id',
  });
  res.end(JSON.stringify(payload));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => resolve(body));
    req.on('error', reject);
  });
}

function requireAuth(req, res) {
  const auth = parseAuthHeader(req);
  if (!auth) {
    authError(res, 401, 'Unauthorized');
    return null;
  }
  return auth;
}

function rejectCashier(auth, res, message) {
  if (isCashier(auth)) {
    authError(res, 403, message);
    return true;
  }
  return false;
}

async function resolveScopedRestaurantId(req, url, auth, { allowPublicDefault = false } = {}) {
  const restaurants = await readRestaurants();
  const slugParam = url.searchParams.get('restaurant_slug') || url.searchParams.get('slug');
  const restaurantIdParam =
    url.searchParams.get('restaurant_id') ||
    url.searchParams.get('restaurantId') ||
    req.headers['x-restaurant-id'];

  if (slugParam) {
    const match = restaurants.find(
      (entry) => String(entry.slug || '').toLowerCase() === String(slugParam).toLowerCase(),
    );
    if (!match) return null;
    return resolveRestaurantId(auth, match.id, { allowPublicDefault });
  }

  if (restaurantIdParam) {
    return resolveRestaurantId(auth, restaurantIdParam, { allowPublicDefault });
  }

  const requested = resolveRestaurantFromQuery(url, restaurants);
  return resolveRestaurantId(auth, requested, { allowPublicDefault });
}

module.exports = async (req, res) => {
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

  const host = req.headers['x-forwarded-host'] || req.headers.host || 'localhost';
  const url = new URL(req.url || '/api/kitchens', `https://${host}`);

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
    sendJson(res, 404, { error: 'Kitchen route not found' });
  }
};
