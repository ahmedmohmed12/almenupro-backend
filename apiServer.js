const http = require('http');
const fs = require('fs');
const path = require('path');
const {
  persistMenuItemsImages,
  serveMenuImage,
  ensureUploadDir,
} = require('./lib/menuImageStorage');
const {
  ROLES,
  DEFAULT_RESTAURANT_ID,
  loginSuperAdmin,
  loginRestaurantAdmin,
  parseAuthHeader,
  verifyToken,
  buildAuthResponse,
  isSuperAdmin,
  isRestaurantAdmin,
  canAccessRestaurant,
  resolveRestaurantId,
  authError,
} = require('./lib/adminAuth');
const {
  ensureRestaurantId,
  filterByRestaurant,
  migrateSettingsShape,
  defaultSettingsPayload,
  sanitizeRestaurant,
  createRestaurantRecord,
  resolveRestaurantFromQuery,
  assertRestaurantAccess,
  nextNumericItemId,
} = require('./lib/tenantStore');

function warmMenuImageBundle() {
  const roots = [
    path.join(__dirname, 'uploads', 'menu'),
    path.join(__dirname, 'public', 'menu-images'),
  ];

  for (const root of roots) {
    if (!fs.existsSync(root)) continue;
    for (const filename of fs.readdirSync(root)) {
      if (filename.startsWith('.')) continue;
      try {
        fs.readFileSync(path.join(root, filename));
      } catch (_) {}
    }
  }
}

warmMenuImageBundle();

const { scrapeTalabatMenu } = require('./lib/talabatScraper');
const {
  initDataStore,
  usesMongo,
  readItems,
  writeItems,
  readOrders,
  writeOrders,
  readRestaurants,
  writeRestaurants,
  readSettingsMap,
  writeSettingsMap,
} = require('./lib/dataStore');

const PORT = Number(process.env.PORT) || 3000;
const IS_VERCEL = Boolean(process.env.VERCEL);

const categoryIds = new Map();
let nextCategoryId = 1;
let storeReady = initDataStore();

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Restaurant-Id',
  });
  res.end(JSON.stringify(payload));
}

const ALLOWED_IMAGE_HOSTS = new Set([
  'images.deliveryhero.io',
  'deliveryhero.io',
]);

function isAllowedImageUrl(rawUrl) {
  try {
    const parsed = new URL(rawUrl);
    if (parsed.protocol !== 'https:') return false;
    const host = parsed.hostname.toLowerCase();
    return [...ALLOWED_IMAGE_HOSTS].some(
      (allowed) => host === allowed || host.endsWith(`.${allowed}`),
    );
  } catch {
    return false;
  }
}

async function proxyImage(res, rawUrl) {
  if (!isAllowedImageUrl(rawUrl)) {
    sendJson(res, 400, { error: 'Invalid or disallowed image URL' });
    return;
  }

  try {
    const upstream = await fetch(rawUrl, {
      headers: {
        'User-Agent': 'AlmenuproImageProxy/1.0',
        Accept: 'image/*,*/*;q=0.8',
      },
    });

    if (!upstream.ok) {
      sendJson(res, upstream.status, { error: 'Failed to fetch image' });
      return;
    }

    const contentType = upstream.headers.get('content-type') || 'image/jpeg';
    const buffer = Buffer.from(await upstream.arrayBuffer());

    res.writeHead(200, {
      'Content-Type': contentType,
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'public, max-age=86400, immutable',
    });
    res.end(buffer);
  } catch (error) {
    sendJson(res, 502, { error: error.message || 'Image proxy failed' });
  }
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

function normalizeSettings(raw) {
  const base = defaultSettingsPayload();
  const source = raw && typeof raw === 'object' ? raw : {};
  const workingHours = Array.isArray(source.workingHours) && source.workingHours.length
    ? source.workingHours
    : base.workingHours;

  return {
    whatsappNumber: String(source.whatsappNumber || source.whatsapp_number || base.whatsappNumber).trim(),
    workingHours: workingHours.map((day) => ({
      weekday: Number(day.weekday) || 6,
      isOpen: day.isOpen !== false && day.is_open !== false,
      open: String(day.open || day.openTime || '10:00'),
      close: String(day.close || day.closeTime || '22:00'),
    })),
    updatedAt: source.updatedAt || new Date().toISOString(),
  };
}

async function readSettings(restaurantId = DEFAULT_RESTAURANT_ID) {
  const map = await readSettingsMap();
  const scoped = map.byRestaurant?.[restaurantId];
  return normalizeSettings(scoped || defaultSettingsPayload());
}

async function writeSettings(restaurantId, settings) {
  const map = await readSettingsMap();
  if (!map.byRestaurant || typeof map.byRestaurant !== 'object') {
    map.byRestaurant = {};
  }
  map.byRestaurant[restaurantId] = normalizeSettings(settings);
  await writeSettingsMap(map);
  return map.byRestaurant[restaurantId];
}

function normalizeOrder(raw, id, restaurantId = DEFAULT_RESTAURANT_ID) {
  const createdAt = raw.createdAt || new Date().toISOString();
  return ensureRestaurantId(
    {
      id: String(id),
      customerName: String(raw.customerName || raw.customer_name || '').trim(),
      phone: String(raw.phone || '').trim(),
      address: String(raw.address || '').trim(),
      items: Array.isArray(raw.items) ? raw.items : [],
      totalPrice: Number(raw.totalPrice ?? raw.total_price ?? 0) || 0,
      orderType: String(raw.orderType || raw.order_type || 'Delivery'),
      status: String(raw.status || 'pending'),
      createdAt,
      invoiceNumber: raw.invoiceNumber?.toString() || raw.invoice_number?.toString() || null,
      paymentMethod: raw.paymentMethod?.toString() || raw.payment_method?.toString() || null,
    },
    raw.restaurant_id || raw.restaurantId || restaurantId,
  );
}

function sortOrdersDesc(orders) {
  return [...orders].sort((a, b) => {
    const aTime = Date.parse(a.createdAt || 0);
    const bTime = Date.parse(b.createdAt || 0);
    return bTime - aTime;
  });
}

function categoryIdFor(name) {
  const key = String(name || 'عام').trim() || 'عام';
  if (!categoryIds.has(key)) {
    categoryIds.set(key, nextCategoryId++);
  }
  return categoryIds.get(key);
}

function rebuildCategoryIds(items) {
  categoryIds.clear();
  nextCategoryId = 1;
  for (const item of items) {
    categoryIdFor(item.category_name);
  }
}

function normalizeIncoming(raw, index, restaurantId = DEFAULT_RESTAURANT_ID) {
  const categoryName =
    raw.category_name || raw.categoryName || raw.category || 'عام';
  const talabatId = raw.talabat_id ?? raw.talabatId ?? null;

  return ensureRestaurantId(
    {
      id: Number(raw.id ?? talabatId ?? index + 1),
      category_id: Number(raw.category_id ?? raw.categoryId ?? categoryIdFor(categoryName)),
      category_name: String(categoryName).trim() || 'عام',
      name: String(raw.name || '').trim(),
      description: String(raw.description || ''),
      price: Number(raw.price) || 0,
      image_url: String(raw.image_url || raw.imageUrl || ''),
      is_available:
        raw.is_available === 0 || raw.is_available === false || raw.isAvailable === false
          ? 0
          : 1,
      talabat_id: talabatId,
      source: raw.source || 'Talabat',
    },
    restaurantId,
  );
}

function mergeItems(existing, incoming, restaurantId = DEFAULT_RESTAURANT_ID) {
  const scopedExisting = filterByRestaurant(existing, restaurantId);
  const otherRestaurants = existing.filter(
    (item) =>
      String(item.restaurant_id || item.restaurantId || DEFAULT_RESTAURANT_ID) !==
      String(restaurantId),
  );

  const byTalabatId = new Map();
  const byId = new Map();
  const byName = new Map();
  let added = 0;
  let updated = 0;
  let skipped = 0;

  for (const item of scopedExisting) {
    if (item.talabat_id != null) byTalabatId.set(String(item.talabat_id), item);
    byId.set(String(item.id), item);
    byName.set(String(item.name || '').trim().toLowerCase(), item);
  }

  const merged = [...scopedExisting];

  incoming.forEach((raw, index) => {
    const item = normalizeIncoming(raw, index, restaurantId);
    if (!item.name) {
      skipped += 1;
      return;
    }

    const talabatKey = item.talabat_id != null ? String(item.talabat_id) : null;
    let existingItem = talabatKey ? byTalabatId.get(talabatKey) : null;
    if (!existingItem) {
      existingItem = byId.get(String(item.id)) || byName.get(item.name.toLowerCase());
    }

    if (existingItem) {
      Object.assign(existingItem, item, { id: existingItem.id });
      if (talabatKey) byTalabatId.set(talabatKey, existingItem);
      byName.set(item.name.toLowerCase(), existingItem);
      updated += 1;
      return;
    }

    merged.push(item);
    added += 1;
    byId.set(String(item.id), item);
    if (talabatKey) byTalabatId.set(talabatKey, item);
    byName.set(item.name.toLowerCase(), item);
  });

  return {
    items: [...otherRestaurants, ...merged.filter((item) => item.name)],
    added,
    updated,
    skipped,
  };
}

function requireAuth(req, res) {
  const auth = parseAuthHeader(req);
  if (!auth) {
    authError(res, 401, 'Unauthorized');
    return null;
  }
  return auth;
}

function requireSuperAdmin(req, res) {
  const auth = requireAuth(req, res);
  if (!auth) return null;
  if (!isSuperAdmin(auth)) {
    authError(res, 403, 'Super admin access required');
    return null;
  }
  return auth;
}

async function resolveScopedRestaurantId(req, url, auth, { allowPublicDefault = false } = {}) {
  const restaurants = await readRestaurants();
  const slugParam =
    url.searchParams.get('restaurant_slug') || url.searchParams.get('slug');
  const restaurantIdParam =
    url.searchParams.get('restaurant_id') || req.headers['x-restaurant-id'];

  if (slugParam) {
    const match = restaurants.find(
      (entry) =>
        String(entry.slug || '').toLowerCase() === String(slugParam).toLowerCase(),
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

function findItemById(items, itemId) {
  return items.find((item) => String(item.id) === String(itemId));
}

const server = http.createServer(async (req, res) => {
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

  const url = new URL(req.url, `http://${req.headers.host}`);

  if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '')) {
    sendJson(res, 200, {
      ok: true,
      service: 'almenupro-api',
      message: 'Almenupro backend is running.',
      endpoints: {
        health: '/api/health',
        auth: '/api/auth/login',
        restaurants: '/api/restaurants',
        restaurantPublic: '/api/restaurants/public/{slug}',
        menu: '/api/items?slug={slug}',
        orders: '/api/orders',
        settings: '/api/settings',
        images: '/menu-images/{filename}',
      },
      frontend: 'https://almenupro-frontend-three.vercel.app',
      admin: 'https://almenupro-frontend-three.vercel.app/admin',
    });
    return;
  }

  const menuImageMatch = url.pathname.match(/^\/menu-images\/([^/]+)$/);
  if (req.method === 'GET' && menuImageMatch) {
    serveMenuImage(res, decodeURIComponent(menuImageMatch[1]));
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/auth/login') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      let session = null;

      if (body.username != null || body.user != null) {
        session = loginSuperAdmin(body.username ?? body.user, body.password);
      } else if (body.restaurantSlug != null || body.restaurant_slug != null) {
        session = loginRestaurantAdmin(
          body.restaurantSlug ?? body.restaurant_slug,
          body.password,
          await readRestaurants(),
        );
      }

      if (!session) {
        sendJson(res, 401, { error: 'Invalid credentials' });
        return;
      }

      sendJson(res, 200, session);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/auth/me') {
    const auth = requireAuth(req, res);
    if (!auth) return;

    const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    const session = buildAuthResponse(token);
    sendJson(res, 200, session || auth);
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/restaurants') {
    const auth = requireSuperAdmin(req, res);
    if (!auth) return;

    const restaurants = (await readRestaurants()).map(sanitizeRestaurant);
    sendJson(res, 200, restaurants);
    return;
  }

  const publicRestaurantMatch = url.pathname.match(
    /^\/api\/restaurants\/public\/([^/]+)$/,
  );
  if (req.method === 'GET' && publicRestaurantMatch) {
    const slug = decodeURIComponent(publicRestaurantMatch[1]).trim().toLowerCase();
    const restaurants = await readRestaurants();
    const match = restaurants.find(
      (entry) =>
        String(entry.slug || '').toLowerCase() === slug &&
        String(entry.status || 'active') !== 'inactive',
    );

    if (!match) {
      sendJson(res, 404, { error: 'Restaurant not found' });
      return;
    }

    sendJson(res, 200, sanitizeRestaurant(match));
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/restaurants') {
    const auth = requireSuperAdmin(req, res);
    if (!auth) return;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurants = await readRestaurants();
      const record = createRestaurantRecord(body);

      if (
        restaurants.some(
          (entry) => String(entry.slug).toLowerCase() === String(record.slug).toLowerCase(),
        )
      ) {
        sendJson(res, 409, { error: 'Restaurant slug already exists' });
        return;
      }

      restaurants.push(record);
      await writeRestaurants(restaurants);
      await writeSettings(record.id, defaultSettingsPayload());

      sendJson(res, 201, sanitizeRestaurant(record));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/health') {
    const items = await readItems();
    const { resolveImageDiskPath } = require('./lib/menuImageStorage');
    sendJson(res, 200, {
      ok: true,
      service: 'almenupro-api',
      storage: usesMongo() ? 'mongodb' : IS_VERCEL ? 'ephemeral-json' : 'filesystem',
      items: items.length,
      imagesReady: Boolean(resolveImageDiskPath('1962105681.jpg')),
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/items') {
    const auth = parseAuthHeader(req);
    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: true,
    });

    if (!restaurantId) {
      const slugParam =
        url.searchParams.get('restaurant_slug') || url.searchParams.get('slug');
      if (slugParam) {
        sendJson(res, 404, { error: 'Restaurant not found' });
      } else {
        authError(res, 401, 'Restaurant context required');
      }
      return;
    }

    if (auth && !canAccessRestaurant(auth, restaurantId)) {
      authError(res, 403, 'Access denied for this restaurant');
      return;
    }

    const items = filterByRestaurant(await readItems(), restaurantId);
    rebuildCategoryIds(items);
    sendJson(res, 200, items);
    return;
  }

  const itemImageMatch = url.pathname.match(/^\/api\/items\/image\/([^/]+)$/);
  if (req.method === 'GET' && itemImageMatch) {
    serveMenuImage(res, decodeURIComponent(itemImageMatch[1]));
    return;
  }

  const menuImageApiMatch = url.pathname.match(/^\/api\/menu-image\/([^/]+)$/);
  if (req.method === 'GET' && menuImageApiMatch) {
    serveMenuImage(res, decodeURIComponent(menuImageApiMatch[1]));
    return;
  }

  const menuImageShortMatch = url.pathname.match(/^\/menu-image\/([^/]+)$/);
  if (req.method === 'GET' && menuImageShortMatch) {
    serveMenuImage(res, decodeURIComponent(menuImageShortMatch[1]));
    return;
  }

  const uploadMatch = url.pathname.match(/^\/api\/uploads\/menu\/([^/]+)$/);
  if (req.method === 'GET' && uploadMatch) {
    serveMenuImage(res, decodeURIComponent(uploadMatch[1]));
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/image-proxy') {
    const imageUrl = url.searchParams.get('url');
    if (!imageUrl) {
      sendJson(res, 400, { error: 'Missing url query parameter' });
      return;
    }
    await proxyImage(res, imageUrl);
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/items/sync') {
    const auth = requireSuperAdmin(req, res);
    if (!auth) return;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const incoming = Array.isArray(body.items) ? body.items : [];
      const downloadImages = body.downloadImages !== false;
      const restaurantId = String(
        body.restaurantId || body.restaurant_id || DEFAULT_RESTAURANT_ID,
      );

      const restaurants = await readRestaurants();
      if (!restaurants.some((entry) => entry.id === restaurantId)) {
        sendJson(res, 404, { error: 'Restaurant not found' });
        return;
      }

      const normalizedIncoming = incoming.map((raw, index) =>
        normalizeIncoming(raw, index, restaurantId),
      );
      const preparedIncoming = downloadImages
        ? await persistMenuItemsImages(normalizedIncoming)
        : normalizedIncoming;
      const existing = await readItems();
      const mergeResult = mergeItems(existing, preparedIncoming, restaurantId);
      rebuildCategoryIds(filterByRestaurant(mergeResult.items, restaurantId));
      await writeItems(mergeResult.items);
      sendJson(res, 200, {
        ok: true,
        restaurantId,
        total: filterByRestaurant(mergeResult.items, restaurantId).length,
        synced: incoming.length,
        added: mergeResult.added,
        updated: mergeResult.updated,
        skipped: mergeResult.skipped,
        imagesStoredLocally: preparedIncoming.filter((item) =>
          String(item.image_url || '').startsWith('/api/uploads/menu/'),
        ).length,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/talabat/import') {
    const auth = requireSuperAdmin(req, res);
    if (!auth) return;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const inputUrl = String(body.url || body.menuUrl || '').trim();
      const downloadImages = body.downloadImages !== false;
      const restaurantId = String(
        body.restaurantId || body.restaurant_id || DEFAULT_RESTAURANT_ID,
      );

      if (!inputUrl) {
        sendJson(res, 400, { error: 'Missing Talabat menu URL' });
        return;
      }

      const restaurants = await readRestaurants();
      if (!restaurants.some((entry) => entry.id === restaurantId)) {
        sendJson(res, 404, { error: 'Restaurant not found' });
        return;
      }

      const scrapeResult = await scrapeTalabatMenu(inputUrl);
      const incoming = Array.isArray(scrapeResult.items) ? scrapeResult.items : [];

      if (!incoming.length) {
        sendJson(res, 400, { error: 'No menu items found at this Talabat URL' });
        return;
      }

      const normalizedIncoming = incoming.map((raw, index) =>
        normalizeIncoming(raw, index, restaurantId),
      );
      const preparedIncoming = downloadImages
        ? await persistMenuItemsImages(normalizedIncoming)
        : normalizedIncoming;
      const existing = await readItems();
      const mergeResult = mergeItems(existing, preparedIncoming, restaurantId);
      rebuildCategoryIds(filterByRestaurant(mergeResult.items, restaurantId));
      await writeItems(mergeResult.items);

      sendJson(res, 200, {
        ok: true,
        menuUrl: scrapeResult.menuUrl,
        restaurantId,
        total: filterByRestaurant(mergeResult.items, restaurantId).length,
        synced: incoming.length,
        added: mergeResult.added,
        updated: mergeResult.updated,
        skipped: mergeResult.skipped,
        imagesStoredLocally: preparedIncoming.filter((item) =>
          String(item.image_url || '').startsWith('/api/uploads/menu/'),
        ).length,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Talabat import failed' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/items') {
    const auth = requireAuth(req, res);
    if (!auth) return;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurantId = resolveRestaurantId(
        auth,
        body.restaurantId ||
          body.restaurant_id ||
          req.headers['x-restaurant-id'],
      );

      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return;
      }

      const items = await readItems();
      const scoped = filterByRestaurant(items, restaurantId);
      const categoryName = body.categoryName || body.category_name || 'عام';
      const item = ensureRestaurantId(
        {
          id: nextNumericItemId(scoped),
          category_id: categoryIdFor(categoryName),
          category_name: String(categoryName).trim() || 'عام',
          name: String(body.name || '').trim(),
          description: String(body.description || ''),
          price: Number(body.price) || 0,
          image_url: String(body.image_url || body.imageUrl || ''),
          is_available:
            body.is_available === 0 ||
            body.is_available === false ||
            body.isAvailable === false
              ? 0
              : 1,
          source: body.source || 'Manual',
        },
        restaurantId,
      );

      if (!item.name) {
        sendJson(res, 400, { error: 'Item name is required' });
        return;
      }

      items.push(item);
      await writeItems(items);
      sendJson(res, 201, item);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  const itemMatch = url.pathname.match(/^\/api\/items\/([^/]+)$/);
  if (itemMatch && (req.method === 'PUT' || req.method === 'DELETE')) {
    const auth = requireAuth(req, res);
    if (!auth) return;

    try {
      const itemId = decodeURIComponent(itemMatch[1]);
      const items = await readItems();
      const item = findItemById(items, itemId);

      if (!item) {
        sendJson(res, 404, { error: 'Item not found' });
        return;
      }

      const restaurantId = item.restaurant_id || item.restaurantId || DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return;
      }

      if (req.method === 'DELETE') {
        await writeItems(items.filter((entry) => String(entry.id) !== String(itemId)));
        sendJson(res, 200, { ok: true, id: itemId });
        return;
      }

      const body = JSON.parse((await readBody(req)) || '{}');
      const categoryName =
        body.categoryName || body.category_name || item.category_name || 'عام';

      Object.assign(item, {
        name: String(body.name ?? item.name).trim(),
        description: String(body.description ?? item.description ?? ''),
        price: Number(body.price ?? item.price) || 0,
        category_name: String(categoryName).trim() || 'عام',
        category_id: Number(body.category_id ?? body.categoryId ?? categoryIdFor(categoryName)),
        image_url: String(body.image_url ?? body.imageUrl ?? item.image_url ?? ''),
        is_available:
          body.is_available === 0 ||
          body.is_available === false ||
          body.isAvailable === false
            ? 0
            : body.is_available != null || body.isAvailable != null
              ? 1
              : item.is_available,
        source: body.source || item.source || 'Manual',
      });

      await writeItems(items);
      sendJson(res, 200, item);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  const itemAvailabilityMatch = url.pathname.match(/^\/api\/items\/([^/]+)\/availability$/);
  if (req.method === 'PATCH' && itemAvailabilityMatch) {
    const auth = requireAuth(req, res);
    if (!auth) return;

    try {
      const itemId = decodeURIComponent(itemAvailabilityMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const items = await readItems();
      const item = findItemById(items, itemId);

      if (!item) {
        sendJson(res, 404, { error: 'Item not found' });
        return;
      }

      const restaurantId = item.restaurant_id || item.restaurantId || DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return;
      }

      const nextAvailable =
        body.is_available ?? body.isAvailable ?? body.available ?? item.is_available;
      item.is_available =
        nextAvailable === 0 || nextAvailable === false || nextAvailable === '0' ? 0 : 1;

      await writeItems(items);
      sendJson(res, 200, item);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/orders') {
    const auth = requireAuth(req, res);
    if (!auth) return;

    if (isSuperAdmin(auth)) {
      authError(res, 403, 'Orders are managed by restaurant admins only');
      return;
    }

    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return;
    }

    const orders = sortOrdersDesc(filterByRestaurant(await readOrders(), restaurantId));
    sendJson(res, 200, orders);
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/orders') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurants = await readRestaurants();
      let restaurantId =
        body.restaurantId ||
        body.restaurant_id ||
        resolveRestaurantFromQuery(url, restaurants);

      if (!restaurantId && (body.restaurantSlug || body.restaurant_slug)) {
        const slug = String(body.restaurantSlug || body.restaurant_slug).trim();
        const match = restaurants.find(
          (entry) => String(entry.slug || '').toLowerCase() === slug.toLowerCase(),
        );
        restaurantId = match ? match.id : null;
      }

      if (!restaurantId) {
        sendJson(res, 404, { error: 'Restaurant not found' });
        return;
      }
      const id = `ord_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
      const order = normalizeOrder(body, id, restaurantId);
      const orders = await readOrders();
      orders.unshift(order);
      await writeOrders(orders);
      sendJson(res, 201, order);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  const orderStatusMatch = url.pathname.match(/^\/api\/orders\/([^/]+)\/status$/);
  if (req.method === 'PATCH' && orderStatusMatch) {
    try {
      const orderId = decodeURIComponent(orderStatusMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const nextStatus = String(body.status || '').trim();
      if (!nextStatus) {
        sendJson(res, 400, { error: 'Missing status' });
        return;
      }

      const orders = await readOrders();
      const index = orders.findIndex((order) => String(order.id) === orderId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Order not found' });
        return;
      }

      const auth = requireAuth(req, res);
      if (!auth) return;

      if (isSuperAdmin(auth)) {
        authError(res, 403, 'Orders are managed by restaurant admins only');
        return;
      }

      const restaurantId =
        orders[index].restaurant_id ||
        orders[index].restaurantId ||
        DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return;
      }

      orders[index] = { ...orders[index], status: nextStatus };
      await writeOrders(orders);
      sendJson(res, 200, orders[index]);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/settings') {
    const auth = parseAuthHeader(req);
    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: true,
    });

    if (!restaurantId) {
      const slugParam =
        url.searchParams.get('restaurant_slug') || url.searchParams.get('slug');
      if (slugParam) {
        sendJson(res, 404, { error: 'Restaurant not found' });
      } else {
        authError(res, 401, 'Restaurant context required');
      }
      return;
    }

    if (auth && !canAccessRestaurant(auth, restaurantId)) {
      authError(res, 403, 'Access denied for this restaurant');
      return;
    }

    sendJson(res, 200, await readSettings(restaurantId));
    return;
  }

  if (req.method === 'PUT' && url.pathname === '/api/settings') {
    const auth = requireAuth(req, res);
    if (!auth) return;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurantId = resolveRestaurantId(
        auth,
        body.restaurantId ||
          body.restaurant_id ||
          url.searchParams.get('restaurant_id') ||
          req.headers['x-restaurant-id'],
      );

      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return;
      }

      const current = await readSettings(restaurantId);
      const merged = await writeSettings(restaurantId, {
        ...current,
        ...body,
        workingHours: Array.isArray(body.workingHours)
          ? body.workingHours
          : current.workingHours,
        updatedAt: new Date().toISOString(),
      });
      sendJson(res, 200, merged);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  sendJson(res, 404, { error: 'Not found' });
});

ensureUploadDir();
storeReady = storeReady.then(async () => {
  const items = await readItems();
  rebuildCategoryIds(items);
});

module.exports = server;

if (require.main === module) {
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`Almenupro API running at http://127.0.0.1:${PORT}`);
    console.log(`GET  http://127.0.0.1:${PORT}/api/items`);
  });
}
