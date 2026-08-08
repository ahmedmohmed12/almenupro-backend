const { DEFAULT_RESTAURANT_ID } = require('./adminAuth');
const { ensureRestaurantId } = require('./tenantStore');

function normalizeDeliveryZone(raw, id, restaurantId = DEFAULT_RESTAURANT_ID) {
  const defaultKitchenId = String(
    raw.defaultKitchenId ||
      raw.default_kitchen_id ||
      raw.kitchenId ||
      raw.kitchen_id ||
      '',
  ).trim();

  return ensureRestaurantId(
    {
      id: String(id),
      governorate: String(raw.governorate || raw.governorateName || '').trim(),
      areaName: String(raw.areaName || raw.area_name || '').trim(),
      deliveryFee: Number(raw.deliveryFee ?? raw.delivery_fee ?? 0) || 0,
      defaultKitchenId: defaultKitchenId || null,
      default_kitchen_id: defaultKitchenId || null,
      isActive:
        raw.isActive === false ||
        raw.is_active === false ||
        raw.isActive === 0 ||
        raw.is_active === 0
          ? false
          : true,
      createdAt: raw.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    restaurantId,
  );
}

function findDeliveryZoneById(zones, zoneId) {
  return zones.find((zone) => String(zone.id) === String(zoneId));
}

async function handleDeliveryZoneRoutes(req, res, url, ctx) {
  const {
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
  } = ctx;

  if (req.method === 'GET' && url.pathname === '/api/delivery-zones') {
    const auth = parseAuthHeader(req);
    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: true,
    });

    if (!restaurantId) {
      sendJson(res, 404, { error: 'Restaurant not found' });
      return true;
    }

    const zones = filterByRestaurant(await readDeliveryZones(), restaurantId).filter(
      (zone) => zone.isActive !== false,
    );
    sendJson(res, 200, zones);
    return true;
  }

  if (req.method === 'POST' && url.pathname === '/api/delivery-zones') {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (rejectCashier(auth, res, 'Cashiers cannot manage delivery zones')) return true;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurantId = resolveRestaurantId(
        auth,
        body.restaurantId ||
          body.restaurant_id ||
          req.headers['x-restaurant-id'],
      );

      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      const governorate = String(body.governorate || '').trim();
      const areaName = String(body.areaName || body.area_name || '').trim();
      if (!governorate || !areaName) {
        sendJson(res, 400, { error: 'Governorate and area name are required' });
        return true;
      }

      const id = `zone_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
      const zone = normalizeDeliveryZone(body, id, restaurantId);
      zone.governorate = governorate;
      zone.areaName = areaName;

      if (!zone.defaultKitchenId && !zone.default_kitchen_id) {
        sendJson(res, 400, {
          error: 'A kitchen must be assigned to each delivery zone',
          code: 'KITCHEN_REQUIRED',
        });
        return true;
      }

      const zones = await readDeliveryZones();
      zones.push(zone);
      await writeDeliveryZones(zones);
      sendJson(res, 201, zone);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  const deliveryZoneMatch = url.pathname.match(/^\/api\/delivery-zones\/([^/]+)$/);
  if (deliveryZoneMatch && (req.method === 'PUT' || req.method === 'DELETE')) {
    const auth = requireAuth(req, res);
    if (!auth) return true;
    if (rejectCashier(auth, res, 'Cashiers cannot manage delivery zones')) return true;

    try {
      const zoneId = decodeURIComponent(deliveryZoneMatch[1]);
      const zones = await readDeliveryZones();
      const zone = findDeliveryZoneById(zones, zoneId);

      if (!zone) {
        sendJson(res, 404, { error: 'Delivery zone not found' });
        return true;
      }

      const restaurantId = zone.restaurant_id || zone.restaurantId || DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return true;
      }

      if (req.method === 'DELETE') {
        await writeDeliveryZones(zones.filter((entry) => String(entry.id) !== String(zoneId)));
        sendJson(res, 200, { ok: true, id: zoneId });
        return true;
      }

      const body = JSON.parse((await readBody(req)) || '{}');
      const nextKitchenId = String(
        body.defaultKitchenId ||
          body.default_kitchen_id ||
          body.kitchenId ||
          body.kitchen_id ||
          zone.defaultKitchenId ||
          zone.default_kitchen_id ||
          '',
      ).trim();

      Object.assign(zone, {
        governorate: String(body.governorate ?? zone.governorate).trim(),
        areaName: String(body.areaName ?? body.area_name ?? zone.areaName).trim(),
        deliveryFee: Number(body.deliveryFee ?? body.delivery_fee ?? zone.deliveryFee) || 0,
        defaultKitchenId: nextKitchenId || null,
        default_kitchen_id: nextKitchenId || null,
        isActive:
          body.isActive === false ||
          body.is_active === false ||
          body.isActive === 0 ||
          body.is_active === 0
            ? false
            : body.isActive != null || body.is_active != null
              ? true
              : zone.isActive !== false,
        updatedAt: new Date().toISOString(),
      });

      if (!zone.governorate || !zone.areaName) {
        sendJson(res, 400, { error: 'Governorate and area name are required' });
        return true;
      }

      if (!zone.defaultKitchenId && !zone.default_kitchen_id) {
        sendJson(res, 400, {
          error: 'A kitchen must be assigned to each delivery zone',
          code: 'KITCHEN_REQUIRED',
        });
        return true;
      }

      await writeDeliveryZones(zones);
      sendJson(res, 200, zone);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return true;
  }

  return false;
}

module.exports = {
  handleDeliveryZoneRoutes,
  normalizeDeliveryZone,
  findDeliveryZoneById,
};
