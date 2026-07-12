const caviteBounds = L.latLngBounds(Config.MAP_BOUNDS);
const map = L.map('map', {
  zoomControl: true,
  maxBounds: caviteBounds,
  maxBoundsViscosity: 1,
  minZoom: 9
}).setView(Config.MAP_CENTER, Config.MAP_ZOOM);

const streetLayer = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
  maxZoom: 19,
  attribution: '&copy; OpenStreetMap contributors'
}).addTo(map);

const satelliteLayer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
  maxZoom: 19,
  attribution: 'Tiles &copy; Esri'
});

L.control.layers({ 'Street map': streetLayer, 'Satellite imagery': satelliteLayer }, null, { position: 'bottomright' }).addTo(map);

const riskColors = { low: '#10b981', moderate: '#f59e0b', high: '#f97316', critical: '#dc2626' };
const layerColors = { flood: '#2563eb', storm: '#7c3aed', earthquake: '#f97316' };
const layers = {
  flood: L.featureGroup().addTo(map),
  storm: L.featureGroup().addTo(map),
  earthquake: L.featureGroup().addTo(map),
  safeZones: L.featureGroup().addTo(map),
  centers: L.featureGroup().addTo(map)
};

let searchMarker;
let municipalitiesLoaded = false;

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

function hazardIcon(key, risk) {
  return L.divIcon({
    className: `dm-marker dm-marker-hazard dm-marker-${key} dm-risk-${risk || 'moderate'}`,
    html: `<span>${key === 'flood' ? 'F' : key === 'storm' ? 'S' : 'Q'}</span>`,
    iconSize: [34, 42],
    iconAnchor: [17, 38],
    popupAnchor: [0, -34]
  });
}

function hazardPopup(item, label) {
  return popupCard(
    safe(item.hazard_name),
    `${safe(label)} - <b>${safe(item.risk_level)} risk</b>`,
    safe(item.description || 'No description'),
    safe(item.municipality_name || 'Province-wide')
  );
}

function addHazards(rows, layer, key, label) {
  rows.forEach(item => {
    L.geoJSON(item.geojson_data, {
      style: {
        color: layerColors[key],
        weight: 3.5,
        fillColor: riskColors[item.risk_level] || layerColors[key],
        fillOpacity: .24,
        opacity: .95
      },
      pointToLayer: (feature, latlng) => L.marker(latlng, { icon: hazardIcon(key, item.risk_level) })
    }).bindPopup(hazardPopup(item, label)).addTo(layer);
  });
}

function addSafeZones(rows) {
  rows.forEach(item => {
    const contact = [item.contact_person ? `Contact person: <b>${safe(item.contact_person)}</b>` : '', item.contact_number ? `Contact number: ${safe(item.contact_number)}` : ''].filter(Boolean).join('<br>');
    L.marker([item.latitude, item.longitude], { icon: markerIcon('safe', 'SZ') })
      .bindPopup(popupCard(
        safe(item.safezone_name),
        'Safe zone',
        `${safe(item.address)}<br>Capacity: <b>${item.capacity}</b>${contact ? `<br>${contact}` : ''}`,
        safe(item.municipality_name)
      ))
      .addTo(layers.safeZones);
  });
}

function addCenters(rows) {
  rows.forEach(item => {
    const contact = [item.contact_person ? `Contact person: <b>${safe(item.contact_person)}</b>` : '', item.contact_number ? `Contact number: ${safe(item.contact_number)}` : ''].filter(Boolean).join('<br>');
    L.marker([item.latitude, item.longitude], { icon: markerIcon('center', 'EC') })
      .bindPopup(popupCard(
        safe(item.center_name),
        `Evacuation center - <b>${safe(item.status)}</b>`,
        `${safe(item.address)}<br>Capacity: <b>${item.capacity}</b>${contact ? `<br>${contact}` : ''}`,
        safe(item.municipality_name)
      ))
      .addTo(layers.centers);
  });
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
    addSafeZones(data.safe_zone_layer);
    addCenters(data.evacuation_center_layer);

    if (!municipalitiesLoaded) {
      const select = document.getElementById('municipalityFilter');
      data.municipalities.forEach(item => select.add(new Option(item.municipality_name, item.id)));
      municipalitiesLoaded = true;
    }

    const total = data.flood_layer.length + data.storm_surge_layer.length + data.earthquake_layer.length + data.safe_zone_layer.length + data.evacuation_center_layer.length;
    status.textContent = `${total} mapped feature${total === 1 ? '' : 's'} in Cavite`;
    if (fit) fitVisible();
  } catch (error) {
    status.textContent = 'GIS data unavailable';
    toast(error.message);
  }
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
  ['flood', 'storm', 'earthquake'].forEach(key => {
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

document.getElementById('locateBtn').addEventListener('click', () => map.locate({ setView: false, maxZoom: 16, enableHighAccuracy: true }));

map.on('locationfound', event => {
  if (!caviteBounds.contains(event.latlng)) {
    toast('Your current location is outside Cavite');
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

map.on('locationerror', () => toast('Unable to access your location'));

if (Api.token()) {
  document.getElementById('accountLink').textContent = 'Dashboard';
  document.getElementById('accountLink').href = 'dashboard.html';
}

loadGisLayers();

async function loadAlerts() {
  try {
    const alerts = await Api.get('/alerts');
    const el = document.getElementById('alertStrip');
    if (!alerts.length) {
      el.classList.add('hidden');
      return;
    }
    const alert = alerts[0];
    el.innerHTML = `<strong>${safe(alert.title)}</strong><p class="text-sm">${safe(alert.message)}</p>`;
    el.classList.remove('hidden');
  } catch {}
}

loadAlerts();
setInterval(loadAlerts, Config.ALERT_POLL_MS);
