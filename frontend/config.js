const xamppOrigin = location.protocol === 'file:'
  ? 'http://localhost'
  : (location.port && !['80', '443'].includes(location.port)
      ? `${location.protocol}//${location.hostname}`
      : location.origin);

window.DISASTER_MAP_CONFIG = {
  API_URL: window.DISASTER_MAP_API_URL || `${xamppOrigin}/Disaster-Management-System/backend/public/api`,
  MAP_CENTER: [14.2554073, 120.8671503],
  MAP_BOUNDS: [[14.0568738, 120.4161392], [14.5856400, 121.0776824]],
  MAP_ZOOM: 10,
  ALERT_POLL_MS: 30000
};
