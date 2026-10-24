import puppeteer from 'puppeteer-core';
const out = process.argv[2];
const base = 'http://localhost/Disaster-Management-System/frontend';
const api = 'http://localhost/Disaster-Management-System/backend/public/api';
const browser = await puppeteer.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: 'new', args: ['--no-sandbox', '--disable-gpu'] });
const page = await browser.newPage();
await page.setViewport({ width: 1440, height: 900 });
page.on('pageerror', e => console.log('PAGE ERROR', e.message));
const sleep = ms => new Promise(r => setTimeout(r, ms));
const login = await (await fetch(`${api}/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: 'admin@example.gov.ph', password: process.env.DM_PASSWORD || '' }) })).json();
await page.goto(`${base}/login.html`, { waitUntil: 'domcontentloaded' });
await page.evaluate(d => { sessionStorage.setItem('dm_token', d.access_token); sessionStorage.setItem('dm_user', JSON.stringify(d.user)); }, login.data);
await page.goto(`${base}/dashboard.html`, { waitUntil: 'networkidle2', timeout: 60000 });
const steps = [['reports', '#openReportModalBtn', 'modal-report'], ['users', '#addUserBtn', 'modal-user'], ['alerts', '#newAlertBtn', 'modal-alert'], ['municipalities', '#addMunicipalityBtn', 'modal-municipality'], ['history', '#newHistoricalBtn', 'modal-history'], ['municipalities', '.municipality-action.view', 'modal-municipality-view'], ['history', '.history-table-action.view', 'swal-history-view'], ['users', '.user-table-action.delete', 'swal-confirm']];
for (const [view, sel, name] of steps) {
  await page.evaluate(v => document.querySelector(`.nav-item[data-view="${v}"]`)?.click(), view);
  await sleep(2500);
  const ok = await page.evaluate(s => { const b = document.querySelector(s); if (!b) return false; b.click(); return true; }, sel);
  await sleep(1500);
  await page.screenshot({ path: `${out}/${name}.png` });
  console.log('shot', name, ok);
  await page.keyboard.press('Escape'); await sleep(600);
  await page.evaluate(() => { document.querySelectorAll('.crud-modal').forEach(m => { m.classList.add('hidden'); m.classList.remove('flex'); }); document.body.classList.remove('modal-open'); });
}
await page.evaluate(() => document.getElementById('notificationBell')?.click()); await sleep(1500);
await page.screenshot({ path: `${out}/notifications.png` });
await browser.close();
