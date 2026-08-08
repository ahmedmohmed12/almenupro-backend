/**
 * Seeds kitchens and backfills delivery zone default_kitchen_id mappings.
 * Run: node scripts/migrateKitchens.js
 */
const fs = require('fs');
const path = require('path');

const DATA_DIR = path.join(__dirname, '..', 'data');
const kitchensPath = path.join(DATA_DIR, 'kitchens.json');
const zonesPath = path.join(DATA_DIR, 'delivery_zones.json');

const DEFAULT_KITCHENS = [
  {
    id: 'kitchen_ardiya',
    restaurant_id: 'rest_molton',
    name: 'Al-Ardiya Kitchen',
    name_ar: 'مطبخ العارضية',
    name_en: 'Al-Ardiya Kitchen',
    code: 'ARD',
    status: 'active',
    is_default: true,
    sort_order: 1,
    kds_enabled: true,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  },
  {
    id: 'kitchen_sabah',
    restaurant_id: 'rest_molton',
    name: 'Sabah Al-Salem Kitchen',
    name_ar: 'مطبخ صباح السالم',
    name_en: 'Sabah Al-Salem Kitchen',
    code: 'SBH',
    status: 'active',
    is_default: false,
    sort_order: 2,
    kds_enabled: true,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  },
];

const ZONE_KITCHEN_MAP = {
  zone_molton_salmiya: 'kitchen_ardiya',
  zone_molton_hawally: 'kitchen_ardiya',
  zone_molton_jabriya: 'kitchen_sabah',
  zone_molton_fintas: 'kitchen_sabah',
};

function loadJson(filePath, fallback) {
  try {
    if (!fs.existsSync(filePath)) return fallback;
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return fallback;
  }
}

function main() {
  let kitchens = loadJson(kitchensPath, []);
  if (!Array.isArray(kitchens) || kitchens.length === 0) {
    kitchens = DEFAULT_KITCHENS;
    fs.writeFileSync(kitchensPath, `${JSON.stringify(kitchens, null, 2)}\n`, 'utf8');
    console.log(`Created ${kitchens.length} kitchens`);
  } else {
    console.log(`Kitchens already present (${kitchens.length}) — skipped seed`);
  }

  const zones = loadJson(zonesPath, []);
  if (!Array.isArray(zones)) {
    console.log('No delivery zones file — done');
    return;
  }

  let updated = 0;
  const nextZones = zones.map((zone) => {
    if (zone.default_kitchen_id || zone.defaultKitchenId) return zone;
    const mapped = ZONE_KITCHEN_MAP[zone.id];
    if (!mapped) return zone;
    updated += 1;
    return {
      ...zone,
      default_kitchen_id: mapped,
      defaultKitchenId: mapped,
      updatedAt: new Date().toISOString(),
    };
  });

  fs.writeFileSync(zonesPath, `${JSON.stringify(nextZones, null, 2)}\n`, 'utf8');
  console.log(`Updated ${updated} delivery zones with default_kitchen_id`);
}

main();
