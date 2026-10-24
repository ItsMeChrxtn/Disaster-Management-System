import 'package:latlong2/latlong.dart';

/// Mirrors frontend/config.js. The API base URL can be overridden at runtime
/// from the login screen (stored in SharedPreferences) so the same APK can be
/// pointed at a local XAMPP server (http://10.0.2.2/... on the emulator).
class AppConfig {
  /// Local XAMPP server on the LAN for now (phone must be on the same Wi-Fi).
  /// Override at build time with --dart-define=API_URL=... (e.g. the live
  /// domain, or http://10.0.2.2/... for the Android emulator), or at runtime
  /// from the API server settings dialog.
  static const String defaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://192.168.1.8/Disaster-Management-System/backend/public/api');

  static const LatLng mapCenter = LatLng(14.2554073, 120.8671503);
  // PSA Cavite boundary extent (assets/data/cavite-boundary.json, incl.
  // Corregidor) plus ~1 km padding; the camera lock keeps the view inside it.
  static final LatLng mapBoundsSouthWest = const LatLng(14.0470, 120.5520);
  static final LatLng mapBoundsNorthEast = const LatLng(14.5100, 121.0880);
  static const double mapZoom = 10;
  static const double mapMinZoom = 9;
  static const Duration alertPoll = Duration(seconds: 30);

  // EmailJS (same account as the web frontend) used for the verification code.
  static const String emailJsPublicKey = '1Iu7NRjXvLh_DplPB';
  static const String emailJsServiceId = 'service_0kagnzg';
  static const String emailJsVerifyTemplateId = 'template_kyg4m7m';

  /// Origin sent to EmailJS so the request is accepted like a browser call.
  static const String emailJsOrigin = 'https://darkturquoise-skunk-797617.hostingersite.com';

  static const String psgcCaviteProvince = '042100000';
}
