// Optional override. config.js already derives API_URL from the current
// origin (frontend/ and backend/ as siblings under the same domain), which
// is correct for a standard single-hosting-account deployment. Only set
// API_URL here if the API is genuinely served from a different host.
window.DISASTER_MAP_CONFIG = {
  API_URL: 'https://yourdomain.com/backend/public/api',
  MAP_CENTER: [14.2554073, 120.8671503],
  MAP_BOUNDS: [[14.035, 120.535], [14.52, 121.1]],
  MAP_ZOOM: 10,
  ALERT_POLL_MS: 30000
};
