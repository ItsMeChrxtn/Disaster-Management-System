// Shared Cavite GIS helpers: province lock + mask, geohazard reference layers,
// barangay/municipality lookups, and the colour scales used across the app.
window.CaviteGIS = (() => {
  const DATA_VERSION = '20261009';
  const config = window.DISASTER_MAP_CONFIG || {};
  const BOUNDS = L.latLngBounds(config.MAP_BOUNDS || [[14.035, 120.535], [14.52, 121.1]]);
  const cache = new Map();
  const maps = [];

  const RISK = {
    critical: { hex: '#dc2626', label: 'Critical', meaning: 'Imminent danger to life and property. Pre-emptive or forced evacuation.' },
    high: { hex: '#ea580c', label: 'High', meaning: 'Severe impact is likely. Prepare to evacuate; move vulnerable residents first.' },
    moderate: { hex: '#d97706', label: 'Moderate', meaning: 'Some impact is possible. Monitor advisories and prepare go-bags.' },
    low: { hex: '#059669', label: 'Low', meaning: 'Minor impact expected. Stay informed and keep routes clear.' }
  };

  const HAZARD_TYPES = {
    flood_zone: { label: 'Flood', hex: '#2563eb', symbol: 'F' },
    storm_surge_area: { label: 'Storm surge', hex: '#7c3aed', symbol: 'S' },
    landslide: { label: 'Landslide', hex: '#a16207', symbol: 'L' },
    earthquake_area: { label: 'Earthquake', hex: '#be123c', symbol: 'Q' },
    tsunami: { label: 'Tsunami', hex: '#0891b2', symbol: 'T' },
    volcanic: { label: 'Volcanic / ashfall', hex: '#57534e', symbol: 'V' },
    fire: { label: 'Fire', hex: '#ef4444', symbol: 'FR' },
    high_risk_area: { label: 'High-risk area', hex: '#475569', symbol: 'H' }
  };

  // PAGASA Heavy Rainfall Warning System.
  const RAINFALL = [
    { color: 'yellow', hex: '#facc15', ink: '#713f12', label: 'Yellow', range: '7.5–15 mm/hr', meaning: 'Heavy rain. Flooding is possible in low-lying areas and near rivers.', action: 'Monitor the weather' },
    { color: 'orange', hex: '#f97316', ink: '#7c2d12', label: 'Orange', range: '15–30 mm/hr', meaning: 'Intense rain. Flooding is threatening.', action: 'Prepare to evacuate' },
    { color: 'red', hex: '#dc2626', ink: '#ffffff', label: 'Red', range: 'over 30 mm/hr', meaning: 'Torrential rain. Serious flooding expected in low-lying areas.', action: 'Evacuate now' }
  ];

  // US EPA Air Quality Index bands.
  const AQI = [
    { max: 50, label: 'Good', hex: '#16a34a', mask: 'No mask needed' },
    { max: 100, label: 'Moderate', hex: '#ca8a04', mask: 'Sensitive people limit long outdoor activity' },
    { max: 150, label: 'Unhealthy for sensitive groups', hex: '#ea580c', mask: 'Sensitive groups wear a face mask' },
    { max: 200, label: 'Unhealthy', hex: '#dc2626', mask: 'Everyone wears a face mask outdoors' },
    { max: 300, label: 'Very unhealthy', hex: '#7e22ce', mask: 'N95 mask; stay indoors' },
    { max: Infinity, label: 'Hazardous', hex: '#7f1d1d', mask: 'Health emergency; stay indoors' }
  ];

  const GEO_STYLE = {
    tsunami: { high: '#0369a1', moderate: '#38bdf8' },
    landslide: { high: '#92400e', moderate: '#d97706' }
  };

  function escape(value) {
    const div = document.createElement('div');
    div.textContent = value ?? '';
    return div.innerHTML;
  }

  function data(name) {
    if (!cache.has(name)) {
      cache.set(name, fetch(`assets/data/${name}.json?v=${DATA_VERSION}`).then(response => {
        if (!response.ok) throw new Error(`Unable to load ${name}`);
        return response.json();
      }));
    }
    return cache.get(name);
  }

  function rings(geometry) {
    if (!geometry) return [];
    if (geometry.type === 'Feature') return rings(geometry.geometry);
    if (geometry.type === 'FeatureCollection') return geometry.features.flatMap(rings);
    if (geometry.type === 'GeometryCollection') return geometry.geometries.flatMap(rings);
    if (geometry.type === 'Polygon') return [geometry.coordinates];
    if (geometry.type === 'MultiPolygon') return geometry.coordinates;
    return [];
  }

  function inRing(ring, [x, y]) {
    let inside = false;
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      const [xi, yi] = ring[i], [xj, yj] = ring[j];
      if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / ((yj - yi) || 1e-12) + xi) inside = !inside;
    }
    return inside;
  }

  // point is [lng, lat]
  function pointInGeometry(geometry, point) {
    return rings(geometry).some(polygon => inRing(polygon[0], point) && !polygon.slice(1).some(hole => inRing(hole, point)));
  }

  function bbox(polygons) {
    const box = [Infinity, Infinity, -Infinity, -Infinity];
    polygons.forEach(polygon => polygon[0].forEach(([x, y]) => {
      if (x < box[0]) box[0] = x; if (y < box[1]) box[1] = y;
      if (x > box[2]) box[2] = x; if (y > box[3]) box[3] = y;
    }));
    return box;
  }

  function segmentsCross([a, b], [c, d]) {
    const orient = (p, q, r) => Math.sign((q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]));
    return orient(a, b, c) !== orient(a, b, d) && orient(c, d, a) !== orient(c, d, b);
  }

  function polygonsIntersect(a, b) {
    const ringsA = a.map(p => p[0]), ringsB = b.map(p => p[0]);
    if (ringsA.some(ring => ring.some(pt => b.some(poly => inRing(poly[0], pt))))) return true;
    if (ringsB.some(ring => ring.some(pt => a.some(poly => inRing(poly[0], pt))))) return true;
    for (const ra of ringsA) for (let i = 0; i < ra.length - 1; i++) {
      for (const rb of ringsB) for (let j = 0; j < rb.length - 1; j++) {
        if (segmentsCross([ra[i], ra[i + 1]], [rb[j], rb[j + 1]])) return true;
      }
    }
    return false;
  }

  // Barangays whose boundary touches a drawn hazard polygon.
  async function barangaysIn(geojson) {
    const hazard = rings(geojson);
    if (!hazard.length) return [];
    const box = bbox(hazard);
    const { features } = await data('cavite-barangays');
    return features.filter(feature => {
      const polygons = rings(feature.geometry);
      const b = feature._bbox || (feature._bbox = bbox(polygons));
      if (b[0] > box[2] || b[2] < box[0] || b[1] > box[3] || b[3] < box[1]) return false;
      return polygonsIntersect(hazard, polygons);
    }).map(feature => ({ name: feature.properties.name, municipality: feature.properties.municipality }));
  }

  async function barangaysOf(municipalityName) {
    const key = normalizeName(municipalityName);
    const { features } = await data('cavite-barangays');
    return features.filter(f => normalizeName(f.properties.municipality) === key).map(f => f.properties.name).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  }

  async function locate(lat, lng) {
    const point = [lng, lat];
    const [{ features: barangays }, { features: municipalities }] = await Promise.all([data('cavite-barangays'), data('cavite-municipalities')]);
    const barangay = barangays.find(f => pointInGeometry(f.geometry, point));
    const municipality = barangay ? barangay.properties.municipality : municipalities.find(f => pointInGeometry(f.geometry, point))?.properties.name;
    return { barangay: barangay?.properties.name || null, municipality: municipality || null };
  }

  async function geohazardsAt(lat, lng) {
    const { features } = await data('cavite-geohazards');
    return features.filter(f => pointInGeometry(f.geometry, [lng, lat])).map(f => f.properties);
  }

  function normalizeName(value) {
    return String(value || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\b(city of|city|municipality of)\b/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
  }

  function sameMunicipality(a, b) {
    return normalizeName(a) === normalizeName(b);
  }

  // ---------- Province lock ----------
  function ensurePane(map, name, zIndex) {
    if (!map.getPane(name)) {
      const pane = map.createPane(name);
      pane.style.zIndex = zIndex;
      if (name === 'caviteMask') pane.style.pointerEvents = 'none';
    }
  }

  function addMask(map, collection) {
    if (map._caviteMask) return;
    ensurePane(map, 'caviteMask', 350);
    const holes = rings(collection).map(polygon => polygon[0].map(([x, y]) => [y, x]));
    const world = [[-85, -180], [85, -180], [85, 180], [-85, 180]];
    map._caviteMask = L.layerGroup([
      L.polygon([world, ...holes], { pane: 'caviteMask', interactive: false, stroke: false, fillColor: '#e2e8f0', fillOpacity: .8 }),
      L.polygon(holes, { pane: 'caviteMask', interactive: false, fill: false, color: '#1e3a8a', weight: 2.2, opacity: .75 })
    ]).addTo(map);
  }

  function restrict(map, { mask = true } = {}) {
    maps.push(map);
    map.options.zoomSnap = Math.min(map.options.zoomSnap ?? 1, .25);
    map.setMaxBounds(BOUNDS);
    map.options.maxBoundsViscosity = 1;
    const fit = () => {
      const size = map.getSize();
      if (size.x < 80 || size.y < 80) return;
      map.setMinZoom(Math.max(8, Math.min(12, map.getBoundsZoom(BOUNDS, false))));
    };
    fit();
    map.on('resize', fit);
    // Containers often change size after init (hidden views, stretching grids).
    if (window.ResizeObserver) new ResizeObserver(() => map.invalidateSize({ pan: false })).observe(map.getContainer());
    if (mask) data('cavite-boundary').then(collection => addMask(map, collection)).catch(() => {});
    return map;
  }

  // ---------- Earthquake epicenters (USGS) ----------
  function quakeColor(mag) {
    return mag >= 5 ? '#b91c1c' : mag >= 4 ? '#ea580c' : '#f59e0b';
  }

  function loadQuakes() {
    if (!cache.has('usgs')) {
      const since = new Date(Date.now() - 10 * 365.25 * 864e5).toISOString().slice(0, 10);
      const url = `https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&minlatitude=13.75&maxlatitude=14.85&minlongitude=120.2&maxlongitude=121.4&minmagnitude=3&starttime=${since}&orderby=time&limit=300`;
      cache.set('usgs', fetch(url).then(response => {
        if (!response.ok) throw new Error('USGS earthquake feed unavailable');
        return response.json();
      }).then(json => json.features.map(f => ({
        id: f.id,
        magnitude: Number(f.properties.mag),
        place: f.properties.place || 'Unnamed location',
        time: new Date(f.properties.time),
        depth: Number(f.geometry.coordinates[2]),
        lat: f.geometry.coordinates[1],
        lng: f.geometry.coordinates[0],
        url: f.properties.url
      }))));
    }
    return cache.get('usgs');
  }

  async function nearestMunicipality(lat, lng) {
    const { features } = await data('cavite-municipalities');
    let best = null;
    features.forEach(feature => {
      const box = feature._bbox || (feature._bbox = bbox(rings(feature.geometry)));
      const distance = L.latLng(lat, lng).distanceTo([(box[1] + box[3]) / 2, (box[0] + box[2]) / 2]);
      if (!best || distance < best.distance) best = { name: feature.properties.name, distance, inside: pointInGeometry(feature.geometry, [lng, lat]) };
    });
    return best;
  }

  function formatDate(date, withTime = true) {
    return date.toLocaleString('en-PH', { timeZone: 'Asia/Manila', year: 'numeric', month: 'short', day: 'numeric', ...(withTime ? { hour: 'numeric', minute: '2-digit' } : {}) });
  }

  function depthClass(depth) {
    return depth < 70 ? 'shallow' : depth < 300 ? 'intermediate' : 'deep';
  }

  async function quakePopup(q) {
    const near = await nearestMunicipality(q.lat, q.lng).catch(() => null);
    const where = near ? (near.inside ? `Inside ${escape(near.name)}` : `${(near.distance / 1000).toFixed(0)} km from ${escape(near.name)}`) : '';
    return `<div class="geo-popup"><span class="geo-popup-kicker" style="--geo:${quakeColor(q.magnitude)}">Earthquake epicenter</span><strong>Magnitude ${q.magnitude.toFixed(1)}</strong><p>${escape(q.place)}</p><dl><div><dt>Date &amp; time</dt><dd>${formatDate(q.time)} PHT</dd></div><div><dt>Depth</dt><dd>${q.depth.toFixed(0)} km (${depthClass(q.depth)})</dd></div>${where ? `<div><dt>Nearest Cavite area</dt><dd>${where}</dd></div>` : ''}</dl><small>Source: USGS earthquake catalog${q.url ? ` · <a href="${escape(q.url)}" target="_blank" rel="noopener">details</a>` : ''}</small></div>`;
  }

  // ---------- Geohazard reference control ----------
  function geohazardControl(map, { position = 'topright', show = {}, collapsed = false, onQuakes } = {}) {
    const visible = { tsunami: true, landslide: true, quakes: true, ...show };
    ensurePane(map, 'geohazards', 380);
    const layers = { tsunami: L.featureGroup(), landslide: L.featureGroup(), quakes: L.featureGroup() };
    let zonesLoaded = false, quakesLoaded = false;

    function zoneStyle(feature) {
      const color = GEO_STYLE[feature.properties.kind][feature.properties.level];
      return { pane: 'geohazards', color, weight: 1, opacity: .8, fillColor: color, fillOpacity: feature.properties.level === 'high' ? .42 : .26 };
    }

    async function ensureZones() {
      if (zonesLoaded) return;
      zonesLoaded = true;
      const { features } = await data('cavite-geohazards');
      features.forEach(feature => {
        L.geoJSON(feature, { style: zoneStyle, pane: 'geohazards' })
          .bindPopup(`<div class="geo-popup"><span class="geo-popup-kicker" style="--geo:${GEO_STYLE[feature.properties.kind][feature.properties.level]}">${feature.properties.kind === 'tsunami' ? 'Tsunami-prone coast' : 'Landslide-prone slope'}</span><strong>${escape(feature.properties.label)}</strong><p>${escape(feature.properties.description)}</p><small>Derived from SRTM elevation data. For planning reference; confirm with MGB / PHIVOLCS hazard maps.</small></div>`, { maxWidth: 320 })
          .addTo(layers[feature.properties.kind]);
      });
    }

    async function ensureQuakes(status) {
      if (quakesLoaded) return;
      quakesLoaded = true;
      status.textContent = 'Loading USGS feed…';
      try {
        const quakes = await loadQuakes();
        const inView = quakes.filter(q => BOUNDS.contains([q.lat, q.lng]));
        inView.slice().reverse().forEach(q => {
          const marker = L.circleMarker([q.lat, q.lng], { pane: 'geohazards', radius: 4 + Math.max(0, q.magnitude - 3) * 3.4, color: '#fff', weight: 1.5, fillColor: quakeColor(q.magnitude), fillOpacity: .88 });
          marker.bindPopup(() => { quakePopup(q).then(html => marker.setPopupContent(html)); return '<div class="geo-popup"><p>Loading…</p></div>'; }, { maxWidth: 320 });
          marker.bindTooltip(`M${q.magnitude.toFixed(1)} · ${formatDate(q.time, false)}`, { direction: 'top' });
          marker.addTo(layers.quakes);
        });
        const latest = inView[0];
        if (latest) {
          L.marker([latest.lat, latest.lng], { pane: 'geohazards', interactive: false, icon: L.divIcon({ className: 'geo-quake-pulse', iconSize: [44, 44], iconAnchor: [22, 22], html: '<span></span>' }) }).addTo(layers.quakes);
        }
        status.innerHTML = latest
          ? `${inView.length} epicenter${inView.length === 1 ? '' : 's'} in view since ${new Date(Date.now() - 10 * 365.25 * 864e5).getFullYear()} · latest <b>M${latest.magnitude.toFixed(1)}</b> on ${formatDate(latest.time, false)}`
          : 'No M3+ epicenters recorded in this area.';
        onQuakes?.(quakes, inView);
      } catch (error) {
        quakesLoaded = false;
        status.textContent = error.message;
      }
    }

    const Control = L.Control.extend({
      options: { position },
      onAdd() {
        const box = L.DomUtil.create('div', `geo-control${collapsed ? ' is-collapsed' : ''}`);
        box.innerHTML = `
          <button type="button" class="geo-control-toggle" aria-expanded="${!collapsed}"><span class="geo-control-icon"></span>Geohazard layers</button>
          <div class="geo-control-body">
            <label class="geo-row"><input type="checkbox" data-geo="tsunami"${visible.tsunami ? ' checked' : ''}><span><b>Tsunami-prone coast</b><small>Low-lying land within 3 km of the sea</small></span></label>
            <ul class="geo-legend"><li><i style="background:${GEO_STYLE.tsunami.high}"></i>High · 5 m or lower</li><li><i style="background:${GEO_STYLE.tsunami.moderate}"></i>Moderate · 5–10 m</li></ul>
            <label class="geo-row"><input type="checkbox" data-geo="landslide"${visible.landslide ? ' checked' : ''}><span><b>Landslide-prone slopes</b><small>Steep ridges, ravines and gorges</small></span></label>
            <ul class="geo-legend"><li><i style="background:${GEO_STYLE.landslide.high}"></i>High · slopes 25°+</li><li><i style="background:${GEO_STYLE.landslide.moderate}"></i>Moderate · slopes 15°+</li></ul>
            <label class="geo-row"><input type="checkbox" data-geo="quakes"${visible.quakes ? ' checked' : ''}><span><b>Earthquake epicenters</b><small>USGS, magnitude 3+, last 10 years</small></span></label>
            <ul class="geo-legend geo-legend-dots"><li><i style="background:${quakeColor(3)}"></i>M3–3.9</li><li><i style="background:${quakeColor(4)}"></i>M4–4.9</li><li><i style="background:${quakeColor(5)}"></i>M5+</li></ul>
            <p class="geo-status" data-geo-status></p>
          </div>`;
        L.DomEvent.disableClickPropagation(box);
        L.DomEvent.disableScrollPropagation(box);
        const status = box.querySelector('[data-geo-status]');
        const apply = async input => {
          const key = input.dataset.geo;
          if (input.checked) {
            if (key === 'quakes') ensureQuakes(status); else await ensureZones();
            layers[key].addTo(map);
          } else map.removeLayer(layers[key]);
        };
        box.querySelectorAll('[data-geo]').forEach(input => {
          input.addEventListener('change', () => apply(input));
          if (input.checked) apply(input);
        });
        box.querySelector('.geo-control-toggle').addEventListener('click', event => {
          const isCollapsed = box.classList.toggle('is-collapsed');
          event.currentTarget.setAttribute('aria-expanded', String(!isCollapsed));
        });
        return box;
      }
    });
    const control = new Control();
    control.addTo(map);
    return { control, layers };
  }

  // ---------- Weather icons ----------
  const ICON_PARTS = {
    sun: '<g class="wx-sun"><circle cx="24" cy="24" r="8.5" fill="#f59e0b"/><g stroke="#f59e0b" stroke-width="2.6" stroke-linecap="round"><path d="M24 6v4M24 38v4M6 24h4M38 24h4M11.3 11.3l2.8 2.8M33.9 33.9l2.8 2.8M11.3 36.7l2.8-2.8M33.9 14.1l2.8-2.8"/></g></g>',
    moon: '<path d="M30.5 9.5a13 13 0 1 0 8 23.3A15 15 0 0 1 30.5 9.5Z" fill="#818cf8"/>',
    smallSun: '<g><circle cx="17" cy="17" r="6.5" fill="#f59e0b"/><g stroke="#f59e0b" stroke-width="2.2" stroke-linecap="round"><path d="M17 4.5v3M4.5 17h3M8.2 8.2l2.1 2.1M25.8 8.2l-2.1 2.1M8.2 25.8l2.1-2.1"/></g></g>',
    smallMoon: '<path d="M21 7a9.5 9.5 0 1 0 5.8 17A11 11 0 0 1 21 7Z" fill="#818cf8"/>',
    cloud: '<path d="M15 37h19.5a8 8 0 0 0 .7-16 11 11 0 0 0-21.1 2.7A6.7 6.7 0 0 0 15 37Z" fill="#e2e8f0" stroke="#94a3b8" stroke-width="1.6"/>',
    darkCloud: '<path d="M15 33h19.5a8 8 0 0 0 .7-16 11 11 0 0 0-21.1 2.7A6.7 6.7 0 0 0 15 33Z" fill="#94a3b8" stroke="#64748b" stroke-width="1.6"/>',
    rain: '<g stroke="#2563eb" stroke-width="2.4" stroke-linecap="round"><path d="M18 37l-2 5M25 37l-2 5M32 37l-2 5"/></g>',
    heavyRain: '<g stroke="#1d4ed8" stroke-width="2.6" stroke-linecap="round"><path d="M15 37l-2.4 6M21 37l-2.4 6M27 37l-2.4 6M33 37l-2.4 6"/></g>',
    drizzle: '<g fill="#3b82f6"><circle cx="18" cy="40" r="1.6"/><circle cx="25" cy="42" r="1.6"/><circle cx="31" cy="40" r="1.6"/></g>',
    bolt: '<path d="M25 33l-5 8h5l-3 6 9-10h-5l3-4Z" fill="#facc15" stroke="#ca8a04" stroke-width="1"/>',
    fog: '<g stroke="#94a3b8" stroke-width="2.4" stroke-linecap="round"><path d="M10 40h28M14 44h20"/></g>'
  };

  function weatherIcon(code, isDay = true, size = 44) {
    const c = Number(code), p = ICON_PARTS;
    let body;
    if (c === 0 || c === 1) body = isDay ? p.sun : p.moon;
    else if (c === 2) body = (isDay ? p.smallSun : p.smallMoon) + p.cloud;
    else if (c === 3) body = p.cloud;
    else if (c === 45 || c === 48) body = p.cloud + p.fog;
    else if (c >= 51 && c <= 57) body = p.darkCloud + p.drizzle;
    else if (c === 65 || c === 82 || c === 67) body = p.darkCloud + p.heavyRain;
    else if ((c >= 61 && c <= 67) || (c >= 80 && c <= 81)) body = p.darkCloud + p.rain;
    else if (c >= 95) body = p.darkCloud + p.bolt;
    else body = p.cloud;
    return `<svg class="wx-icon" width="${size}" height="${size}" viewBox="0 0 48 48" aria-hidden="true">${body}</svg>`;
  }

  function aqiBand(aqi) {
    return AQI.find(band => aqi <= band.max) || AQI[AQI.length - 1];
  }

  // ~700 PDRRMO evacuation centers: below zoom 13 facility pins shrink to dots so the province view stays readable.
  function compactFacilities(map){const sync=()=>map.getContainer().classList.toggle('facility-compact',map.getZoom()<13);map.whenReady(sync);map.on('zoomend',sync);return map;}
  return {maps, BOUNDS, RISK, HAZARD_TYPES, RAINFALL, AQI, GEO_STYLE,
    data, restrict, geohazardControl, loadQuakes, quakeColor, formatDate,
    pointInGeometry, barangaysIn, barangaysOf, locate, geohazardsAt, sameMunicipality, normalizeName,
    weatherIcon, aqiBand, escape,compactFacilities};
})();
