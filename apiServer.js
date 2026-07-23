const http = require('http');
const fs = require('fs');
const path = require('path');
const {
  persistMenuItemsImages,
  serveMenuImage,
  ensureUploadDir,
} = require('./lib/menuImageStorage');

const PORT = Number(process.env.PORT) || 3000;
const DATA_FILE = path.join(__dirname, 'data', 'menu_items.json');
const ORDERS_FILE = path.join(__dirname, 'data', 'orders.json');
const IS_VERCEL = Boolean(process.env.VERCEL);

let seedItems = [];
let seedOrders = [];
try {
  seedItems = require('./data/menu_items.json');
  if (!Array.isArray(seedItems)) seedItems = [];
} catch {
  seedItems = [];
}
try {
  seedOrders = require('./data/orders.json');
  if (!Array.isArray(seedOrders)) seedOrders = [];
} catch {
  seedOrders = [];
}

let memoryItems = [...seedItems];
let memoryOrders = [...seedOrders];

const categoryIds = new Map();
let nextCategoryId = 1;

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
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

function ensureDataFile() {
  const dir = path.dirname(DATA_FILE);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  if (!fs.existsSync(DATA_FILE)) {
    fs.writeFileSync(DATA_FILE, '[]', 'utf8');
  }
}

function readItems() {
  if (IS_VERCEL) {
    try {
      delete require.cache[require.resolve('./data/menu_items.json')];
      const fresh = require('./data/menu_items.json');
      if (Array.isArray(fresh)) {
        memoryItems = fresh;
      }
    } catch (_) {}
    return memoryItems;
  }

  ensureDataFile();
  const raw = fs.readFileSync(DATA_FILE, 'utf8');
  const parsed = JSON.parse(raw || '[]');
  const items = Array.isArray(parsed) ? parsed : [];
  memoryItems = items;
  return items;
}

function writeItems(items) {
  memoryItems = items;

  if (IS_VERCEL) {
    return;
  }

  ensureDataFile();
  fs.writeFileSync(DATA_FILE, JSON.stringify(items, null, 2), 'utf8');
}

function ensureOrdersFile() {
  const dir = path.dirname(ORDERS_FILE);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  if (!fs.existsSync(ORDERS_FILE)) {
    fs.writeFileSync(ORDERS_FILE, '[]', 'utf8');
  }
}

function readOrders() {
  if (IS_VERCEL) {
    return memoryOrders;
  }

  ensureOrdersFile();
  const raw = fs.readFileSync(ORDERS_FILE, 'utf8');
  const parsed = JSON.parse(raw || '[]');
  const orders = Array.isArray(parsed) ? parsed : [];
  memoryOrders = orders;
  return orders;
}

function writeOrders(orders) {
  memoryOrders = orders;

  if (IS_VERCEL) {
    return;
  }

  ensureOrdersFile();
  fs.writeFileSync(ORDERS_FILE, JSON.stringify(orders, null, 2), 'utf8');
}

function normalizeOrder(raw, id) {
  const createdAt = raw.createdAt || new Date().toISOString();
  return {
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
  };
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

function normalizeIncoming(raw, index) {
  const categoryName =
    raw.category_name || raw.categoryName || raw.category || 'عام';
  const talabatId = raw.talabat_id ?? raw.talabatId ?? null;

  return {
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
  };
}

function mergeItems(existing, incoming) {
  const byTalabatId = new Map();
  const byId = new Map();
  const byName = new Map();

  for (const item of existing) {
    if (item.talabat_id != null) byTalabatId.set(String(item.talabat_id), item);
    byId.set(String(item.id), item);
    byName.set(String(item.name || '').trim().toLowerCase(), item);
  }

  const merged = [...existing];

  incoming.forEach((raw, index) => {
    const item = normalizeIncoming(raw, index);
    if (!item.name) return;

    const talabatKey = item.talabat_id != null ? String(item.talabat_id) : null;
    let existingItem = talabatKey ? byTalabatId.get(talabatKey) : null;
    if (!existingItem) {
      existingItem = byId.get(String(item.id)) || byName.get(item.name.toLowerCase());
    }

    if (existingItem) {
      Object.assign(existingItem, item, { id: existingItem.id });
      if (talabatKey) byTalabatId.set(talabatKey, existingItem);
      byName.set(item.name.toLowerCase(), existingItem);
      return;
    }

    merged.push(item);
    byId.set(String(item.id), item);
    if (talabatKey) byTalabatId.set(talabatKey, item);
    byName.set(item.name.toLowerCase(), item);
  });

  return merged.filter((item) => item.name);
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    sendJson(res, 204, {});
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host}`);

  const menuImageMatch = url.pathname.match(/^\/menu-images\/([^/]+)$/);
  if (req.method === 'GET' && menuImageMatch) {
    serveMenuImage(res, decodeURIComponent(menuImageMatch[1]));
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/health') {
    const items = readItems();
    sendJson(res, 200, { ok: true, service: 'almenupro-api', items: items.length });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/items') {
    const items = readItems();
    rebuildCategoryIds(items);
    sendJson(res, 200, items);
    return;
  }

  const menuImageApiMatch = url.pathname.match(/^\/api\/menu-image\/([^/]+)$/);
  if (req.method === 'GET' && menuImageApiMatch) {
    serveMenuImage(res, decodeURIComponent(menuImageApiMatch[1]));
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
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const incoming = Array.isArray(body.items) ? body.items : [];
      const downloadImages = body.downloadImages !== false;
      const normalizedIncoming = incoming.map((raw, index) => normalizeIncoming(raw, index));
      const preparedIncoming = downloadImages
        ? await persistMenuItemsImages(normalizedIncoming)
        : normalizedIncoming;
      const existing = readItems();
      const merged = mergeItems(existing, preparedIncoming);
      rebuildCategoryIds(merged);
      writeItems(merged);
      sendJson(res, 200, {
        ok: true,
        total: merged.length,
        synced: incoming.length,
        imagesStoredLocally: preparedIncoming.filter((item) =>
          String(item.image_url || '').startsWith('/api/uploads/menu/'),
        ).length,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/orders') {
    const orders = sortOrdersDesc(readOrders());
    sendJson(res, 200, orders);
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/orders') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const id = `ord_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
      const order = normalizeOrder(body, id);
      const orders = readOrders();
      orders.unshift(order);
      writeOrders(orders);
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

      const orders = readOrders();
      const index = orders.findIndex((order) => String(order.id) === orderId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Order not found' });
        return;
      }

      orders[index] = { ...orders[index], status: nextStatus };
      writeOrders(orders);
      sendJson(res, 200, orders[index]);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  sendJson(res, 404, { error: 'Not found' });
});

ensureDataFile();
ensureOrdersFile();
ensureUploadDir();
if (!IS_VERCEL && memoryItems.length === 0) {
  memoryItems = readItems();
}
if (!IS_VERCEL && memoryOrders.length === 0) {
  memoryOrders = readOrders();
}
rebuildCategoryIds(memoryItems);

module.exports = server;

if (require.main === module) {
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`Almenupro API running at http://127.0.0.1:${PORT}`);
    console.log(`GET  http://127.0.0.1:${PORT}/api/items`);
  });
}
