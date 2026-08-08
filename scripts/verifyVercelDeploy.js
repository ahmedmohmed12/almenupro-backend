#!/usr/bin/env node
/**
 * Fail CI/Vercel build early if entrypoints, handlers, or routing config are invalid.
 * Uses syntax checks only — does not boot MongoDB or the full data store.
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const root = path.join(__dirname, '..');

// Prevent accidental Mongo init during CI syntax checks.
delete process.env.MONGODB_URI;
delete process.env.VERCEL;

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
  'lib/vercelApiUtils.js',
];

for (const relativePath of requiredFiles) {
  const fullPath = path.join(root, relativePath);
  if (!fs.existsSync(fullPath)) {
    console.error(`[verify] Missing required file: ${relativePath}`);
    process.exit(1);
  }
}

let vercel;
try {
  vercel = JSON.parse(fs.readFileSync(path.join(root, 'vercel.json'), 'utf8'));
} catch (error) {
  console.error('[verify] Invalid vercel.json:', error.message);
  process.exit(1);
}

if (vercel.framework !== null) {
  console.error('[verify] vercel.json framework must be null (not Express)');
  process.exit(1);
}

if (!Array.isArray(vercel.builds) || vercel.builds.length === 0) {
  console.error('[verify] vercel.json must define builds');
  process.exit(1);
}

if (!Array.isArray(vercel.routes) || vercel.routes.length === 0) {
  console.error('[verify] vercel.json must define routes');
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

const syntaxCheckFiles = [
  'app.js',
  'index.js',
  'server.js',
  'api/kitchens.js',
  'api/delivery-zones.js',
  'lib/kitchenApiHandler.js',
  'lib/deliveryZoneApiHandler.js',
];

for (const relativePath of syntaxCheckFiles) {
  const fullPath = path.join(root, relativePath);
  try {
    execSync(`node --check "${fullPath}"`, { stdio: 'pipe' });
  } catch (error) {
    console.error(`[verify] Syntax error in ${relativePath}`);
    process.exit(1);
  }
}

console.log('[verify] Vercel deploy checks passed (kitchen-zones-v14)');
