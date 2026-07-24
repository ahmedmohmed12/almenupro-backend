const fs = require('fs');
const path = require('path');

const {
  DEFAULT_RESTAURANT_ID,
  canAccessRestaurant,
  isSuperAdmin,
} = require('./adminAuth');

function ensureRestaurantId(item, restaurantId = DEFAULT_RESTAURANT_ID) {
  return {
    ...item,
    restaurant_id: item.restaurant_id || item.restaurantId || restaurantId,
  };
}

function filterByRestaurant(items, restaurantId) {
  if (!restaurantId) return items;
  return items.filter(
    (item) =>
      String(item.restaurant_id || item.restaurantId || DEFAULT_RESTAURANT_ID) ===
      String(restaurantId),
  );
}

function migrateSettingsShape(raw) {
  if (!raw || typeof raw !== 'object') {
    return { byRestaurant: { [DEFAULT_RESTAURANT_ID]: defaultSettingsPayload() } };
  }

  if (raw.byRestaurant && typeof raw.byRestaurant === 'object') {
    return raw;
  }

  return {
    byRestaurant: {
      [DEFAULT_RESTAURANT_ID]: raw,
    },
  };
}

function defaultSettingsPayload() {
  return {
    whatsappNumber: '96594774950',
    workingHours: [
      { weekday: 6, isOpen: true, open: '10:00', close: '22:00' },
      { weekday: 7, isOpen: true, open: '10:00', close: '22:00' },
      { weekday: 1, isOpen: true, open: '10:00', close: '22:00' },
      { weekday: 2, isOpen: true, open: '10:00', close: '22:00' },
      { weekday: 3, isOpen: true, open: '10:00', close: '22:00' },
      { weekday: 4, isOpen: true, open: '10:00', close: '22:00' },
      { weekday: 5, isOpen: true, open: '10:00', close: '23:00' },
    ],
    updatedAt: new Date().toISOString(),
  };
}

function sanitizeRestaurant(entry) {
  return {
    id: entry.id,
    slug: entry.slug,
    name: entry.name,
    status: entry.status || 'active',
    createdAt: entry.createdAt || new Date().toISOString(),
  };
}

function createRestaurantRecord({ name, slug, adminPassword, admin_password }) {
  const cleanName = String(name || '').trim();
  const password = String(adminPassword || admin_password || '').trim();
  const cleanSlug = normalizeRestaurantSlug(slug, cleanName);

  if (!cleanName || !cleanSlug || !password) {
    throw new Error('name, slug, and adminPassword are required');
  }

  return {
    id: `rest_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
    slug: cleanSlug,
    name: cleanName,
    adminPassword: password,
    status: 'active',
    createdAt: new Date().toISOString(),
  };
}

function normalizeRestaurantSlug(slug, fallbackName = '') {
  const normalize = (value) =>
    String(value || '')
      .trim()
      .toLowerCase()
      .replace(/\s+/g, '-')
      .replace(/[^a-z0-9-]/g, '')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '');

  const fromSlug = normalize(slug);
  if (fromSlug) return fromSlug;

  const fromName = normalize(fallbackName);
  if (fromName) return fromName;

  return '';
}

function resolveRestaurantFromQuery(url, restaurants) {
  const restaurantId = url.searchParams.get('restaurant_id');
  const slug = url.searchParams.get('restaurant_slug') || url.searchParams.get('slug');

  if (restaurantId) return restaurantId;
  if (slug) {
    const match = restaurants.find(
      (entry) => String(entry.slug || '').toLowerCase() === slug.toLowerCase(),
    );
    if (match) return match.id;
    return null;
  }

  return DEFAULT_RESTAURANT_ID;
}

function assertRestaurantAccess(auth, restaurantId, authError, res) {
  if (!canAccessRestaurant(auth, restaurantId)) {
    authError(res, 403, 'Access denied for this restaurant');
    return false;
  }
  return true;
}

function nextNumericItemId(items) {
  let maxId = 0;
  for (const item of items) {
    const numeric = Number(item.id);
    if (Number.isFinite(numeric) && numeric > maxId) {
      maxId = numeric;
    }
  }
  return maxId + 1;
}

module.exports = {
  DEFAULT_RESTAURANT_ID,
  ensureRestaurantId,
  filterByRestaurant,
  migrateSettingsShape,
  defaultSettingsPayload,
  sanitizeRestaurant,
  createRestaurantRecord,
  normalizeRestaurantSlug,
  resolveRestaurantFromQuery,
  assertRestaurantAccess,
  nextNumericItemId,
  isSuperAdmin,
};
