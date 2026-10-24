// Screenshot every public page and admin view. Usage: node shots.mjs <outdir> [prefix]
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';

const out = process.argv[2];
const prefix = process.argv[3] || '';
fs.mkdirSync(out, { recursive: true });
const base = 'http://localhost/Disaster-Management-System/frontend';
const api = 'http://localhost/Disaster-Management-System/backend/public/api';

const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: 'new',
  args: ['--no-sandbox', '--disable-gpu', '--use-gl=swiftshader'],
});
const page = await browser.newPage();
await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });
page.on('pageerror', e => console.log('PAGE ERROR', e.message));
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function shot(name, opts = {}) {
  await sleep(opts.wait ?? 1500);
  await page.screenshot({ path: `${out}/${prefix}${name}.png`, fullPage: !!opts.full });
  console.log('shot', name);
}

for (const p of ['index', 'login', 'register', 'forgot-password', 'verify-email']) {
  await page.goto(`${base}/${p}.html`, { waitUntil: 'networkidle2', timeout: 60000 }).catch(e => console.log(p, e.message));
  await shot(p, { full: p === 'index', wait: 2500 });
}

// Login through the API and seed sessionStorage like auth.js does.
const login = await (await fetch(`${api}/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: process.env.DM_EMAIL || 'admin@example.gov.ph', password: process.env.DM_PASSWORD || '' }) })).json();
await page.goto(`${base}/login.html`, { waitUntil: 'domcontentloaded' });
await page.evaluate(d => { sessionStorage.setItem('dm_token', d.access_token); sessionStorage.setItem('dm_user', JSON.stringify(d.user)); }, login.data);
await page.goto(`${base}/dashboard.html`, { waitUntil: 'networkidle2', timeout: 60000 });
await shot('dashboard-overview', { wait: 3500 });
for (const view of ['weather', 'municipalities', 'hazards', 'safezones', 'alerts', 'history', 'reports', 'users', 'profile']) {
  const ok = await page.evaluate(v => { const b = document.querySelector(`.nav-item[data-view="${v}"]`); if (!b) return false; b.click(); return true; }, view);
  if (!ok) { console.log('skip', view); continue; }
  await shot(`dashboard-${view}`, { wait: 3500, full: view !== 'hazards' && view !== 'safezones' });
}
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 });
await page.goto(`${base}/index.html`, { waitUntil: 'networkidle2', timeout: 60000 });
await shot('mobile-index', { wait: 2500 });
await page.goto(`${base}/dashboard.html`, { waitUntil: 'networkidle2', timeout: 60000 });
await shot('mobile-dashboard', { wait: 3500 });
await browser.close();
