import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config.dart';
import 'geo.dart';

/// PSGC barangay lookup and Photon/Nominatim geocoding used by the facility
/// form (safeZonePsgcCode / photonSafeZoneSearch / nominatimSafeZoneSearch).
class Geocode {
  Geocode._();

  static List<Map<String, dynamic>>? _psgcPlaces;
  static final Map<String, List<Map<String, dynamic>>> _barangayCache = {};

  static const _headers = {'Accept': 'application/json', 'User-Agent': 'DisasterMap/1.0 (com.disastermap.app)'};

  static const Map<String, String> _diacritics = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'å': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ñ': 'n',
    'ç': 'c',
  };

  /// Equivalent of normalizeSafeZonePlace (NFD + strip diacritics + strip
  /// barangay/city prefixes) so "City of Dasmariñas" matches "Dasmarinas City".
  static String normalizePlace(String value) {
    var text = value.toLowerCase();
    _diacritics.forEach((from, to) => text = text.replaceAll(from, to));
    return text.replaceAll(RegExp(r'\b(brgy|barangay|city of|municipality of|pob\.?|poblacion)\b'), ' ').replaceAll(RegExp(r'\bgen\.\s*'), 'general ').replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static Future<String> psgcCode(String cityName) async {
    if (_psgcPlaces == null) {
      final response = await http.get(Uri.parse('https://psgc.gitlab.io/api/provinces/${AppConfig.psgcCaviteProvince}/cities-municipalities.json'), headers: _headers);
      if (response.statusCode != 200) throw Exception('Unable to load Cavite cities and municipalities');
      _psgcPlaces = (jsonDecode(utf8.decode(response.bodyBytes)) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    final target = normalizePlace(cityName);
    final places = _psgcPlaces!;
    final exact = places.where((p) => normalizePlace(p['name'].toString()) == target).firstOrNull;
    if (exact != null) return exact['code'].toString();
    final partial = places.where((p) {
      final name = normalizePlace(p['name'].toString());
      return name.contains(target) || target.contains(name);
    }).firstOrNull;
    return partial?['code']?.toString() ?? '';
  }

  static Future<List<Map<String, dynamic>>> barangays(String cityName) async {
    final code = await psgcCode(cityName);
    if (code.isEmpty) throw Exception('City or municipality was not found in PSGC');
    final cached = _barangayCache[code];
    if (cached != null) return cached;
    final response = await http.get(Uri.parse('https://psgc.gitlab.io/api/cities-municipalities/$code/barangays.json'), headers: _headers);
    if (response.statusCode != 200) throw Exception('Unable to load barangays');
    final rows = (jsonDecode(utf8.decode(response.bodyBytes)) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    rows.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
    _barangayCache[code] = rows;
    return rows;
  }

  /// Finds the barangay in [rows] mentioned in [text] (matchSafeZoneBarangay).
  static Map<String, dynamic>? matchBarangay(List<Map<String, dynamic>> rows, String text) {
    final normalized = normalizePlace(text);
    final parts = text.split(',').map(normalizePlace).where((p) => p.isNotEmpty).toList();
    for (final row in rows) {
      final name = normalizePlace(row['name'].toString());
      if (name.length <= 1) continue;
      if (normalized.contains(name) || name.contains(normalized)) return row;
      if (parts.any((part) => part.contains(name) || name.contains(part))) return row;
    }
    return null;
  }

  /// Finds the municipality option whose name is mentioned in [text].
  static Map<String, dynamic>? matchMunicipality(List<Map<String, dynamic>> options, String text) {
    final normalized = normalizePlace(text);
    final parts = text.split(',').map(normalizePlace).where((p) => p.isNotEmpty).toList();
    for (final option in options) {
      final label = normalizePlace(option['municipality_name'].toString());
      if (label.isEmpty) continue;
      if (normalized.contains(label) || label.contains(normalized)) return option;
      if (parts.any((part) => part.contains(label) || label.contains(part))) return option;
    }
    return null;
  }

  static Future<Map<String, dynamic>?> photonFeature(String query, {int limit = 8}) async {
    final response = await http.get(
      Uri.parse('https://photon.komoot.io/api/?q=${Uri.encodeQueryComponent(query)}&limit=$limit&lat=${AppConfig.mapCenter.latitude}&lon=${AppConfig.mapCenter.longitude}'),
      headers: _headers,
    );
    if (response.statusCode != 200) return null;
    final features = (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['features'] as List? ?? [];
    for (final feature in features.whereType<Map>()) {
      final coords = (feature['geometry'] as Map?)?['coordinates'] as List?;
      if (coords == null || coords.length < 2) continue;
      final point = LatLng(double.parse(coords[1].toString()), double.parse(coords[0].toString()));
      if (Geo.inCavite(point)) return Map<String, dynamic>.from(feature);
    }
    return null;
  }

  static Future<LatLng?> photonSearch(String query) async {
    final feature = await photonFeature(query, limit: 5);
    if (feature == null) return null;
    final coords = (feature['geometry'] as Map)['coordinates'] as List;
    return LatLng(double.parse(coords[1].toString()), double.parse(coords[0].toString()));
  }

  static Future<LatLng?> nominatimSearch(String query) async {
    final b = Geo.caviteBounds;
    final viewbox = '${b.west},${b.north},${b.east},${b.south}';
    final response = await http.get(
      Uri.parse('https://nominatim.openstreetmap.org/search?format=jsonv2&limit=3&countrycodes=ph&bounded=1&viewbox=$viewbox&q=${Uri.encodeQueryComponent(query)}'),
      headers: _headers,
    );
    if (response.statusCode != 200) return null;
    final rows = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    if (rows.isEmpty) return null;
    final first = rows.first as Map;
    return LatLng(double.parse(first['lat'].toString()), double.parse(first['lon'].toString()));
  }
}
