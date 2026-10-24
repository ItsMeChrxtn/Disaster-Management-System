// Pulls the live site down from Hostinger over FTP — the reverse of deploy-ftp.mjs.
//
//   node tools/dev/download-ftp.mjs <local-folder>
//   node tools/dev/download-ftp.mjs <local-folder> frontend
//   node tools/dev/download-ftp.mjs <local-folder> backend/app
//
// The second argument is a path inside public_html; without it the whole site comes
// down. Credentials come from .vscode/sftp.json, same as deploy-ftp.mjs.
import { Client } from 'basic-ftp';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '../..');
const config = JSON.parse(fs.readFileSync(path.join(root, '.vscode/sftp.json'), 'utf8'));
const remoteRoot = (config.remotePath || '/public_html').replace(/\/+$/, '');

const [target, subPath = ''] = process.argv.slice(2);
if (!target) {
  console.error('Usage: node tools/dev/download-ftp.mjs <local-folder> [remote-subpath]');
  console.error('   e.g. node tools/dev/download-ftp.mjs C:/backup-hostinger');
  console.error('        node tools/dev/download-ftp.mjs C:/backup-hostinger frontend');
  process.exit(1);
}

const localDir = path.resolve(target);
const remoteDir = subPath ? `${remoteRoot}/${subPath.replace(/^\/+|\/+$/g, '')}` : remoteRoot;

// Refuse to scribble into a folder that already holds something, unless it is empty.
if (fs.existsSync(localDir) && fs.readdirSync(localDir).length) {
  console.error(`❌ "${localDir}" ay may laman na. Pumili ng bagong folder o linisin muna ito.`);
  process.exit(1);
}
fs.mkdirSync(localDir, { recursive: true });

const client = new Client(180_000);
const started = Date.now();
let lastLogged = 0;
let files = 0;

client.trackProgress(info => {
  const now = Date.now();
  if (info.type === 'download') {
    files = Math.max(files, 0);
    if (now - lastLogged > 5000) {
      lastLogged = now;
      console.log(`  ${(info.bytesOverall / 1048576).toFixed(1)} MB · ${((now - started) / 60000).toFixed(1)} min · ${info.name}`);
    }
  }
});

console.log(`Kinukuha mula sa ${config.host}${remoteDir}`);
console.log(`          papunta sa ${localDir}\n`);

try {
  await client.access({
    host: config.host,
    port: config.port || 21,
    user: config.username,
    password: config.password,
    secure: config.secure ?? false,
  });
  await client.downloadToDir(localDir, remoteDir);

  // Count what actually landed.
  let n = 0, bytes = 0;
  (function walk(dir) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.isFile()) { n++; bytes += fs.statSync(p).size; }
    }
  })(localDir);

  console.log(`\n✅ Tapos: ${n} files, ${(bytes / 1048576).toFixed(1)} MB sa ${((Date.now() - started) / 60000).toFixed(1)} min`);
  console.log(`   Nasa: ${localDir}`);
  if (fs.existsSync(path.join(localDir, 'backend/.env'))) {
    console.log('\n⚠️  May backend/.env sa na-download — naglalaman ito ng database password');
    console.log('    at ng JWT secret. Huwag mong i-commit sa git.');
  }
} catch (error) {
  console.error('\n❌ NABIGO:', error.message);
  process.exitCode = 1;
} finally {
  client.close();
}
