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

function sanitizeRestaurantAdmin(entry) {
  return {
    ...sanitizeRestaurant(entry),
    ownerName: String(entry.ownerName || entry.owner_name || '').trim(),
    phone: String(entry.phone || entry.ownerPhone || entry.owner_phone || '').trim(),
    subscriptionPlan: String(
      entry.subscriptionPlan || entry.subscription_plan || 'free',
    ).toLowerCase(),
    subscriptionStatus: String(
      entry.subscriptionStatus || entry.subscription_status || 'active',
    ).toLowerCase(),
    subscriptionExpiresAt:
      entry.subscriptionExpiresAt || entry.subscription_expires_at || null,
    subscriptionNotes: String(
      entry.subscriptionNotes || entry.subscription_notes || '',
    ).trim(),
    updatedAt: entry.updatedAt || entry.updated_at || null,
  };
}

function normalizeRestaurantSlug(raw) {
  return String(raw || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9-]/g, '');
}

function createRestaurantRecord(body = {}) {
  const cleanName = String(body.name || '').trim();
  const cleanSlug = normalizeRestaurantSlug(body.slug);
  const adminPassword = String(body.adminPassword || body.admin_password || '');

  if (!cleanName || !cleanSlug || !adminPassword) {
    throw new Error('name, slug, and adminPassword are required');
  }

  const now = new Date().toISOString();
  return {
    id: `rest_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
    slug: cleanSlug,
    name: cleanName,
    adminPassword,
    ownerName: String(body.ownerName || body.owner_name || '').trim(),
    phone: String(body.phone || body.ownerPhone || body.owner_phone || '').trim(),
    status: String(body.status || 'active').trim().toLowerCase() || 'active',
    subscriptionPlan: String(body.subscriptionPlan || body.subscription_plan || 'free')
      .trim()
      .toLowerCase(),
    subscriptionStatus: String(
      body.subscriptionStatus || body.subscription_status || 'active',
    )
      .trim()
      .toLowerCase(),
    subscriptionExpiresAt:
      body.subscriptionExpiresAt || body.subscription_expires_at || null,
    subscriptionNotes: String(
      body.subscriptionNotes || body.subscription_notes || '',
    ).trim(),
    createdAt: now,
    updatedAt: now,
  };
}

function updateRestaurantRecord(existing, body = {}) {
  if (!existing) {
    throw new Error('Restaurant not found');
  }

  const cleanName = String(body.name ?? existing.name ?? '').trim();
  const cleanSlug = normalizeRestaurantSlug(body.slug ?? existing.slug);
  if (!cleanName || !cleanSlug) {
    throw new Error('name and slug are required');
  }

  const next = {
    ...existing,
    name: cleanName,
    slug: cleanSlug,
    ownerName: String(body.ownerName ?? body.owner_name ?? existing.ownerName ?? '').trim(),
    phone: String(
      body.phone ?? body.ownerPhone ?? body.owner_phone ?? existing.phone ?? '',
    ).trim(),
    status: String(body.status ?? existing.status ?? 'active')
      .trim()
      .toLowerCase(),
    subscriptionPlan: String(
      body.subscriptionPlan ??
        body.subscription_plan ??
        existing.subscriptionPlan ??
        'free',
    )
      .trim()
      .toLowerCase(),
    subscriptionStatus: String(
      body.subscriptionStatus ??
        body.subscription_status ??
        existing.subscriptionStatus ??
        'active',
    )
      .trim()
      .toLowerCase(),
    subscriptionExpiresAt:
      body.subscriptionExpiresAt ??
      body.subscription_expires_at ??
      existing.subscriptionExpiresAt ??
      existing.subscription_expires_at ??
      null,
    subscriptionNotes: String(
      body.subscriptionNotes ?? body.subscription_notes ?? existing.subscriptionNotes ?? '',
    ).trim(),
    updatedAt: new Date().toISOString(),
  };

  const adminPassword = body.adminPassword ?? body.admin_password;
  if (adminPassword != null && String(adminPassword).trim()) {
    next.adminPassword = String(adminPassword);
  }

  return next;
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
  sanitizeRestaurantAdmin,
  createRestaurantRecord,
  updateRestaurantRecord,
  normalizeRestaurantSlug,
  resolveRestaurantFromQuery,
  assertRestaurantAccess,
  nextNumericItemId,
  isSuperAdmin,
};
