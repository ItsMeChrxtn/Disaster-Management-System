import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';

/// Parsed GeoJSON split into the primitives flutter_map can draw.
class GeoShapes {
  final List<List<LatLng>> polygons = [];
  final List<List<LatLng>> lines = [];
  final List<LatLng> points = [];

  bool get isEmpty => polygons.isEmpty && lines.isEmpty && points.isEmpty;

  LatLngBounds? get bounds {
    final all = <LatLng>[...points, for (final p in polygons) ...p, for (final l in lines) ...l];
    if (all.isEmpty) return null;
    return LatLngBounds.fromPoints(all);
  }
}

class Geo {
  Geo._();

  static final LatLngBounds caviteBounds = LatLngBounds(AppConfig.mapBoundsSouthWest, AppConfig.mapBoundsNorthEast);

  /// Province lock (CaviteGIS.restrict in cavite-gis.js): the viewport can never
  /// leave Cavite or zoom out past the whole province.
  static const CameraConstraint caviteConstraint = CaviteLock();

  /// Outer rings of the official PSA Cavite boundary (assets/data/cavite-boundary.json).
  static Future<List<List<LatLng>>>? _boundary;
  static Future<List<List<LatLng>>> caviteBoundary() => _boundary ??= rootBundle.loadString('assets/data/cavite-boundary.json').then((text) {
    final shapes = parse(jsonDecode(text));
    return shapes.polygons;
  });

  static bool inCavite(LatLng point) => caviteBounds.contains(point);

  static LatLng? _coord(dynamic pair) {
    if (pair is! List || pair.length < 2) return null;
    final lng = double.tryParse(pair[0].toString());
    final lat = double.tryParse(pair[1].toString());
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  static List<LatLng> _ring(dynamic ring) {
    if (ring is! List) return [];
    return ring.map(_coord).whereType<LatLng>().toList();
  }

  /// Walks any GeoJSON value (geometry, Feature, FeatureCollection,
  /// GeometryCollection) and collects drawable shapes.
  static GeoShapes parse(dynamic geojson, [GeoShapes? into]) {
    final out = into ?? GeoShapes();
    if (geojson is! Map) return out;
    final type = geojson['type']?.toString();
    switch (type) {
      case 'FeatureCollection':
        for (final feature in (geojson['features'] as List? ?? [])) {
          parse(feature, out);
        }
      case 'Feature':
        parse(geojson['geometry'], out);
      case 'GeometryCollection':
        for (final geometry in (geojson['geometries'] as List? ?? [])) {
          parse(geometry, out);
        }
      case 'Point':
        final point = _coord(geojson['coordinates']);
        if (point != null) out.points.add(point);
      case 'MultiPoint':
        for (final pair in (geojson['coordinates'] as List? ?? [])) {
          final point = _coord(pair);
          if (point != null) out.points.add(point);
        }
      case 'LineString':
        final line = _ring(geojson['coordinates']);
        if (line.length >= 2) out.lines.add(line);
      case 'MultiLineString':
        for (final line in (geojson['coordinates'] as List? ?? [])) {
          final parsed = _ring(line);
          if (parsed.length >= 2) out.lines.add(parsed);
        }
      case 'Polygon':
        final rings = geojson['coordinates'] as List? ?? [];
        if (rings.isNotEmpty) {
          final outer = _ring(rings.first);
          if (outer.length >= 3) out.polygons.add(outer);
        }
      case 'MultiPolygon':
        for (final polygon in (geojson['coordinates'] as List? ?? [])) {
          if (polygon is List && polygon.isNotEmpty) {
            final outer = _ring(polygon.first);
            if (outer.length >= 3) out.polygons.add(outer);
          }
        }
    }
    return out;
  }

  /// The outer ring of the first polygon (`[lng, lat]` pairs) for vertex editing.
  static List<List<double>>? editableRing(dynamic geojson) {
    if (geojson is! Map) return null;
    final g = geojson['type'] == 'Feature' ? geojson['geometry'] : geojson;
    if (g is! Map) return null;
    List? ring;
    if (g['type'] == 'Polygon') ring = (g['coordinates'] as List?)?.firstOrNull as List?;
    if (g['type'] == 'MultiPolygon') ring = ((g['coordinates'] as List?)?.firstOrNull as List?)?.firstOrNull as List?;
    if (ring == null) return null;
    return ring.map((pair) => pair is List && pair.length >= 2 ? [double.tryParse(pair[0].toString()) ?? 0, double.tryParse(pair[1].toString()) ?? 0] : null).whereType<List<double>>().toList();
  }

  static Map<String, dynamic> geojsonWithRing(dynamic geojson, List<List<double>> ring) {
    final next = deepCopy(geojson) as Map<String, dynamic>;
    final target = next['type'] == 'Feature' ? next['geometry'] as Map : next;
    if (target['type'] == 'Polygon') {
      (target['coordinates'] as List)[0] = ring;
    } else if (target['type'] == 'MultiPolygon') {
      ((target['coordinates'] as List)[0] as List)[0] = ring;
    }
    return next;
  }

  static dynamic deepCopy(dynamic value) {
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), deepCopy(v)));
    if (value is List) return value.map(deepCopy).toList();
    return value;
  }

  static Map<String, dynamic> polygonFromPoints(List<LatLng> points) {
    final ring = points.map((p) => [round7(p.longitude), round7(p.latitude)]).toList();
    ring.add([...ring.first]);
    return {
      'type': 'Polygon',
      'coordinates': [ring],
    };
  }

  static Map<String, dynamic> rectangleFromCorners(LatLng a, LatLng b) {
    final west = math.min(a.longitude, b.longitude), east = math.max(a.longitude, b.longitude);
    final south = math.min(a.latitude, b.latitude), north = math.max(a.latitude, b.latitude);
    return {
      'type': 'Polygon',
      'coordinates': [
        [
          [west, south],
          [east, south],
          [east, north],
          [west, north],
          [west, south],
        ],
      ],
    };
  }

  static double round7(double value) => (value * 1e7).round() / 1e7;

  /// Spherical ring area (same formula as hazardAreaSquareMeters in dashboard.js).
  static double areaSquareMeters(List<List<double>> ring) {
    const radius = 6378137.0;
    var area = 0.0;
    for (var i = 0; i < ring.length - 1; i++) {
      final x1 = ring[i][0], y1 = ring[i][1], x2 = ring[i + 1][0], y2 = ring[i + 1][1];
      area += (x2 - x1) * math.pi / 180 * (2 + math.sin(y1 * math.pi / 180) + math.sin(y2 * math.pi / 180));
    }
    return (area * radius * radius / 2).abs();
  }

  static double distanceKm(LatLng a, LatLng b) => const Distance().as(LengthUnit.Kilometer, a, b);

  /// Approximate 16 km box around a municipality centre (focusMunicipality in dashboard.js).
  static LatLngBounds municipalityBox(LatLng center, {double meters = 16000}) {
    final half = meters / 2;
    final dLat = half / 111320;
    final dLng = half / (111320 * math.cos(center.latitude * math.pi / 180));
    return LatLngBounds(LatLng(center.latitude - dLat, center.longitude - dLng), LatLng(center.latitude + dLat, center.longitude + dLng));
  }

  static LatLng? municipalityCenter(Map<String, dynamic>? row) {
    if (row == null) return null;
    final lat = double.tryParse(row['center_lat']?.toString() ?? '');
    final lng = double.tryParse(row['center_lng']?.toString() ?? '');
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }
}

/// Convenience builders for map layers.
Polygon<T> stylePolygon<T extends Object>(List<LatLng> points, Color color, {double fillOpacity = .28, double width = 3, T? hitValue}) {
  return Polygon<T>(
    points: points,
    color: color.withValues(alpha: fillOpacity),
    borderColor: color,
    borderStrokeWidth: width,
    hitValue: hitValue,
  );
}

/// Below this zoom the ~700 facility pins are drawn as small dots so the province view stays readable.
const double kFacilityPinZoom = 12.5;

/// Pin with an icon when zoomed in, a compact dot when zoomed out.
Marker facilityMarker(LatLng point, Color color, IconData icon, {required bool compact, VoidCallback? onTap, double size = 38}) =>
    compact ? circleMarker(point, color, size: 11, onTap: onTap, border: Colors.white) : pinMarker(point, color, icon, onTap: onTap, size: size);

Marker circleMarker(LatLng point, Color color, {double size = 18, VoidCallback? onTap, Color border = Colors.white}) {
  return Marker(
    point: point,
    width: size,
    height: size,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 2.5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
        ),
      ),
    ),
  );
}

Marker pinMarker(LatLng point, Color color, IconData icon, {VoidCallback? onTap, double size = 40}) {
  return Marker(
    point: point,
    width: size,
    height: size,
    alignment: Alignment.topCenter,
    child: GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Icon(
            Icons.location_pin,
            color: color,
            size: size,
            shadows: const [Shadow(color: Colors.black38, blurRadius: 4)],
          ),
          Positioned(
            top: size * .15,
            child: Icon(icon, color: Colors.white, size: size * .38),
          ),
        ],
      ),
    ),
  );
}

TileLayer osmTileLayer() => TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.disastermap.app', maxZoom: 19);

TileLayer satelliteTileLayer() =>
    TileLayer(urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', userAgentPackageName: 'com.disastermap.app', maxZoom: 19);

Widget osmAttribution() =>
    const RichAttributionWidget(alignment: AttributionAlignment.bottomLeft, showFlutterMapAttribution: false, attributions: [TextSourceAttribution('OpenStreetMap contributors')]);

void fitMap(MapController controller, LatLngBounds? bounds, {double padding = 36, double maxZoom = 15}) {
  if (bounds == null) return;
  if (bounds.north == bounds.south && bounds.east == bounds.west) {
    controller.move(bounds.center, maxZoom);
    return;
  }
  controller.fitCamera(CameraFit.bounds(bounds: bounds, padding: EdgeInsets.all(padding), maxZoom: maxZoom));
}

/// Ray-casting point-in-polygon test used for tap hit detection on hazards.
bool pointInRing(LatLng point, List<LatLng> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i].longitude, yi = ring[i].latitude;
    final xj = ring[j].longitude, yj = ring[j].latitude;
    final intersects = ((yi > point.latitude) != (yj > point.latitude)) && (point.longitude < (xj - xi) * (point.latitude - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi);
    if (intersects) inside = !inside;
  }
  return inside;
}

/// Planar area of a ring in square degrees – only used to pick the smallest
/// polygon when several overlap under a tap.
double ringAreaDegrees(List<LatLng> ring) {
  var area = 0.0;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    area += (ring[j].longitude + ring[i].longitude) * (ring[j].latitude - ring[i].latitude);
  }
  return area.abs() / 2;
}

/// Province lock: the map can't zoom out past the whole of Cavite, and on any
/// axis where Cavite is bigger than the screen the edges are clamped so you
/// can't pan beyond it (on the smaller axis Cavite stays centred; the
/// [CaviteMaskLayer] greys the leftover band). Unlike [CameraConstraint.contain]
/// it never fails when the screen is bigger than the province. [focus]
/// optionally also clamps the centre (sub-admin's own municipality).
@immutable
class CaviteLock extends CameraConstraint {
  const CaviteLock({this.focus});

  final LatLngBounds? focus;

  @override
  MapCamera? constrain(MapCamera camera) {
    final bounds = Geo.caviteBounds;
    final size = camera.size;
    if (size.width <= 0 || size.height <= 0) return camera;

    var zoom = camera.zoom;
    var nw = camera.projectAtZoom(bounds.northWest, zoom);
    var se = camera.projectAtZoom(bounds.southEast, zoom);
    // Fit the province to the screen: "contain" would leave bands outside
    // Cavite on a tall phone, so the grey mask covers the rest instead.
    final fit = math.min(size.width / (se.dx - nw.dx), size.height / (se.dy - nw.dy));
    // Tolerances keep constrain() idempotent; flutter_map asserts on that.
    if (fit > 1 + 1e-6) {
      zoom += math.log(fit) / math.ln2;
      nw = camera.projectAtZoom(bounds.northWest, zoom);
      se = camera.projectAtZoom(bounds.southEast, zoom);
    }

    var center = camera.center;
    final focusBox = focus;
    if (focusBox != null) {
      center = LatLng(center.latitude.clamp(focusBox.south, focusBox.north), center.longitude.clamp(focusBox.west, focusBox.east));
    }
    final pixel = camera.projectAtZoom(center, zoom);
    double axis(double value, double min, double max, double half) => max - min <= half * 2 ? (min + max) / 2 : value.clamp(min + half, max - half);
    final clamped = Offset(axis(pixel.dx, nw.dx, se.dx, size.width / 2), axis(pixel.dy, nw.dy, se.dy, size.height / 2));
    if (zoom == camera.zoom && (clamped - pixel).distance < 0.5) return camera;
    return camera.withPosition(center: camera.unprojectAtZoom(clamped, zoom), zoom: zoom);
  }

  @override
  bool operator ==(Object other) => other is CaviteLock && other.focus == focus;

  @override
  int get hashCode => focus.hashCode;
}

/// flutter_map never runs the camera constraint on the initial camera or when
/// the map is resized, so a size-dependent lock like [CaviteLock] has to be
/// re-applied then (otherwise the camera sits outside it and debug builds
/// assert on the next rebuild). Pass as `MapOptions.onMapEvent`.
void reapplyCameraConstraint(MapController controller, MapEvent event) {
  if (event is MapEventNonRotatedSizeChange) {
    controller.move(event.camera.center, event.camera.zoom);
  }
}

/// Greys out everything outside the PSA Cavite boundary and outlines the
/// province (the web map's mask in cavite-gis.js).
class CaviteMaskLayer extends StatelessWidget {
  const CaviteMaskLayer({super.key});

  static final List<LatLng> _world = [const LatLng(25, 110), const LatLng(25, 132), const LatLng(3, 132), const LatLng(3, 110)];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<LatLng>>>(
      future: Geo.caviteBoundary(),
      builder: (context, snapshot) {
        final rings = snapshot.data;
        if (rings == null || rings.isEmpty) return const SizedBox.shrink();
        return PolygonLayer(
          polygons: [
            Polygon(points: _world, holePointsList: rings, color: const Color(0xFF0F172A).withValues(alpha: .5)),
            for (final ring in rings) Polygon(points: ring, color: Colors.transparent, borderColor: const Color(0xFF1D4ED8), borderStrokeWidth: 2.5),
          ],
        );
      },
    );
  }
}
