#!/usr/bin/env node
const fs = require('fs');
const transcript = process.argv[2];
const outDir = process.argv[3];
const names = process.argv.slice(4).map((n) => n.toLowerCase());
const files = new Map();

for (const line of fs.readFileSync(transcript, 'utf8').split('\n')) {
  if (!line.includes('"Write"') || !line.includes('"contents"')) continue;
  let row;
  try {
    row = JSON.parse(line);
  } catch {
    continue;
  }
  for (const block of row?.message?.content || []) {
    if (block?.name !== 'Write') continue;
    const p = (block.input?.path || '').replace(/\\/g, '/').toLowerCase();
    if (!names.some((n) => p.endsWith(n))) continue;
    files.set(p, block.input.contents);
  }
}

fs.mkdirSync(outDir, { recursive: true });
for (const [p, contents] of files) {
  const base = p.split('/').pop();
  fs.writeFileSync(`${outDir}/${base}`, contents, 'utf8');
  console.log('extracted', base, contents.split('\n').length, 'lines');
}
