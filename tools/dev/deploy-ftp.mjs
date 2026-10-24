// Uploads the deployable parts of the repo to Hostinger over FTP.
//
//   node tools/dev/deploy-ftp.mjs             # upload everything
//   node tools/dev/deploy-ftp.mjs frontend    # only that top-level path
//
// Credentials come from .vscode/sftp.json (git-ignored):
//   { "host": "...", "username": "...", "password": "...", "remotePath": "/domains/<domain>/public_html" }
//
// A staging copy is built first so basic-ftp's uploadFromDir (one recursive pass,
// far fewer round trips than per-folder ensureDir) sees exactly what should ship.
import { Client } from 'basic-ftp';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '../..');
const config = JSON.parse(fs.readFileSync(path.join(root, '.vscode/sftp.json'), 'utf8'));
const remoteRoot = (config.remotePath || '/public_html').replace(/\/+$/, '') || '/';

// Only these ever go to the server.
const DEPLOY = ['index.php', 'favicon.ico', 'frontend', 'backend'];
// Never ship these. `backend/.env` is excluded on purpose: the local one points at
// XAMPP; the production copy ships via RENAME below.
const SKIP = new Set(['node_modules', '.git', '.vscode', 'mobile', 'tools', '.DS_Store', 'Thumbs.db', '.env']);
// local path -> path inside the staging dir (and therefore on the server)
const RENAME = { 'backend/.env.production': 'backend/.env' };

const only = process.argv.slice(2);
const targets = only.length ? DEPLOY.filter(d => only.includes(d)) : DEPLOY;
if (!targets.length) {
  console.error(`Nothing to upload. Valid targets: ${DEPLOY.join(', ')}`);
  process.exit(1);
}

// ---------------------------------------------------------------- staging
const stage = fs.mkdtempSync(path.join(os.tmpdir(), 'dm-deploy-'));
let staged = 0;
let stagedBytes = 0;

function copyInto(fromAbs, relPath) {
  const name = path.basename(relPath);
  if (SKIP.has(name)) return;
  const stat = fs.statSync(fromAbs);
  const target = path.join(stage, RENAME[relPath] ?? relPath);
  if (stat.isDirectory()) {
    fs.mkdirSync(target, { recursive: true });
    for (const entry of fs.readdirSync(fromAbs)) {
      copyInto(path.join(fromAbs, entry), `${relPath}/${entry}`);
    }
  } else if (stat.isFile()) {
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.copyFileSync(fromAbs, target);
    staged++;
    stagedBytes += stat.size;
  }
}

console.log('Staging files...');
for (const target of targets) {
  const abs = path.join(root, target);
  if (fs.existsSync(abs)) copyInto(abs, target);
}
// Production .env always ships when the backend does.
if (targets.includes('backend')) {
  const prod = path.join(root, 'backend/.env.production');
  if (fs.existsSync(prod)) {
    fs.copyFileSync(prod, path.join(stage, 'backend/.env'));
    staged++;
    stagedBytes += fs.statSync(prod).size;
  } else {
    console.warn('⚠️  backend/.env.production is missing — the server will have no .env');
  }
}

console.log(`  ${staged} files (${(stagedBytes / 1048576).toFixed(1)} MB) ready`);
console.log(`  to ${config.host}${remoteRoot}\n`);

// ---------------------------------------------------------------- upload
const client = new Client(180_000);
client.ftp.verbose = false;
const started = Date.now();
let lastLogged = 0;

client.trackProgress(info => {
  const now = Date.now();
  if (info.type === 'upload' && now - lastLogged > 5000) {
    lastLogged = now;
    const pct = ((info.bytesOverall / stagedBytes) * 100).toFixed(0);
    const mins = ((now - started) / 60000).toFixed(1);
    console.log(`  ${pct}% · ${(info.bytesOverall / 1048576).toFixed(1)}/${(stagedBytes / 1048576).toFixed(1)} MB · ${mins} min · ${info.name}`);
  }
});

try {
  await client.access({
    host: config.host,
    port: config.port || 21,
    user: config.username,
    password: config.password,
    secure: config.secure ?? false,
  });
  await client.ensureDir(remoteRoot);
  await client.uploadFromDir(stage, remoteRoot);
  console.log(`\n✅ Done: ${staged} files, ${(stagedBytes / 1048576).toFixed(1)} MB in ${((Date.now() - started) / 60000).toFixed(1)} min`);
} catch (error) {
  console.error('\n❌ FAILED:', error.message);
  process.exitCode = 1;
} finally {
  client.close();
  fs.rmSync(stage, { recursive: true, force: true });
}
