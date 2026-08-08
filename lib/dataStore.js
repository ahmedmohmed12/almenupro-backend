const fs = require('fs');
const path = require('path');
const { MongoClient } = require('mongodb');
const { ensureRestaurantId, migrateSettingsShape, defaultSettingsPayload } = require('./tenantStore');
const { DEFAULT_RESTAURANT_ID } = require('./adminAuth');
const { migrateMenuItems } = require('./bilingualMenu');
const { autoTranslateMenuItems } = require('./bilingualItemMigration');
const { migrateCustomersFromOrders } = require('./customersStore');

const DATA_DIR = path.join(__dirname, '..', 'data');
const FILES = {
  menuItems: path.join(DATA_DIR, 'menu_items.json'),
  orders: path.join(DATA_DIR, 'orders.json'),
  customers: path.join(DATA_DIR, 'customers.json'),
  settings: path.join(DATA_DIR, 'settings.json'),
  restaurants: path.join(DATA_DIR, 'restaurants.json'),
  deliveryZones: path.join(DATA_DIR, 'delivery_zones.json'),
  kitchens: path.join(DATA_DIR, 'kitchens.json'),
  staffUsers: path.join(DATA_DIR, 'staff_users.json'),
  shiftSessions: path.join(DATA_DIR, 'shift_sessions.json'),
  auditEvents: path.join(DATA_DIR, 'audit_events.json'),
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
  customers: [],
  restaurants: [],
  deliveryZones: [],
  kitchens: [],
  staffUsers: [],
  shiftSessions: [],
  auditEvents: [],
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
  const customers = loadJson(FILES.customers, []);
  const restaurants = loadJson(FILES.restaurants, []);
  const deliveryZones = loadJson(FILES.deliveryZones, []);
  const kitchens = loadJson(FILES.kitchens, []);
  const staffUsers = loadJson(FILES.staffUsers, []);
  const shiftSessions = loadJson(FILES.shiftSessions, []);
  const auditEvents = loadJson(FILES.auditEvents, []);
  const settings = migrateSettingsShape(loadJson(FILES.settings, {}));

  memory.menuItems = Array.isArray(menuItems)
    ? menuItems.map((item) => ensureRestaurantId(item))
    : [];
  memory.orders = Array.isArray(orders)
    ? orders.map((order) => ensureRestaurantId(order))
    : [];
  memory.customers = Array.isArray(customers)
    ? customers.map((customer) => ensureRestaurantId(customer))
    : [];
  memory.restaurants = Array.isArray(restaurants) ? restaurants : [];
  memory.deliveryZones = Array.isArray(deliveryZones)
    ? deliveryZones.map((zone) => ensureRestaurantId(zone))
    : [];
  memory.kitchens = Array.isArray(kitchens)
    ? kitchens.map((kitchen) => ensureRestaurantId(kitchen))
    : [];
  memory.staffUsers = Array.isArray(staffUsers)
    ? staffUsers.map((user) => ensureRestaurantId(user))
    : [];
  memory.shiftSessions = Array.isArray(shiftSessions)
    ? shiftSessions.map((shift) => ensureRestaurantId(shift))
    : [];
  memory.auditEvents = Array.isArray(auditEvents) ? auditEvents : [];
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
    `Cannot ${action}: persistent storage is not configured. Set MONGODB_URI on Vercel.`,
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
    await mongoDb.collection(COLLECTION).updateOne(
      { _id: id },
      { $set: { data, updatedAt: new Date().toISOString() } },
      { upsert: true },
    );
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
    case 'customers':
      memory.customers = data;
      if (!IS_VERCEL) writeJson(FILES.customers, data);
      break;
    case 'delivery_zones':
      memory.deliveryZones = data;
      if (!IS_VERCEL) writeJson(FILES.deliveryZones, data);
      break;
    case 'kitchens':
      memory.kitchens = data;
      if (!IS_VERCEL) writeJson(FILES.kitchens, data);
      break;
    case 'settings':
      memory.settings = data;
      if (!IS_VERCEL) writeJson(FILES.settings, data);
      break;
    case 'staff_users':
      memory.staffUsers = data;
      if (!IS_VERCEL) writeJson(FILES.staffUsers, data);
      break;
    case 'shift_sessions':
      memory.shiftSessions = data;
      if (!IS_VERCEL) writeJson(FILES.shiftSessions, data);
      break;
    case 'audit_events':
      memory.auditEvents = data;
      if (!IS_VERCEL) writeJson(FILES.auditEvents, data);
      break;
    default:
      break;
  }
}

async function persistAllToMongo() {
  await writeDoc('menu_items', memory.menuItems);
  await writeDoc('orders', memory.orders);
  await writeDoc('customers', memory.customers);
  await writeDoc('restaurants', memory.restaurants);
  await writeDoc('delivery_zones', memory.deliveryZones);
  await writeDoc('kitchens', memory.kitchens);
  await writeDoc('settings', memory.settings);
  await writeDoc('staff_users', memory.staffUsers);
  await writeDoc('shift_sessions', memory.shiftSessions);
  await writeDoc('audit_events', memory.auditEvents);
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
    memory.customers = await readDoc('customers', memory.customers);
    memory.deliveryZones = await readDoc('delivery_zones', memory.deliveryZones);
    memory.kitchens = await readDoc('kitchens', memory.kitchens);
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

    try {
      delete require.cache[require.resolve('../data/delivery_zones.json')];
      const freshZones = require('../data/delivery_zones.json');
      if (Array.isArray(freshZones)) {
        memory.deliveryZones = freshZones.map((zone) => ensureRestaurantId(zone));
      }
    } catch (_) {}

    try {
      delete require.cache[require.resolve('../data/kitchens.json')];
      const freshKitchens = require('../data/kitchens.json');
      if (Array.isArray(freshKitchens)) {
        memory.kitchens = freshKitchens.map((kitchen) => ensureRestaurantId(kitchen));
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

async function readCustomers() {
  if (usesMongo()) {
    const customers = await readDoc('customers', memory.customers);
    return Array.isArray(customers)
      ? customers.map((customer) => ensureRestaurantId(customer))
      : [];
  }

  if (IS_VERCEL) {
    return memory.customers.map((customer) => ensureRestaurantId(customer));
  }

  const customers = loadJson(FILES.customers, memory.customers);
  memory.customers = Array.isArray(customers)
    ? customers.map((customer) => ensureRestaurantId(customer))
    : [];
  return memory.customers;
}

async function writeCustomers(customers) {
  assertCanPersist('save customers');
  const normalized = customers.map((customer) => ensureRestaurantId(customer));
  memory.customers = normalized;
  await writeDoc('customers', normalized);
  return normalized;
}

async function ensureCustomersMigrated() {
  const customers = await readCustomers();
  const orders = await readOrders();
  if (customers.length > 0 || orders.length === 0) {
    return customers;
  }

  const migrated = migrateCustomersFromOrders(customers, orders);
  if (migrated.length > 0) {
    await writeCustomers(migrated);
  }
  return migrated;
}

async function readDeliveryZones() {
  if (usesMongo()) {
    const zones = await readDoc('delivery_zones', memory.deliveryZones);
    return Array.isArray(zones) ? zones.map((zone) => ensureRestaurantId(zone)) : [];
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
  assertCanPersist('save delivery zones');
  const normalized = zones.map((zone) => ensureRestaurantId(zone));
  memory.deliveryZones = normalized;
  await writeDoc('delivery_zones', normalized);
  return normalized;
}

async function readKitchens() {
  if (usesMongo()) {
    const kitchens = await readDoc('kitchens', memory.kitchens);
    return Array.isArray(kitchens)
      ? kitchens.map((kitchen) => ensureRestaurantId(kitchen))
      : [];
  }

  if (IS_VERCEL) {
    return memory.kitchens.map((kitchen) => ensureRestaurantId(kitchen));
  }

  const kitchens = loadJson(FILES.kitchens, memory.kitchens);
  memory.kitchens = Array.isArray(kitchens)
    ? kitchens.map((kitchen) => ensureRestaurantId(kitchen))
    : [];
  return memory.kitchens;
}

async function writeKitchens(kitchens) {
  assertCanPersist('save kitchens');
  const normalized = kitchens.map((kitchen) => ensureRestaurantId(kitchen));
  memory.kitchens = normalized;
  await writeDoc('kitchens', normalized);
  return normalized;
}

async function readStaffUsers() {
  if (usesMongo()) {
    const users = await readDoc('staff_users', memory.staffUsers);
    return Array.isArray(users) ? users.map((user) => ensureRestaurantId(user)) : [];
  }

  if (IS_VERCEL) {
    return memory.staffUsers.map((user) => ensureRestaurantId(user));
  }

  const users = loadJson(FILES.staffUsers, memory.staffUsers);
  memory.staffUsers = Array.isArray(users)
    ? users.map((user) => ensureRestaurantId(user))
    : [];
  return memory.staffUsers;
}

async function writeStaffUsers(users) {
  assertCanPersist('save staff users');
  const normalized = users.map((user) => ensureRestaurantId(user));
  memory.staffUsers = normalized;
  await writeDoc('staff_users', normalized);
  return normalized;
}

async function readShiftSessions() {
  if (usesMongo()) {
    const shifts = await readDoc('shift_sessions', memory.shiftSessions);
    return Array.isArray(shifts) ? shifts.map((shift) => ensureRestaurantId(shift)) : [];
  }

  if (IS_VERCEL) {
    return memory.shiftSessions.map((shift) => ensureRestaurantId(shift));
  }

  const shifts = loadJson(FILES.shiftSessions, memory.shiftSessions);
  memory.shiftSessions = Array.isArray(shifts)
    ? shifts.map((shift) => ensureRestaurantId(shift))
    : [];
  return memory.shiftSessions;
}

async function writeShiftSessions(shifts) {
  assertCanPersist('save shift sessions');
  const normalized = shifts.map((shift) => ensureRestaurantId(shift));
  memory.shiftSessions = normalized;
  await writeDoc('shift_sessions', normalized);
  return normalized;
}

async function readAuditEvents() {
  if (usesMongo()) {
    const events = await readDoc('audit_events', memory.auditEvents);
    return Array.isArray(events) ? events : [];
  }

  if (IS_VERCEL) {
    return memory.auditEvents;
  }

  const events = loadJson(FILES.auditEvents, memory.auditEvents);
  memory.auditEvents = Array.isArray(events) ? events : [];
  return memory.auditEvents;
}

async function appendAuditEvents(events) {
  assertCanPersist('save audit events');
  const incoming = Array.isArray(events) ? events : [events];
  const existing = await readAuditEvents();
  const merged = [...incoming, ...existing].slice(0, 5000);
  memory.auditEvents = merged;
  await writeDoc('audit_events', merged);
  return merged;
}

async function ensureBilingualMenuItemsFast() {
  const items = await readItems();
  const { items: migrated, updated } = migrateMenuItems(items);
  const shapeChanged = migrated.some(
    (item, index) => JSON.stringify(item) !== JSON.stringify(items[index]),
  );

  if (updated > 0 || shapeChanged) {
    await writeItems(migrated);
  }

  return { updated, total: items.length, scanned: items.length };
}

async function ensureBilingualMenuItemsWithAutoTranslate(options = {}) {
  const items = await readItems();
  const result = await autoTranslateMenuItems(items, options);
  if (result.updated > 0) {
    await writeItems(result.items);
  }
  return result;
}

module.exports = {
  initDataStore,
  usesMongo,
  getStorageStatus,
  canPersistWrites,
  assertCanPersist,
  readItems,
  writeItems,
  readOrders,
  writeOrders,
  readCustomers,
  writeCustomers,
  ensureCustomersMigrated,
  readRestaurants,
  writeRestaurants,
  readSettingsMap,
  writeSettingsMap,
  readDeliveryZones,
  writeDeliveryZones,
  readKitchens,
  writeKitchens,
  readStaffUsers,
  writeStaffUsers,
  readShiftSessions,
  writeShiftSessions,
  readAuditEvents,
  appendAuditEvents,
  ensureBilingualMenuItemsFast,
  ensureBilingualMenuItemsWithAutoTranslate,
};
