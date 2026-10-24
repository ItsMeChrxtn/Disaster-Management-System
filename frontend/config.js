const appOrigin = location.protocol === 'file:'
  ? 'http://localhost'
  : (location.port && !['80', '443'].includes(location.port)
      ? `${location.protocol}//${location.hostname}`
      : location.origin);

const appBasePath = location.protocol === 'file:'
  ? '/Disaster-Management-System'
  : location.pathname.replace(/\/frontend\/?.*$/, '').replace(/\/$/, '');

window.DISASTER_MAP_CONFIG = {
  API_URL: window.DISASTER_MAP_API_URL || `${appOrigin}${appBasePath}/backend/public/api`,
  MAP_CENTER: [14.2554073, 120.8671503],
  MAP_BOUNDS: [[14.035, 120.535], [14.52, 121.1]],
  MAP_ZOOM: 10,
  ALERT_POLL_MS: 30000,
  EMAILJS_PUBLIC_KEY: window.EMAILJS_PUBLIC_KEY || '1Iu7NRjXvLh_DplPB',
  EMAILJS_SERVICE_ID: window.EMAILJS_SERVICE_ID || 'service_0kagnzg',
  EMAILJS_USER_PASSWORD_TEMPLATE_ID: window.EMAILJS_USER_PASSWORD_TEMPLATE_ID || 'template_f65jlcs',
  EMAILJS_VERIFY_TEMPLATE_ID: window.EMAILJS_VERIFY_TEMPLATE_ID || 'template_kyg4m7m'
};
