const {
  parseAuthHeader,
  resolveRestaurantId,
  authError,
  isCashier,
} = require('./adminAuth');
const { readRestaurants } = require('./dataStore');
const { resolveRestaurantFromQuery } = require('./tenantStore');

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
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

function buildRequestUrl(req, apiBasePath) {
  const host = req.headers['x-forwarded-host'] || req.headers.host || 'localhost';
  const proto = req.headers['x-forwarded-proto'] || 'https';
  let raw = req.url || apiBasePath;

  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    return new URL(raw);
  }

  if (!raw.startsWith('/')) {
    raw = `/${raw}`;
  }

  if (raw.startsWith(`${apiBasePath}.js`)) {
    raw = raw.replace(`${apiBasePath}.js`, apiBasePath);
  }

  if (!raw.startsWith(apiBasePath)) {
    const suffix = raw === '/' ? '' : raw;
    raw = `${apiBasePath}${suffix}`;
  }

  return new URL(raw, `${proto}://${host}`);
}

module.exports = {
  sendJson,
  readBody,
  requireAuth,
  rejectCashier,
  resolveScopedRestaurantId,
  buildRequestUrl,
  authError,
  parseAuthHeader,
  resolveRestaurantId,
};
