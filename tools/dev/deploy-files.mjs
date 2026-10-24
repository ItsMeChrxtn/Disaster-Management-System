// Uploads individual files to Hostinger over FTP — for small changes, when a full
// deploy-ftp.mjs run (54 MB, ~25 min) would be wasteful.
//
//   node tools/dev/deploy-files.mjs frontend/assets/js/ui.js frontend/index.html
//
// Paths are repo-relative and keep their position on the server. Credentials come
// from .vscode/sftp.json, same as deploy-ftp.mjs.
import { Client } from 'basic-ftp';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '../..');
const config = JSON.parse(fs.readFileSync(path.join(root, '.vscode/sftp.json'), 'utf8'));
const remoteRoot = (config.remotePath || '/public_html').replace(/\/+$/, '');

const files = process.argv.slice(2);
if (!files.length) {
  console.error('Usage: node tools/dev/deploy-files.mjs <path> [path...]');
  process.exit(1);
}

const missing = files.filter(f => !fs.existsSync(path.join(root, f)));
if (missing.length) {
  console.error('Not found:\n' + missing.map(f => '  ' + f).join('\n'));
  process.exit(1);
}

const client = new Client(60_000);
let bytes = 0;
try {
  await client.access({
    host: config.host,
    port: config.port || 21,
    user: config.username,
    password: config.password,
    secure: config.secure ?? false,
  });
  for (const rel of files) {
    const local = path.join(root, rel);
    const remote = remoteRoot + '/' + rel.split(path.sep).join('/');
    await client.ensureDir(path.posix.dirname(remote));
    await client.cd('/'); // ensureDir leaves the cwd inside the target
    await client.uploadFrom(local, remote);
    bytes += fs.statSync(local).size;
    console.log('  ' + rel);
  }
  console.log(`\n✅ ${files.length} files, ${(bytes / 1024).toFixed(0)} KB -> ${config.host}${remoteRoot}`);
} catch (error) {
  console.error('\n❌ FAILED:', error.message);
  process.exitCode = 1;
} finally {
  client.close();
}
