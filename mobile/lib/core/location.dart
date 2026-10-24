import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// navigator.geolocation replacement.
class Location {
  Location._();

  /// Returns null when permission is denied or the service is off (same
  /// as browserLocation()/weatherPosition() resolving null on the web).
  static Future<LatLng?> tryCurrent({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      return await current(timeout: timeout);
    } catch (_) {
      return null;
    }
  }

  /// Throws with the same wording as currentPosition() in dashboard.js.
  static Future<LatLng> current({Duration timeout = const Duration(seconds: 10)}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are disabled on this device');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required to plan a route');
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return LatLng(last.latitude, last.longitude);
      throw Exception('Unable to access your location');
    }
  }
}
