#!/usr/bin/env node
/**
 * Fail the Vercel build early if entrypoints, handlers, or routing config are invalid.
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');

const requiredFiles = [
  'app.js',
  'index.js',
  'server.js',
  'apiServer.js',
  'vercel.json',
  'package.json',
  'api/kitchens.js',
  'api/delivery-zones.js',
  'lib/kitchenApiHandler.js',
  'lib/deliveryZoneApiHandler.js',
  'lib/kitchenRoutes.js',
  'lib/deliveryZoneRoutes.js',
];

for (const relativePath of requiredFiles) {
  if (!fs.existsSync(path.join(root, relativePath))) {
    console.error(`[verify] Missing required file: ${relativePath}`);
    process.exit(1);
  }
}

const vercel = JSON.parse(fs.readFileSync(path.join(root, 'vercel.json'), 'utf8'));

if (!Array.isArray(vercel.builds) || vercel.builds.length === 0) {
  console.error('[verify] vercel.json must define builds');
  process.exit(1);
}

if (vercel.framework !== null) {
  console.error('[verify] vercel.json framework must be null (not Express)');
  process.exit(1);
}

const buildSources = vercel.builds.map((entry) => entry.src);
for (const src of ['index.js', 'apiServer.js', 'api/kitchens.js', 'api/delivery-zones.js']) {
  if (!buildSources.includes(src)) {
    console.error(`[verify] vercel.json builds missing: ${src}`);
    process.exit(1);
  }
}

const routeDests = vercel.routes.map((route) => route.dest).filter(Boolean);
for (const dest of ['/api/kitchens.js', '/api/delivery-zones.js', '/apiServer.js']) {
  if (!routeDests.includes(dest)) {
    console.error(`[verify] vercel.json routes missing dest: ${dest}`);
    process.exit(1);
  }
}

require(path.join(root, 'app.js'));
require(path.join(root, 'index.js'));
require(path.join(root, 'server.js'));
require(path.join(root, 'api/kitchens.js'));
require(path.join(root, 'api/delivery-zones.js'));

console.log('[verify] Vercel deploy checks passed (kitchen-zones-v13)');
