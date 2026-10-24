// Rebuilds frontend/assets/data/cavite-*.json (boundaries + DEM-derived geohazard zones).
// Sources: PSA/NAMRIA boundaries via github.com/faeldon/philippines-json-maps (2023),
// Terrarium elevation tiles (AWS Terrain Tiles, SRTM-based).
// Run from a scratch dir after downloading cav_hires.json and bgy/*.json (see README in tools/gis):
//   npm i --no-save @turf/turf@7 pngjs && node build-cavite-layers.mjs <out-dir>
import * as turf from '@turf/turf';
import fs from 'fs';
import { PNG } from 'pngjs';

const OUT = process.argv[2];
fs.mkdirSync(OUT, { recursive: true });
const round = (geom, d = 5) => {
  const r = c => typeof c[0] === 'number' ? [+c[0].toFixed(d), +c[1].toFixed(d)] : c.map(r);
  return { ...geom, coordinates: r(geom.coordinates) };
};
const clean = name => name.replace(/^City of (.+)$/, '$1 City').replace('Gen. Mariano Alvarez', 'General Mariano Alvarez').replace('Dasmariñas', 'Dasmarinas');

// ---------- Municipal + provincial boundaries ----------
const muni = JSON.parse(fs.readFileSync('cav_hires.json'));
const municipalities = turf.featureCollection(muni.features.map(f => {
  const s = turf.simplify(f, { tolerance: 0.00025, highQuality: true });
  return turf.feature(round(s.geometry), { name: clean(f.properties.adm3_en), psgc: String(f.properties.adm3_psgc).padStart(10, '0') });
}));
fs.writeFileSync(`${OUT}/cavite-municipalities.json`, JSON.stringify(municipalities));

let province = turf.union(turf.featureCollection(muni.features.map(f => turf.buffer(f, 0.02, { units: 'kilometers' }))));
province = turf.simplify(province, { tolerance: 0.0003, highQuality: true });
// Drop slivers/holes left by buffering between municipalities.
const polys = province.geometry.type === 'Polygon' ? [province.geometry.coordinates] : province.geometry.coordinates;
const outline = turf.feature(round({ type: 'MultiPolygon', coordinates: polys.filter(p => turf.area(turf.polygon(p)) > 20000).map(p => [p[0]]) }), { name: 'Cavite' });
fs.writeFileSync(`${OUT}/cavite-boundary.json`, JSON.stringify(turf.featureCollection([outline])));
console.log('province km2', (turf.area(outline) / 1e6).toFixed(0), 'bbox', turf.bbox(outline).map(v => v.toFixed(4)).join(','));

// ---------- Barangays ----------
const barangays = [];
for (const file of fs.readdirSync('bgy')) {
  const d = JSON.parse(fs.readFileSync(`bgy/${file}`));
  const mname = clean(muni.features.find(f => String(f.properties.adm3_psgc) === file.replace('.json', '')).properties.adm3_en);
  for (const f of d.features) { if (!f.geometry) { console.log("no geometry", f.properties.adm4_en); continue; }
    const s = turf.simplify(f, { tolerance: 0.00015, highQuality: true });
    barangays.push(turf.feature(round(s.geometry), { name: f.properties.adm4_en, municipality: mname, psgc: String(f.properties.adm4_psgc).padStart(10, '0') }));
  }
}
fs.writeFileSync(`${OUT}/cavite-barangays.json`, JSON.stringify(turf.featureCollection(barangays)));
console.log('barangays', barangays.length);

// ---------- DEM (Terrarium tiles, z12 ≈ 37 m/px) ----------
const Z = 12, N = 2 ** Z;
const [W, S, E, Nn] = [120.55, 14.03, 121.10, 14.62];
const tx = lng => (lng + 180) / 360 * N;
const ty = lat => (1 - Math.log(Math.tan(lat * Math.PI / 180) + 1 / Math.cos(lat * Math.PI / 180)) / Math.PI) / 2 * N;
const x0 = Math.floor(tx(W)), x1 = Math.floor(tx(E)), y0 = Math.floor(ty(Nn)), y1 = Math.floor(ty(S));
const cols = (x1 - x0 + 1) * 256, rows = (y1 - y0 + 1) * 256;
const dem = new Float32Array(cols * rows);
fs.mkdirSync('tiles', { recursive: true });
for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) {
  const path = `tiles/${Z}_${x}_${y}.png`;
  if (!fs.existsSync(path)) {
    const res = await fetch(`https://s3.amazonaws.com/elevation-tiles-prod/terrarium/${Z}/${x}/${y}.png`);
    fs.writeFileSync(path, Buffer.from(await res.arrayBuffer()));
  }
  const png = PNG.sync.read(fs.readFileSync(path));
  for (let py = 0; py < 256; py++) for (let px = 0; px < 256; px++) {
    const i = (py * 256 + px) * 4;
    dem[((y - y0) * 256 + py) * cols + (x - x0) * 256 + px] = png.data[i] * 256 + png.data[i + 1] + png.data[i + 2] / 256 - 32768;
  }
}
const pxLng = c => (x0 + (c + .5) / 256) / N * 360 - 180;
const pxLat = r => { const n = Math.PI - 2 * Math.PI * (y0 + (r + .5) / 256) / N; return 180 / Math.PI * Math.atan(Math.sinh(n)); };
const pxMeters = 156543.03 * Math.cos(14.3 * Math.PI / 180) / N;
const slopeAt = (r, c) => {
  const z = (rr, cc) => dem[Math.min(rows - 1, Math.max(0, rr)) * cols + Math.min(cols - 1, Math.max(0, cc))];
  const dzdx = ((z(r - 1, c + 1) + 2 * z(r, c + 1) + z(r + 1, c + 1)) - (z(r - 1, c - 1) + 2 * z(r, c - 1) + z(r + 1, c - 1))) / (8 * pxMeters);
  const dzdy = ((z(r + 1, c - 1) + 2 * z(r + 1, c) + z(r + 1, c + 1)) - (z(r - 1, c - 1) + 2 * z(r - 1, c) + z(r - 1, c + 1))) / (8 * pxMeters);
  return Math.atan(Math.hypot(dzdx, dzdy)) * 180 / Math.PI;
};

// Aggregate into ~220 m analysis cells.
const STEP = 0.002;
const gw = Math.round((E - W) / STEP), gh = Math.round((Nn - S) / STEP);
const cell = Array.from({ length: gw * gh }, () => ({ n: 0, sum: 0, low: 0, steep15: 0, steep25: 0 }));
for (let r = 1; r < rows - 1; r++) {
  const lat = pxLat(r); if (lat < S || lat >= Nn) continue;
  const gy = Math.floor((lat - S) / STEP);
  for (let c = 1; c < cols - 1; c++) {
    const lng = pxLng(c); if (lng < W || lng >= E) continue;
    const g = cell[gy * gw + Math.floor((lng - W) / STEP)], h = dem[r * cols + c], s = slopeAt(r, c);
    g.n++; g.sum += h; if (h <= 0.5) g.low++; if (s >= 15) g.steep15++; if (s >= 25) g.steep25++;
  }
}
const muniPolys = municipalities.features;
const insideCavite = new Uint8Array(gw * gh);
const bboxes = muniPolys.map(f => turf.bbox(f));
for (let gy = 0; gy < gh; gy++) for (let gx = 0; gx < gw; gx++) {
  const pt = [W + (gx + .5) * STEP, S + (gy + .5) * STEP];
  insideCavite[gy * gw + gx] = muniPolys.some((f, i) => pt[0] >= bboxes[i][0] && pt[0] <= bboxes[i][2] && pt[1] >= bboxes[i][1] && pt[1] <= bboxes[i][3] && turf.booleanPointInPolygon(pt, f)) ? 1 : 0;
}
// Sea cells: outside Cavite and mostly at/below sea level, west/north of the province (excludes Laguna de Bay side).
const dist = new Float32Array(gw * gh).fill(1e9);
const queue = [];
for (let i = 0; i < gw * gh; i++) if (!insideCavite[i] && cell[i].n && cell[i].low / cell[i].n > .6) { dist[i] = 0; queue.push(i); }
const cellKm = STEP * 111;
for (let pass = 0; pass < 2; pass++) { // two-pass chamfer distance transform
  const order = pass === 0 ? [...Array(gw * gh).keys()] : [...Array(gw * gh).keys()].reverse();
  for (const i of order) {
    const gx = i % gw, gy = (i / gw) | 0;
    for (const [dx, dy, w] of [[-1, 0, 1], [1, 0, 1], [0, -1, 1], [0, 1, 1], [-1, -1, 1.414], [1, 1, 1.414], [-1, 1, 1.414], [1, -1, 1.414]]) {
      const nx = gx + dx, ny = gy + dy; if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
      const d = dist[ny * gw + nx] + w * cellKm; if (d < dist[i]) dist[i] = d;
    }
  }
}

function polygonize(test) {
  const rects = [];
  for (let gy = 0; gy < gh; gy++) {
    let start = -1;
    for (let gx = 0; gx <= gw; gx++) {
      const on = gx < gw && test(gy * gw + gx);
      if (on && start < 0) start = gx;
      if (!on && start >= 0) {
        const w = W + start * STEP, e = W + gx * STEP, s = S + gy * STEP, n = s + STEP;
        rects.push(turf.polygon([[[w, s], [e, s], [e, n], [w, n], [w, s]]]));
        start = -1;
      }
    }
  }
  if (!rects.length) return null;
  let merged = turf.union(turf.featureCollection(rects));
  merged = turf.simplify(merged, { tolerance: 0.0006, highQuality: false });
  const parts = (merged.geometry.type === 'Polygon' ? [merged.geometry.coordinates] : merged.geometry.coordinates)
    .filter(p => turf.area(turf.polygon(p)) > 150000); // drop specks < 0.15 km²
  return parts.length ? round({ type: 'MultiPolygon', coordinates: parts }) : null;
}

const mean = i => cell[i].n ? cell[i].sum / cell[i].n : 999;
const COAST_KM = 3;
const layers = [
  { kind: 'tsunami', level: 'high', label: 'Tsunami & storm-surge exposure — high', description: `Coastal land at or below 5 m elevation within ${COAST_KM} km of Manila Bay / the West Philippine Sea. Evacuate inland or to higher ground on a tsunami warning or strong ground shaking.`, test: i => insideCavite[i] && dist[i] <= COAST_KM && mean(i) <= 5 },
  { kind: 'tsunami', level: 'moderate', label: 'Tsunami & storm-surge exposure — moderate', description: `Coastal land between 5 m and 10 m elevation within ${COAST_KM} km of the shoreline. Be ready to move to higher ground.`, test: i => insideCavite[i] && dist[i] <= COAST_KM && mean(i) > 5 && mean(i) <= 10 },
  { kind: 'landslide', level: 'high', label: 'Landslide susceptibility — high', description: 'Steep terrain where at least 30% of the ground has slopes of 25° or more (ridges, ravines, river gorges). Watch for cracks, tilting trees and muddy springs during heavy rain.', test: i => insideCavite[i] && cell[i].n && cell[i].steep25 / cell[i].n >= .3 },
  { kind: 'landslide', level: 'moderate', label: 'Landslide susceptibility — moderate', description: 'Hilly terrain where at least 35% of the ground has slopes of 15° or more. Prolonged or heavy rainfall can trigger slope failure.', test: i => insideCavite[i] && cell[i].n && cell[i].steep25 / cell[i].n < .3 && cell[i].steep15 / cell[i].n >= .35 },
];
const features = [];
for (const layer of layers) {
  const geom = polygonize(layer.test);
  if (!geom) { console.log('empty', layer.kind, layer.level); continue; }
  const { test, ...props } = layer;
  features.push(turf.feature(geom, props));
  console.log(layer.kind, layer.level, 'km2', (turf.area(geom) / 1e6).toFixed(1), 'parts', geom.coordinates.length);
}
fs.writeFileSync(`${OUT}/cavite-geohazards.json`, JSON.stringify(turf.featureCollection(features)));
for (const f of fs.readdirSync(OUT)) console.log(f, fs.statSync(`${OUT}/${f}`).size);
