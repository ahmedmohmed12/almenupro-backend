#!/usr/bin/env node
/**
 * Fail the Vercel build early if entrypoints, handlers, or routing config are invalid.
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');

const requiredFiles = [
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
  'lib/vercelApiUtils.js',
];

let failed = false;

for (const relativePath of requiredFiles) {
  const fullPath = path.join(root, relativePath);
  if (!fs.existsSync(fullPath)) {
    console.error(`[verify] Missing required file: ${relativePath}`);
    failed = true;
  }
}

if (failed) {
  process.exit(1);
}

let vercel;
try {
  vercel = JSON.parse(fs.readFileSync(path.join(root, 'vercel.json'), 'utf8'));
} catch (error) {
  console.error('[verify] Invalid vercel.json:', error.message);
  process.exit(1);
}

if (!Array.isArray(vercel.builds) || vercel.builds.length === 0) {
  console.error('[verify] vercel.json must define a non-empty builds array');
  process.exit(1);
}

const buildSources = vercel.builds.map((entry) => entry.src);
for (const src of ['index.js', 'server.js', 'apiServer.js', 'api/kitchens.js', 'api/delivery-zones.js']) {
  if (!buildSources.includes(src)) {
    console.error(`[verify] vercel.json builds missing entry: ${src}`);
    process.exit(1);
  }
}

if (!Array.isArray(vercel.routes) || vercel.routes.length === 0) {
  console.error('[verify] vercel.json must define routes for /api/kitchens and /api/delivery-zones');
  process.exit(1);
}

const routeDests = vercel.routes.map((route) => route.dest).filter(Boolean);
for (const dest of ['/api/kitchens.js', '/api/delivery-zones.js', '/apiServer.js']) {
  if (!routeDests.includes(dest)) {
    console.error(`[verify] vercel.json routes missing destination: ${dest}`);
    process.exit(1);
  }
}

try {
  require(path.join(root, 'index.js'));
  require(path.join(root, 'server.js'));
  require(path.join(root, 'api/kitchens.js'));
  require(path.join(root, 'api/delivery-zones.js'));
} catch (error) {
  console.error('[verify] Failed to load entrypoint/handler:', error.message);
  process.exit(1);
}

console.log('[verify] Vercel deploy checks passed (kitchen-zones-v11)');
