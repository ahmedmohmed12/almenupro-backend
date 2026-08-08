const { readKitchens, readDeliveryZones } = require('./dataStore');

function kitchenRestaurantId(kitchen) {
  return String(kitchen?.restaurant_id || kitchen?.restaurantId || '').trim();
}

async function getActiveKitchens(restaurantId) {
  const kitchens = await readKitchens();
  return kitchens.filter(
    (kitchen) =>
      kitchenRestaurantId(kitchen) === String(restaurantId) &&
      String(kitchen.status || 'active') === 'active',
  );
}

async function getDefaultKitchen(restaurantId) {
  const active = await getActiveKitchens(restaurantId);
  return active.find((k) => k.is_default === true || k.isDefault === true) || active[0] || null;
}

function zoneDefaultKitchenId(zone) {
  if (!zone) return null;
  return (
    zone.default_kitchen_id ||
    zone.defaultKitchenId ||
    zone.kitchen_id ||
    zone.kitchenId ||
    null
  );
}

async function resolveKitchenForZone({ restaurantId, deliveryZoneId }) {
  if (!deliveryZoneId) {
    const kitchen = await getDefaultKitchen(restaurantId);
    return { kitchen, source: 'platform_default' };
  }

  const zones = await readDeliveryZones();
  const zone = zones.find(
    (entry) =>
      String(entry.id) === String(deliveryZoneId) &&
      String(entry.restaurant_id || entry.restaurantId) === String(restaurantId),
  );

  const mappedId = zoneDefaultKitchenId(zone);
  if (!mappedId) {
    const kitchen = await getDefaultKitchen(restaurantId);
    return { kitchen, source: 'platform_default' };
  }

  const kitchens = await getActiveKitchens(restaurantId);
  const kitchen = kitchens.find((entry) => String(entry.id) === String(mappedId));
  if (!kitchen) {
    const err = new Error(`Delivery zone maps to missing kitchen: ${mappedId}`);
    err.code = 'KITCHEN_NOT_FOUND';
    throw err;
  }

  return { kitchen, source: 'zone_auto' };
}

async function assignTargetKitchen({
  body,
  restaurantId,
  auth,
  deliveryZoneId,
}) {
  const kitchens = await getActiveKitchens(restaurantId);
  const requestedId = String(
    body.targetKitchenId || body.target_kitchen_id || '',
  ).trim();

  const orderType = String(body.orderType || body.order_type || 'Delivery')
    .trim()
    .toLowerCase();
  const isDelivery =
    orderType === 'delivery' ||
    orderType === 'توصيل' ||
    Boolean(deliveryZoneId || body.deliveryZoneId || body.delivery_zone_id);

  let kitchen;
  let source = 'platform_default';
  let overridden = false;
  let previousKitchenId = null;

  if (isDelivery) {
    const zoneId =
      deliveryZoneId || body.deliveryZoneId || body.delivery_zone_id || null;
    const resolved = await resolveKitchenForZone({
      restaurantId,
      deliveryZoneId: zoneId,
    });
    kitchen = resolved.kitchen;
    source = resolved.source;
    previousKitchenId = kitchen?.id || null;

    if (requestedId && kitchen && requestedId !== kitchen.id) {
      const manual = kitchens.find((entry) => String(entry.id) === requestedId);
      if (!manual) {
        const err = new Error('Invalid target kitchen');
        err.code = 'INVALID_TARGET_KITCHEN';
        throw err;
      }
      overridden = true;
      source = 'cashier_override';
      previousKitchenId = kitchen.id;
      kitchen = manual;
    } else if (requestedId && !kitchen) {
      kitchen = kitchens.find((entry) => String(entry.id) === requestedId) || null;
      if (!kitchen) {
        const err = new Error('Invalid target kitchen');
        err.code = 'INVALID_TARGET_KITCHEN';
        throw err;
      }
      source = 'cashier_override';
    }
  } else if (requestedId) {
    kitchen = kitchens.find((entry) => String(entry.id) === requestedId) || null;
    source = 'cashier_override';
  } else {
    kitchen = await getDefaultKitchen(restaurantId);
    source = 'platform_default';
  }

  if (!kitchen) {
    const err = new Error('No active kitchen configured for this restaurant');
    err.code = 'NO_KITCHEN_CONFIGURED';
    throw err;
  }

  const now = new Date().toISOString();
  return {
    targetKitchenId: kitchen.id,
    target_kitchen_id: kitchen.id,
    targetKitchenName: kitchen.name_en || kitchen.name || kitchen.name_ar || kitchen.id,
    target_kitchen_name: kitchen.name_en || kitchen.name || kitchen.name_ar || kitchen.id,
    kitchenAssignment: {
      source,
      assignedAt: now,
      assigned_at: now,
      assignedById: auth?.staffId || auth?.id || null,
      assigned_by_id: auth?.staffId || auth?.id || null,
      assignedByName: auth?.name || auth?.cashierName || null,
      assigned_by_name: auth?.name || auth?.cashierName || null,
      overridden,
      previousKitchenId: overridden ? previousKitchenId : null,
      previous_kitchen_id: overridden ? previousKitchenId : null,
    },
    kitchen_assignment: {
      source,
      assigned_at: now,
      assigned_by_id: auth?.staffId || auth?.id || null,
      assigned_by_name: auth?.name || auth?.cashierName || null,
      overridden,
      previous_kitchen_id: overridden ? previousKitchenId : null,
    },
  };
}

function normalizeKitchen(raw, id, restaurantId) {
  const status = String(raw.status || 'active').trim().toLowerCase();
  const normalizedStatus = ['active', 'paused', 'archived'].includes(status)
    ? status
    : 'active';

  return {
    id: String(id),
    restaurant_id: String(restaurantId),
    restaurantId: String(restaurantId),
    name: String(raw.name || raw.name_ar || raw.nameAr || '').trim(),
    name_ar: String(raw.name_ar || raw.nameAr || raw.name || '').trim(),
    nameAr: String(raw.name_ar || raw.nameAr || raw.name || '').trim(),
    name_en: String(raw.name_en || raw.nameEn || raw.name || '').trim(),
    nameEn: String(raw.name_en || raw.nameEn || raw.name || '').trim(),
    code: String(raw.code || '').trim().toUpperCase(),
    status: normalizedStatus,
    is_default: raw.is_default === true || raw.isDefault === true,
    isDefault: raw.is_default === true || raw.isDefault === true,
    sort_order: Number(raw.sort_order ?? raw.sortOrder ?? 0) || 0,
    sortOrder: Number(raw.sort_order ?? raw.sortOrder ?? 0) || 0,
    kds_enabled:
      raw.kds_enabled !== false &&
      raw.kdsEnabled !== false &&
      raw.kds?.enabled !== false,
    kdsEnabled:
      raw.kds_enabled !== false &&
      raw.kdsEnabled !== false &&
      raw.kds?.enabled !== false,
    createdAt: raw.createdAt || raw.created_at || new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
}

module.exports = {
  getActiveKitchens,
  getDefaultKitchen,
  zoneDefaultKitchenId,
  resolveKitchenForZone,
  assignTargetKitchen,
  normalizeKitchen,
  kitchenRestaurantId,
};
