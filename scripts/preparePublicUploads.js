const fs = require('fs');
const path = require('path');

const sourceDir = path.join(__dirname, '..', 'uploads', 'menu');
const targetDir = path.join(__dirname, '..', 'public', 'api', 'uploads', 'menu');

if (!fs.existsSync(sourceDir)) {
  console.log('No uploads/menu directory found, skipping public copy.');
  process.exit(0);
}

fs.mkdirSync(targetDir, { recursive: true });

let copied = 0;
for (const filename of fs.readdirSync(sourceDir)) {
  if (filename.startsWith('.')) continue;
  fs.copyFileSync(path.join(sourceDir, filename), path.join(targetDir, filename));
  copied += 1;
}

console.log(`Copied ${copied} menu images to public/api/uploads/menu`);
