const caviteBounds = CaviteGIS.BOUNDS;
const map = CaviteGIS.restrict(window.CaviteGIS?.compactFacilities?.(L.map('map', { zoomControl: true, maxBoundsViscosity: 1, zoomSnap: .25 }))).setView(Config.MAP_CENTER, Config.MAP_ZOOM);

const streetLayer = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
  maxZoom: 19,
  attribution: '&copy; OpenStreetMap contributors'
}).addTo(map);

const satelliteLayer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
  maxZoom: 19,
  attribution: 'Tiles &copy; Esri'
});

L.control.layers({ 'Street map': streetLayer, 'Satellite imagery': satelliteLayer }, null, { position: 'bottomright' }).addTo(map);
CaviteGIS.geohazardControl(map, { position: 'topright' });

const riskColors = Object.fromEntries(Object.entries(CaviteGIS.RISK).map(([key, value]) => [key, value.hex]));
const layerColors = { flood: '#2563eb', storm: '#7c3aed', earthquake: '#be123c', landslide: '#a16207', other: '#0891b2' };
const SAFE_ZONE_DEFAULT_RADIUS = 100;
const layers = {
  flood: L.featureGroup().addTo(map),
  storm: L.featureGroup().addTo(map),
  earthquake: L.featureGroup().addTo(map),
  landslide: L.featureGroup().addTo(map),
  other: L.featureGroup().addTo(map),
  safeZones: L.featureGroup().addTo(map),
  centers: L.featureGroup().addTo(map)
};

let searchMarker;
let municipalitiesLoaded = false;
let residentFocused = false;
const currentUser = JSON.parse(sessionStorage.getItem('dm_user') || 'null');

function safe(value) {
  const d = document.createElement('div');
  d.textContent = value ?? '';
  return d.innerHTML;
}

function popupCard(title, meta, body, footer) {
  return `<div class="map-popup-card"><strong>${title}</strong>${meta ? `<span>${meta}</span>` : ''}${body ? `<p>${body}</p>` : ''}${footer ? `<small>${footer}</small>` : ''}</div>`;
}

function markerIcon(type, symbol) {
  return L.divIcon({
    className: `dm-marker dm-marker-${type}`,
    html: `<span>${symbol}</span>`,
    iconSize: [38, 46],
    iconAnchor: [19, 42],
    popupAnchor: [0, -38]
  });
}

function hazardIcon(key, risk, type) {
  const symbol = CaviteGIS.HAZARD_TYPES[type]?.symbol || { flood: 'F', storm: 'S', earthquake: 'Q', landslide: 'L' }[key] || '!';
  return L.divIcon({
    className: `dm-marker dm-marker-hazard dm-marker-${key} dm-risk-${risk || 'moderate'}`,
    html: `<span>${safe(symbol)}</span>`,
    iconSize: [34, 42],
    iconAnchor: [17, 38],
    popupAnchor: [0, -34]
  });
}

function hazardPopup(item, label) {
  const typeLabel = CaviteGIS.HAZARD_TYPES[item.hazard_type]?.label || String(item.hazard_type || label).replaceAll('_', ' ');
  const risk = CaviteGIS.RISK[item.risk_level];
  return popupCard(
    safe(item.hazard_name),
    `${safe(label === 'Other hazard' ? typeLabel : label)} - <b>${safe(risk?.label || item.risk_level)} risk</b>`,
    `${safe(item.description || 'No description')}${risk ? `<br><i>${safe(risk.meaning)}</i>` : ''}`,
    `${safe(item.municipality_name || 'Province-wide')}${item.barangays ? ` · Brgy. ${safe(item.barangays)}` : ''}`
  );
}

function addHazards(rows, layer, key, label) {
  rows.forEach(item => {
    L.geoJSON(item.geojson_data, {
      style: {
        color: CaviteGIS.HAZARD_TYPES[item.hazard_type]?.hex || layerColors[key],
        weight: 3.5,
        fillColor: riskColors[item.risk_level] || layerColors[key],
        fillOpacity: .24,
        opacity: .95
      },
      pointToLayer: (feature, latlng) => L.marker(latlng, { icon: hazardIcon(key, item.risk_level, item.hazard_type) })
    }).bindPopup(hazardPopup(item, label)).addTo(layer);
  });
}

function addSafeZones(rows) {
  rows.forEach(item => {
    const contact = [item.contact_person ? `Contact person: <b>${safe(item.contact_person)}</b>` : '', item.contact_number ? `Contact number: ${safe(item.contact_number)}` : ''].filter(Boolean).join('<br>');
    const radius = Number(item.perimeter_radius_m) || SAFE_ZONE_DEFAULT_RADIUS;
    const card = popupCard(
      safe(item.safezone_name),
      'Safe zone - open gathering ground',
      `${safe(item.address)}<br>Capacity: <b>${item.capacity ?? 'n/a'}</b> · Perimeter: <b>${radius} m</b>${contact ? `<br>${contact}` : ''}`,
      safe(item.municipality_name)
    );
    L.circle([item.latitude, item.longitude], { radius, color: '#047857', weight: 2.5, fillColor: '#10b981', fillOpacity: .22 }).bindPopup(card).addTo(layers.safeZones);
    L.marker([item.latitude, item.longitude], { icon: facilityIcon('safe') })
      .bindPopup(card)
      .addTo(layers.safeZones);
  });
}

function addCenters(rows) {
  rows.forEach(item => {
    const contact = [item.contact_person ? `Contact person: <b>${safe(item.contact_person)}</b>` : '', item.contact_number ? `Contact number: ${safe(item.contact_number)}` : ''].filter(Boolean).join('<br>');
    const insideZone = safeZoneRows.find(zone => L.latLng(item.latitude, item.longitude).distanceTo([zone.latitude, zone.longitude]) <= (Number(zone.perimeter_radius_m) || SAFE_ZONE_DEFAULT_RADIUS));
    L.marker([item.latitude, item.longitude], { icon: facilityIcon('center'), zIndexOffset: 200 })
      .bindPopup(popupCard(
        safe(item.center_name),
        `Evacuation center (shelter) - <b>${safe(item.status)}</b>${insideZone ? ` · inside safe zone ${safe(insideZone.safezone_name)}` : ' · outside safe-zone perimeters'}`,
        `${safe(item.address)}<br>Capacity: <b>${item.capacity}</b>${contact ? `<br>${contact}` : ''}`,
        safe(item.municipality_name)
      ))
      .addTo(layers.centers);
  });
}

let safeZoneRows = [];

function facilityIcon(type) {
  return type === 'safe'
    ? L.divIcon({ className: 'facility-marker facility-marker-safe', iconSize: [36, 36], iconAnchor: [18, 18], popupAnchor: [0, -18], html: '<span class="facility-marker-safe-badge"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.8 19.5 5.6v5.6c0 4.9-3.1 8.6-7.5 10.9-4.4-2.3-7.5-6-7.5-10.9V5.6L12 2.8Z" fill="#fff"/><path d="m8.4 12 2.5 2.5 4.8-5" fill="none" stroke="#059669" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg></span>' })
    : L.divIcon({ className: 'facility-marker facility-marker-center', iconSize: [36, 46], iconAnchor: [18, 44], popupAnchor: [0, -40], html: '<span class="facility-marker-center-box"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3.5 11 12 4l8.5 7v9h-17v-9Z" fill="#fff"/><path d="M9.5 20v-5.5h5V20" fill="#2563eb"/></svg></span><i class="facility-marker-center-tip"></i>' });
}

function visibleBounds() {
  const bounds = L.latLngBounds([]);
  Object.values(layers).forEach(layer => {
    if (map.hasLayer(layer)) {
      const candidate = layer.getBounds();
      if (candidate.isValid()) bounds.extend(candidate);
    }
  });
  return bounds;
}

function constrainedBounds(bounds) {
  if (!bounds.isValid()) return null;
  const south = Math.max(bounds.getSouth(), caviteBounds.getSouth());
  const west = Math.max(bounds.getWest(), caviteBounds.getWest());
  const north = Math.min(bounds.getNorth(), caviteBounds.getNorth());
  const east = Math.min(bounds.getEast(), caviteBounds.getEast());
  return south <= north && west <= east ? L.latLngBounds([south, west], [north, east]) : null;
}

function fitVisible() {
  const bounds = constrainedBounds(visibleBounds());
  if (bounds) map.fitBounds(bounds, { padding: [35, 35], maxZoom: 15 });
  else toast('No visible Cavite map features to fit');
}

async function loadGisLayers(fit = false) {
  const status = document.getElementById('layerStatus');
  status.textContent = 'Loading GIS data...';

  try {
    const mid = document.getElementById('municipalityFilter').value;
    const query = mid ? `?municipality_id=${encodeURIComponent(mid)}` : '';
    const data = await Api.get(`/gis/layers${query}`);

    Object.values(layers).forEach(layer => layer.clearLayers());
    addHazards(data.flood_layer, layers.flood, 'flood', 'Flood zone');
    addHazards(data.storm_surge_layer, layers.storm, 'storm', 'Storm surge area');
    addHazards(data.earthquake_layer, layers.earthquake, 'earthquake', 'Earthquake area');
    addHazards(data.landslide_layer || [], layers.landslide, 'landslide', 'Landslide area');
    addHazards(data.other_hazard_layer || [], layers.other, 'other', 'Other hazard');
    safeZoneRows = data.safe_zone_layer;
    addSafeZones(data.safe_zone_layer);
    addCenters(data.evacuation_center_layer);

    if (!municipalitiesLoaded) {
      const select = document.getElementById('municipalityFilter');
      data.municipalities.forEach(item => select.add(new Option(item.municipality_name, item.id)));
      municipalitiesLoaded = true;
    }

    if (!residentFocused && currentUser?.role === 'resident' && currentUser?.municipality_id) {
      residentFocused = true;
      const own = data.municipalities.find(item => Number(item.id) === Number(currentUser.municipality_id));
      if (own?.center_lat && own?.center_lng) map.setView([Number(own.center_lat), Number(own.center_lng)], 13);
    }

    const total = data.flood_layer.length + data.storm_surge_layer.length + data.earthquake_layer.length + (data.landslide_layer || []).length + (data.other_hazard_layer || []).length + data.safe_zone_layer.length + data.evacuation_center_layer.length;
    status.textContent = `${total} mapped feature${total === 1 ? '' : 's'} in Cavite`;
    if (!mid) updateLandingStats(data);
    if (fit) fitVisible();
  } catch (error) {
    status.textContent = 'GIS data unavailable';
    setStatFallback('Data unavailable');
    toast(error.message);
  }
}

function updateLandingStats(data) {
  const hazardCount = data.flood_layer.length + data.storm_surge_layer.length + data.earthquake_layer.length + (data.landslide_layer || []).length + (data.other_hazard_layer || []).length;
  const facilityCount = data.safe_zone_layer.length + data.evacuation_center_layer.length;
  const municipalityCount = data.municipalities.length;

  const statHazards = document.getElementById('statHazards');
  if (statHazards) statHazards.textContent = `${hazardCount} hazard zone${hazardCount === 1 ? '' : 's'}`;

  const statFacilities = document.getElementById('statFacilities');
  if (statFacilities) statFacilities.textContent = `${facilityCount} safe facilit${facilityCount === 1 ? 'y' : 'ies'}`;

  const statMunicipalities = document.getElementById('statMunicipalities');
  if (statMunicipalities) statMunicipalities.textContent = `${municipalityCount} municipalities & cities`;

  const chips = document.getElementById('coverageChips');
  if (chips) chips.innerHTML = data.municipalities.map(item => `<span>${safe(item.municipality_name)}</span>`).join('');

  const summary = document.getElementById('coverageSummary');
  if (summary) summary.textContent = `${municipalityCount} municipalities and cities with mapped hazard, safe zone, and evacuation center data.`;
}

function setStatFallback(message) {
  ['statHazards', 'statFacilities', 'statMunicipalities'].forEach(id => {
    const el = document.getElementById(id);
    if (el && el.textContent === 'Loading...') el.textContent = message;
  });
}

document.getElementById('layerToggles').addEventListener('change', event => {
  const input = event.target.closest('input[data-layer]');
  if (!input) return;
  const layer = layers[input.dataset.layer];
  input.checked ? layer.addTo(map) : map.removeLayer(layer);
});

document.getElementById('municipalityFilter').addEventListener('change', () => loadGisLayers(true));

document.getElementById('hazardTypeFilter')?.addEventListener('change', event => {
  const selected = event.target.value;
  ['flood', 'storm', 'earthquake', 'landslide', 'other'].forEach(key => {
    const checkbox = document.querySelector(`[data-layer="${key}"]`);
    const visible = !selected || selected === key;
    checkbox.checked = visible;
    visible ? layers[key].addTo(map) : map.removeLayer(layers[key]);
  });
  fitVisible();
});

document.getElementById('fitLayersBtn').addEventListener('click', fitVisible);

document.getElementById('fullscreenMapBtn')?.addEventListener('click', () => {
  const shell = document.getElementById('publicMapShell');
  if (!document.fullscreenElement) shell.requestFullscreen?.();
  else document.exitFullscreen?.();
});

document.addEventListener('fullscreenchange', () => {
  setTimeout(() => map.invalidateSize(), 120);
  const button = document.getElementById('fullscreenMapBtn');
  if (button) button.textContent = document.fullscreenElement ? 'Exit full screen' : 'Full screen';
});

document.getElementById('locationSearchForm').addEventListener('submit', async event => {
  event.preventDefault();
  const input = document.getElementById('locationSearch');
  const button = event.currentTarget.querySelector('button');
  const query = input.value.trim();
  if (query.length < 2) return;

  button.disabled = true;
  button.textContent = 'Searching...';

  try {
    const viewbox = '120.4161392,14.5856400,121.0776824,14.0568738';
    const search = `${query}, Cavite, Philippines`;
    const response = await fetch(`https://nominatim.openstreetmap.org/search?format=jsonv2&limit=5&countrycodes=ph&bounded=1&viewbox=${viewbox}&q=${encodeURIComponent(search)}`, {
      headers: { Accept: 'application/json' }
    });

    if (!response.ok) throw new Error('Location search is temporarily unavailable');
    const results = await response.json();
    if (!results.length) throw new Error('Location not found within Cavite');

    const result = results[0];
    const lat = Number(result.lat);
    const lng = Number(result.lon);
    if (!caviteBounds.contains([lat, lng])) throw new Error('Location is outside Cavite');

    if (searchMarker) searchMarker.remove();
    searchMarker = L.marker([lat, lng], { icon: markerIcon('search', 'GO') })
      .addTo(map)
      .bindPopup(popupCard('Cavite search result', 'Selected location', safe(result.display_name), 'Search result'))
      .openPopup();

    const resultBounds = result.boundingbox?.length === 4
      ? constrainedBounds(L.latLngBounds([[Number(result.boundingbox[0]), Number(result.boundingbox[2])], [Number(result.boundingbox[1]), Number(result.boundingbox[3])]]))
      : null;

    if (resultBounds) map.fitBounds(resultBounds, { maxZoom: 17 });
    else map.setView([lat, lng], 16);
  } catch (error) {
    toast(error.message);
  } finally {
    button.disabled = false;
    button.textContent = 'Search';
  }
});

map.locate({ setView: false, maxZoom: 16, enableHighAccuracy: true });

map.on('locationfound', event => {
  if (!caviteBounds.contains(event.latlng)) {
    toast('Your current location is outside Cavite', 'warning');
    map.fitBounds(caviteBounds);
    return;
  }

  if (searchMarker) searchMarker.remove();
  searchMarker = L.marker(event.latlng, { icon: markerIcon('user', 'ME') })
    .addTo(map)
    .bindPopup(popupCard('Your approximate location', 'Browser location', `Accuracy: <b>${Math.round(event.accuracy)} m</b>`, 'Current device location'))
    .openPopup();
  map.setView(event.latlng, 16);
});

map.on('locationerror', () => toast('Unable to access your location', 'warning'));

if (Api.token()) {
  document.getElementById('accountLink').textContent = 'Dashboard';
  document.getElementById('accountLink').href = 'dashboard.html';
}

loadGisLayers();

async function loadAlerts() {
  try {
    const alerts = await Api.get('/alerts');
    const statAlerts = document.getElementById('statAlerts');
    if (statAlerts) statAlerts.textContent = alerts.length ? `${alerts.length} active alert${alerts.length === 1 ? '' : 's'}` : 'No active alerts';

    const el = document.getElementById('alertStrip');
    if (!alerts.length) {
      el.classList.add('hidden');
      return;
    }
    const alert = alerts[0];
    el.innerHTML = `<strong>${safe(alert.title)}</strong><p class="text-sm">${safe(alert.message)}</p>`;
    el.classList.remove('hidden');
  } catch {
    const statAlerts = document.getElementById('statAlerts');
    if (statAlerts && statAlerts.textContent === 'Loading...') statAlerts.textContent = 'Alerts unavailable';
  }
}

loadAlerts();
setInterval(loadAlerts, Config.ALERT_POLL_MS);
