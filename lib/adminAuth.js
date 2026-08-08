const crypto = require('crypto');

const SECRET = process.env.ADMIN_AUTH_SECRET || 'almenupro-dev-secret';
const SUPER_ADMIN_USER = process.env.SUPER_ADMIN_USER || 'superadmin';
const SUPER_ADMIN_PASSWORD = process.env.SUPER_ADMIN_PASSWORD || 'almenupro2026';
const DEFAULT_RESTAURANT_ID = 'rest_molton';

const ROLES = {
  SUPER_ADMIN: 'super_admin',
  RESTAURANT_ADMIN: 'restaurant_admin',
  CASHIER: 'cashier',
};

function signToken(payload) {
  const data = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = crypto
    .createHmac('sha256', SECRET)
    .update(data)
    .digest('base64url');
  return `${data}.${signature}`;
}

function verifyToken(token) {
  if (!token || typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 2) return null;

  const [data, signature] = parts;
  const expected = crypto
    .createHmac('sha256', SECRET)
    .update(data)
    .digest('base64url');

  if (signature !== expected) return null;

  try {
    const payload = JSON.parse(Buffer.from(data, 'base64url').toString('utf8'));
    if (!payload?.role) return null;
    return payload;
  } catch {
    return null;
  }
}

function issueSession({
  role,
  restaurantId = null,
  restaurantName = null,
  staffId = null,
  staffName = null,
}) {
  return signToken({
    role,
    restaurantId,
    restaurantName,
    staffId,
    staffName,
    iat: Date.now(),
  });
}

function buildAuthResponse(token) {
  const payload = verifyToken(token);
  if (!payload) return null;

  return {
    token,
    role: payload.role,
    restaurantId: payload.restaurantId || null,
    restaurantName: payload.restaurantName || null,
    staffId: payload.staffId || null,
    staffName: payload.staffName || null,
  };
}

function loginSuperAdmin(username, password) {
  if (
    String(username || '').trim() !== SUPER_ADMIN_USER ||
    String(password || '') !== SUPER_ADMIN_PASSWORD
  ) {
    return null;
  }

  return buildAuthResponse(issueSession({ role: ROLES.SUPER_ADMIN }));
}

function loginRestaurantAdmin(restaurantSlug, password, restaurants) {
  const slug = String(restaurantSlug || '').trim().toLowerCase();
  const restaurant = restaurants.find(
    (entry) => String(entry.slug || '').toLowerCase() === slug,
  );

  if (!restaurant) return null;
  if (String(password || '') !== String(restaurant.adminPassword || '')) {
    return null;
  }

  return buildAuthResponse(
    issueSession({
      role: ROLES.RESTAURANT_ADMIN,
      restaurantId: restaurant.id,
      restaurantName: restaurant.name,
    }),
  );
}

function parseAuthHeader(req) {
  const header = req.headers.authorization || req.headers.Authorization || '';
  const match = String(header).match(/^Bearer\s+(.+)$/i);
  if (!match) return null;
  return verifyToken(match[1]);
}

function isSuperAdmin(auth) {
  return auth?.role === ROLES.SUPER_ADMIN;
}

function isRestaurantAdmin(auth) {
  return auth?.role === ROLES.RESTAURANT_ADMIN;
}

function isCashier(auth) {
  return auth?.role === ROLES.CASHIER;
}

function canAccessRestaurant(auth, restaurantId) {
  if (!auth) return false;
  if (isSuperAdmin(auth)) return true;
  if (
    (isRestaurantAdmin(auth) || isCashier(auth)) &&
    String(auth.restaurantId || '') === String(restaurantId)
  ) {
    return true;
  }
  return false;
}

function resolveRestaurantId(auth, requestedRestaurantId, { allowPublicDefault = false } = {}) {
  if (auth && (isRestaurantAdmin(auth) || isCashier(auth))) {
    return auth.restaurantId;
  }

  if (auth && isSuperAdmin(auth)) {
    return requestedRestaurantId || DEFAULT_RESTAURANT_ID;
  }

  if (allowPublicDefault) {
    return requestedRestaurantId || DEFAULT_RESTAURANT_ID;
  }

  return null;
}

function findRestaurantByNameOrSlug(restaurants, restaurantKey) {
  const key = String(restaurantKey || '').trim().toLowerCase();
  if (!key) return null;
  return (restaurants || []).find((entry) => {
    const slug = String(entry.slug || '').trim().toLowerCase();
    const name = String(entry.name || '').trim().toLowerCase();
    return slug === key || name === key;
  }) || null;
}

function loginCashierSession({
  restaurant,
  staff,
}) {
  if (!restaurant || !staff) return null;
  return buildAuthResponse(
    issueSession({
      role: ROLES.CASHIER,
      restaurantId: restaurant.id,
      restaurantName: restaurant.name,
      staffId: staff.id,
      staffName: staff.name,
    }),
  );
}

function authError(res, statusCode, message) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Restaurant-Id',
  });
  res.end(JSON.stringify({ error: message }));
}

module.exports = {
  ROLES,
  DEFAULT_RESTAURANT_ID,
  SUPER_ADMIN_USER,
  loginSuperAdmin,
  loginRestaurantAdmin,
  loginCashierSession,
  findRestaurantByNameOrSlug,
  parseAuthHeader,
  verifyToken,
  buildAuthResponse,
  isSuperAdmin,
  isRestaurantAdmin,
  isCashier,
  canAccessRestaurant,
  resolveRestaurantId,
  authError,
};
