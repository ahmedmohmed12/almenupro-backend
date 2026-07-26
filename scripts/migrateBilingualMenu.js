const fs = require('fs');
const path = require('path');
const { migrateMenuItems } = require('../lib/bilingualMenu');

const DATA_FILE = path.join(__dirname, '..', 'data', 'menu_items.json');

async function main() {
  const raw = fs.readFileSync(DATA_FILE, 'utf8');
  const items = JSON.parse(raw || '[]');
  if (!Array.isArray(items)) {
    throw new Error('menu_items.json must contain an array');
  }

  console.log(`Migrating ${items.length} menu items to bilingual schema...`);
  const { items: migrated, updated } = migrateMenuItems(items);
  fs.writeFileSync(DATA_FILE, JSON.stringify(migrated, null, 2), 'utf8');

  console.log(`Done. ${updated} items updated with English translations.`);
  console.log(`File written: ${DATA_FILE}`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
