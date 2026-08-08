#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const frontendDir = path.join(__dirname, '..');
const distDir = path.join(frontendDir, 'dist');
const outputDir = path.join(distDir, '.vercel', 'output');
const staticDir = path.join(outputDir, 'static');
const middlewareFuncDir = path.join(outputDir, 'functions', '_middleware.func');

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function copyDir(src, dest, skipNames = new Set(['.vercel'])) {
  ensureDir(dest);
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    if (skipNames.has(entry.name)) continue;
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDir(srcPath, destPath, new Set());
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

if (!fs.existsSync(distDir)) {
  console.error('dist/ not found — run flutter build first');
  process.exit(1);
}

if (fs.existsSync(staticDir)) {
  fs.rmSync(staticDir, { recursive: true, force: true });
}

ensureDir(outputDir);
copyDir(distDir, staticDir);

ensureDir(middlewareFuncDir);
fs.copyFileSync(
  path.join(frontendDir, 'middleware.js'),
  path.join(middlewareFuncDir, 'index.js'),
);
fs.writeFileSync(
  path.join(middlewareFuncDir, '.vc-config.json'),
  `${JSON.stringify({ runtime: 'edge', entrypoint: 'index.js' }, null, 2)}\n`,
);

const config = {
  version: 3,
  routes: [
    {
      src: '/menu/(.*)',
      middlewarePath: '_middleware',
      continue: true,
    },
    {
      src: '/restaurant/(.*)',
      middlewarePath: '_middleware',
      continue: true,
    },
    {
      src: '/([^./]+)',
      middlewarePath: '_middleware',
      continue: true,
    },
    { handle: 'filesystem' },
    { src: '^/$', dest: '/landing.html' },
    { src: '^/admin$', dest: '/index.html' },
    { src: '^/admin/.*', dest: '/index.html' },
    { src: '^/menu/.*', dest: '/index.html' },
    { src: '^/restaurant/.*', dest: '/index.html' },
    { src: '^/legacy-menu$', dest: '/index.html' },
    { src: '^/[^/]+$', dest: '/index.html' },
  ],
  overrides: {
    'manifest.json': {
      headers: {
        'Content-Type': 'application/manifest+json; charset=utf-8',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'public, max-age=0, must-revalidate',
      },
    },
    'main.dart.js': {
      headers: {
        'Cache-Control': 'public, max-age=0, must-revalidate',
      },
    },
    'flutter_bootstrap.js': {
      headers: {
        'Cache-Control': 'public, max-age=0, must-revalidate',
      },
    },
  },
};

fs.writeFileSync(
  path.join(outputDir, 'config.json'),
  `${JSON.stringify(config, null, 2)}\n`,
);

console.log('Prepared Vercel Build Output with WhatsApp OG middleware');
