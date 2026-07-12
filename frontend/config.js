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
  ALERT_POLL_MS: 30000,
  EMAILJS_PUBLIC_KEY: window.EMAILJS_PUBLIC_KEY || 'zBJUBMTfHj-iPH73d',
  EMAILJS_SERVICE_ID: window.EMAILJS_SERVICE_ID || 'service_iiqpju1',
  EMAILJS_USER_PASSWORD_TEMPLATE_ID: window.EMAILJS_USER_PASSWORD_TEMPLATE_ID || 'template_f65jlcs'
};
