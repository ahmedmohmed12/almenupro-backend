const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.env.PORT) || 3000;
const DATA_FILE = path.join(__dirname, 'data', 'menu_items.json');

const categoryIds = new Map();
let nextCategoryId = 1;

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
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
  ensureDataFile();
  const raw = fs.readFileSync(DATA_FILE, 'utf8');
  const parsed = JSON.parse(raw || '[]');
  return Array.isArray(parsed) ? parsed : [];
}

function writeItems(items) {
  ensureDataFile();
  fs.writeFileSync(DATA_FILE, JSON.stringify(items, null, 2), 'utf8');
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

  if (req.method === 'POST' && url.pathname === '/api/items/sync') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const incoming = Array.isArray(body.items) ? body.items : [];
      const existing = readItems();
      const merged = mergeItems(existing, incoming);
      rebuildCategoryIds(merged);
      writeItems(merged);
      sendJson(res, 200, {
        ok: true,
        total: merged.length,
        synced: incoming.length,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  sendJson(res, 404, { error: 'Not found' });
});

ensureDataFile();
rebuildCategoryIds(readItems());

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Almenupro API running at http://127.0.0.1:${PORT}`);
  console.log(`GET  http://127.0.0.1:${PORT}/api/items`);
});
