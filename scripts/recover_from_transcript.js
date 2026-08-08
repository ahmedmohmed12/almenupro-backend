#!/usr/bin/env node
/**
 * Recover source files from Cursor agent transcript Write operations.
 * Uses the last Write per path before the Excel v1.48 cutoff line (if set).
 */
const fs = require('fs');
const path = require('path');

const TRANSCRIPT = process.argv[2];
const PROJECT_ROOT = process.argv[3];
const MAX_LINE = Number(process.argv[4] || 0) || Infinity;

if (!TRANSCRIPT || !PROJECT_ROOT) {
  console.error('Usage: node recover_from_transcript.js <transcript.jsonl> <projectRoot> [maxLine]');
  process.exit(1);
}

const files = new Map(); // relPath -> { line, contents }

const lines = fs.readFileSync(TRANSCRIPT, 'utf8').split('\n');
for (let i = 0; i < lines.length; i++) {
  const lineNo = i + 1;
  if (lineNo > MAX_LINE) break;
  const line = lines[i].trim();
  if (!line || !line.includes('"Write"')) continue;

  let row;
  try {
    row = JSON.parse(line);
  } catch {
    continue;
  }

  const content = row?.message?.content;
  if (!Array.isArray(content)) continue;

  for (const block of content) {
    if (block?.name !== 'Write') continue;
    const input = block.input;
    if (!input?.path || typeof input.contents !== 'string') continue;

    const full = input.path.replace(/\\/g, '/');
    const marker = 'almenupro/';
    const idx = full.toLowerCase().indexOf(marker);
    if (idx < 0) continue;
    const rel = full.slice(idx + marker.length);
    if (!rel.startsWith('backend/') && !rel.startsWith('lib/')) continue;

    files.set(rel, { line: lineNo, contents: input.contents });
  }
}

let written = 0;
let skipped = 0;

for (const [rel, { contents }] of files) {
  const backendRoot = path.join(PROJECT_ROOT, 'backend');
  const relPath = rel.startsWith('backend/') ? rel.slice('backend/'.length) : rel;
  const target = path.join(backendRoot, relPath);

  const dir = path.dirname(target);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(target, contents, 'utf8');
  written++;
}

console.log(`Recovered ${written} files (cutoff line ${MAX_LINE === Infinity ? 'none' : MAX_LINE})`);
