const fs = require('fs');
const path = require('path');
const { MongoClient } = require('mongodb');
const { ensureRestaurantId, migrateSettingsShape, defaultSettingsPayload } = require('./tenantStore');
const { DEFAULT_RESTAURANT_ID } = require('./adminAuth');
const {
  itemNeedsBilingualMigration,
  migrateMenuItem,
} = require('./bilingualMenu');
const {
  autoTranslateMenuItems,
  itemNeedsAutoTranslation,
} = require('./bilingualItemMigration');

const DATA_DIR = path.join(__dirname, '..', 'data');
const FILES = {
  menuItems: path.join(DATA_DIR, 'menu_items.json'),
  orders: path.join(DATA_DIR, 'orders.json'),
  settings: path.join(DATA_DIR, 'settings.json'),
  restaurants: path.join(DATA_DIR, 'restaurants.json'),
  deliveryZones: path.join(DATA_DIR, 'delivery_zones.json'),
};

const IS_VERCEL = Boolean(process.env.VERCEL);
const MONGODB_URI = process.env.MONGODB_URI || '';
const MONGODB_DB = process.env.MONGODB_DB || 'almenupro';
const COLLECTION = 'platform_docs';

let mongoClient;
let mongoDb;
let mongoReady = false;
let mongoInitPromise;

const memory = {
  menuItems: [],
  orders: [],
  restaurants: [],
  deliveryZones: [],
  settings: migrateSettingsShape({}),
};

function loadJson(filePath, fallback) {
  try {
    if (!fs.existsSync(filePath)) return fallback;
    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return parsed ?? fallback;
  } catch {
    return fallback;
  }
}

function seedFromFiles() {
  const menuItems = loadJson(FILES.menuItems, []);
  const orders = loadJson(FILES.orders, []);
  const restaurants = loadJson(FILES.restaurants, []);
  const deliveryZones = loadJson(FILES.deliveryZones, []);
  const settings = migrateSettingsShape(loadJson(FILES.settings, {}));

  memory.menuItems = Array.isArray(menuItems)
    ? menuItems.map((item) => ensureRestaurantId(item))
    : [];
  memory.orders = Array.isArray(orders)
    ? orders.map((order) => ensureRestaurantId(order))
    : [];
  memory.restaurants = Array.isArray(restaurants) ? restaurants : [];
  memory.deliveryZones = Array.isArray(deliveryZones)
    ? deliveryZones.map((zone) => ensureRestaurantId(zone))
    : [];
  memory.settings = settings;

  if (!memory.settings.byRestaurant?.[DEFAULT_RESTAURANT_ID]) {
    memory.settings.byRestaurant = memory.settings.byRestaurant || {};
    memory.settings.byRestaurant[DEFAULT_RESTAURANT_ID] = defaultSettingsPayload();
  }
}

function writeJson(filePath, value) {
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2), 'utf8');
}

function usesMongo() {
  return Boolean(MONGODB_URI);
}

function canPersistWrites() {
  return usesMongo() || !IS_VERCEL;
}

function getStorageStatus() {
  if (usesMongo()) {
    return {
      mode: 'mongodb',
      persistent: true,
      message: 'Data is stored in MongoDB.',
    };
  }
  if (IS_VERCEL) {
    return {
      mode: 'ephemeral-json',
      persistent: false,
      message:
        'Vercel serverless memory is not persistent. Set MONGODB_URI in Vercel env vars.',
    };
  }
  return {
    mode: 'filesystem',
    persistent: true,
    message: 'Data is stored on the local filesystem.',
  };
}

function assertCanPersist(action = 'save data') {
  if (canPersistWrites()) return;
  const error = new Error(
    `Persistent storage is required to ${action}. Add MONGODB_URI and MONGODB_DB to Vercel environment variables, then redeploy.`,
  );
  error.code = 'PERSISTENCE_REQUIRED';
  throw error;
}

async function initMongo() {
  if (!usesMongo()) return false;
  if (mongoReady) return true;
  if (mongoInitPromise) return mongoInitPromise;

  mongoInitPromise = (async () => {
    mongoClient = new MongoClient(MONGODB_URI);
    await mongoClient.connect();
    mongoDb = mongoClient.db(MONGODB_DB);
    mongoReady = true;

    const existing = await mongoDb.collection(COLLECTION).countDocuments();
    if (existing === 0) {
      seedFromFiles();
      await persistAllToMongo();
    }
    return true;
  })();

  return mongoInitPromise;
}

async function readDoc(id, fallback) {
  if (usesMongo()) {
    await initMongo();
    const doc = await mongoDb.collection(COLLECTION).findOne({ _id: id });
    return doc?.data ?? fallback;
  }

  return fallback;
}

async function writeDoc(id, data) {
  if (usesMongo()) {
    await initMongo();
    const result = await mongoDb.collection(COLLECTION).updateOne(
      { _id: id },
      { $set: { data, updatedAt: new Date().toISOString() } },
      { upsert: true },
    );
    if (!result.acknowledged) {
      throw new Error(`MongoDB write failed for ${id}`);
    }
    return;
  }

  switch (id) {
    case 'menu_items':
      memory.menuItems = data;
      if (!IS_VERCEL) writeJson(FILES.menuItems, data);
      break;
    case 'orders':
      memory.orders = data;
      if (!IS_VERCEL) writeJson(FILES.orders, data);
      break;
    case 'restaurants':
      memory.restaurants = data;
      if (!IS_VERCEL) writeJson(FILES.restaurants, data);
      break;
    case 'settings':
      memory.settings = data;
      if (!IS_VERCEL) writeJson(FILES.settings, data);
      break;
    case 'delivery_zones':
      memory.deliveryZones = data;
      if (!IS_VERCEL) writeJson(FILES.deliveryZones, data);
      break;
    default:
      break;
  }
}

async function persistAllToMongo() {
  await writeDoc('menu_items', memory.menuItems);
  await writeDoc('orders', memory.orders);
  await writeDoc('restaurants', memory.restaurants);
  await writeDoc('delivery_zones', memory.deliveryZones);
  await writeDoc('settings', memory.settings);
}

async function ensureBilingualMenuItems() {
  const items = await readItems();
  const needsMigration = items.some(
    (item) => itemNeedsBilingualMigration(item) || itemNeedsAutoTranslation(item),
  );

  if (!needsMigration) {
    const normalized = items.map((item) => migrateMenuItem(item));
    const shapeChanged = normalized.some(
      (item, index) => JSON.stringify(item) !== JSON.stringify(items[index]),
    );
    if (shapeChanged) {
      await writeItems(normalized);
      return { updated: normalized.length, total: normalized.length, mode: 'normalize' };
    }
    return { updated: 0, total: items.length, mode: 'none' };
  }

  const { items: migrated, updated, scanned } = await autoTranslateMenuItems(items, {
    delayMs: process.env.VERCEL ? 150 : 200,
    onProgress: (current, total, id, translated) => {
      if (translated) {
        console.log(`Bilingual auto-translate ${current}/${total} item #${id}`);
      }
    },
  });

  if (updated > 0 || needsMigration) {
    await writeItems(migrated);
  }

  return { updated, total: scanned, mode: 'auto-translate' };
}

async function initDataStore() {
  seedFromFiles();

  if (usesMongo()) {
    await initMongo();
    memory.menuItems = (await readDoc('menu_items', memory.menuItems)).map((item) =>
      ensureRestaurantId(item),
    );
    memory.orders = (await readDoc('orders', memory.orders)).map((order) =>
      ensureRestaurantId(order),
    );
    memory.restaurants = await readDoc('restaurants', memory.restaurants);
    memory.deliveryZones = (await readDoc('delivery_zones', memory.deliveryZones)).map((zone) =>
      ensureRestaurantId(zone),
    );
    memory.settings = migrateSettingsShape(await readDoc('settings', memory.settings));
    return;
  }

  if (IS_VERCEL) {
    try {
      delete require.cache[require.resolve('../data/menu_items.json')];
      const freshItems = require('../data/menu_items.json');
      if (Array.isArray(freshItems)) {
        memory.menuItems = freshItems.map((item) => ensureRestaurantId(item));
      }
    } catch (_) {}

    try {
      delete require.cache[require.resolve('../data/restaurants.json')];
      const freshRestaurants = require('../data/restaurants.json');
      if (Array.isArray(freshRestaurants)) {
        memory.restaurants = freshRestaurants;
      }
    } catch (_) {}
  }
}

async function readItems() {
  if (usesMongo()) {
    const items = await readDoc('menu_items', memory.menuItems);
    return Array.isArray(items) ? items.map((item) => ensureRestaurantId(item)) : [];
  }

  if (IS_VERCEL) {
    return memory.menuItems.map((item) => ensureRestaurantId(item));
  }

  const items = loadJson(FILES.menuItems, memory.menuItems);
  memory.menuItems = Array.isArray(items)
    ? items.map((item) => ensureRestaurantId(item))
    : [];
  return memory.menuItems;
}

async function writeItems(items) {
  const normalized = items.map((item) => ensureRestaurantId(item));
  memory.menuItems = normalized;
  await writeDoc('menu_items', normalized);
}

async function readOrders() {
  if (usesMongo()) {
    const orders = await readDoc('orders', memory.orders);
    return Array.isArray(orders) ? orders.map((order) => ensureRestaurantId(order)) : [];
  }

  if (IS_VERCEL) {
    return memory.orders.map((order) => ensureRestaurantId(order));
  }

  const orders = loadJson(FILES.orders, memory.orders);
  memory.orders = Array.isArray(orders)
    ? orders.map((order) => ensureRestaurantId(order))
    : [];
  return memory.orders;
}

async function writeOrders(orders) {
  const normalized = orders.map((order) => ensureRestaurantId(order));
  memory.orders = normalized;
  await writeDoc('orders', normalized);
}

async function readRestaurants() {
  if (usesMongo()) {
    const restaurants = await readDoc('restaurants', memory.restaurants);
    return Array.isArray(restaurants) ? restaurants : [];
  }

  if (IS_VERCEL) {
    return memory.restaurants;
  }

  const restaurants = loadJson(FILES.restaurants, memory.restaurants);
  memory.restaurants = Array.isArray(restaurants) ? restaurants : [];
  return memory.restaurants;
}

async function writeRestaurants(restaurants) {
  assertCanPersist('save restaurants');
  if (!Array.isArray(restaurants)) {
    throw new Error('restaurants must be an array');
  }
  memory.restaurants = restaurants;
  await writeDoc('restaurants', restaurants);
  return restaurants;
}

async function readSettingsMap() {
  if (usesMongo()) {
    return migrateSettingsShape(await readDoc('settings', memory.settings));
  }

  if (IS_VERCEL) {
    return migrateSettingsShape(memory.settings);
  }

  memory.settings = migrateSettingsShape(loadJson(FILES.settings, memory.settings));
  return memory.settings;
}

async function writeSettingsMap(map) {
  memory.settings = migrateSettingsShape(map);
  await writeDoc('settings', memory.settings);
  return memory.settings;
}

async function readDeliveryZones() {
  if (usesMongo()) {
    let zones = await readDoc('delivery_zones', memory.deliveryZones);
    zones = Array.isArray(zones) ? zones.map((zone) => ensureRestaurantId(zone)) : [];
    if (zones.length === 0) {
      const seed = loadJson(FILES.deliveryZones, []);
      if (Array.isArray(seed) && seed.length > 0) {
        zones = seed.map((zone) => ensureRestaurantId(zone));
        await writeDeliveryZones(zones);
      }
    }
    return zones;
  }

  if (IS_VERCEL) {
    return memory.deliveryZones.map((zone) => ensureRestaurantId(zone));
  }

  const zones = loadJson(FILES.deliveryZones, memory.deliveryZones);
  memory.deliveryZones = Array.isArray(zones)
    ? zones.map((zone) => ensureRestaurantId(zone))
    : [];
  return memory.deliveryZones;
}

async function writeDeliveryZones(zones) {
  const normalized = zones.map((zone) => ensureRestaurantId(zone));
  memory.deliveryZones = normalized;
  await writeDoc('delivery_zones', normalized);
}

module.exports = {
  initDataStore,
  usesMongo,
  canPersistWrites,
  ensureBilingualMenuItems,
  getStorageStatus,
  readItems,
  writeItems,
  readOrders,
  writeOrders,
  readRestaurants,
  writeRestaurants,
  readSettingsMap,
  writeSettingsMap,
  readDeliveryZones,
  writeDeliveryZones,
};
