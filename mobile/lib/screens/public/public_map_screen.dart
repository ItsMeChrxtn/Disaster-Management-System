import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../config.dart';
import '../../core/api.dart';
import '../../core/domain.dart';
import '../../core/geo.dart';
import '../../core/location.dart';
import '../../core/session.dart';
import '../../core/ui.dart';

class _HazardFeature {
  _HazardFeature(this.row, this.layer, this.label, this.shapes);

  final Map<String, dynamic> row;
  final String layer;
  final String label;
  final GeoShapes shapes;
}

/// Public GIS viewer (frontend/index.html + assets/js/map.js).
class PublicMapScreen extends StatefulWidget {
  const PublicMapScreen({super.key, this.embedded = false});

  /// True when shown inside the signed-in shell (no back button).
  final bool embedded;

  @override
  State<PublicMapScreen> createState() => _PublicMapScreenState();
}

class _PublicMapScreenState extends State<PublicMapScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  final Map<String, bool> _visible = {'flood': true, 'storm': true, 'earthquake': true, 'safeZones': true, 'centers': true};
  final List<_HazardFeature> _hazards = [];
  List<Map<String, dynamic>> _safeZones = [];
  List<Map<String, dynamic>> _centers = [];
  List<Map<String, dynamic>> _municipalities = [];
  String _municipalityId = '';
  String _hazardFilter = '';
  bool _satellite = false;
  bool _compactPins = true;
  bool _loading = true;
  bool _searching = false;
  bool _residentFocused = false;
  String _status = 'Loading GIS data...';
  LatLng? _searchPoint;
  String? _searchLabel;
  LatLng? _userPoint;
  double? _userAccuracy;

  @override
  void initState() {
    super.initState();
    _load();
    _locate();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool fit = false}) async {
    setState(() {
      _loading = true;
      _status = 'Loading GIS data...';
    });
    try {
      final query = _municipalityId.isNotEmpty ? '?municipality_id=$_municipalityId' : '';
      final data = mapOf(await Api.instance.get('/gis/layers$query'));
      _hazards.clear();
      void add(String key, String layer, String label) {
        for (final row in rowsOf(data[key])) {
          _hazards.add(_HazardFeature(row, layer, label, Geo.parse(row['geojson_data'])));
        }
      }

      add('flood_layer', 'flood', 'Flood zone');
      add('storm_surge_layer', 'storm', 'Storm surge area');
      add('earthquake_layer', 'earthquake', 'Earthquake area');
      _safeZones = rowsOf(data['safe_zone_layer']);
      _centers = rowsOf(data['evacuation_center_layer']);
      if (_municipalities.isEmpty) _municipalities = rowsOf(data['municipalities']);
      final total = _hazards.length + _safeZones.length + _centers.length;
      _status = '$total mapped feature${total == 1 ? '' : 's'} in Cavite';
      final session = Session.instance;
      if (!_residentFocused && session.isResident && session.municipalityId != null) {
        _residentFocused = true;
        final own = _municipalities.where((m) => intOf(m, 'id') == session.municipalityId).firstOrNull;
        final center = Geo.municipalityCenter(own);
        if (center != null) WidgetsBinding.instance.addPostFrameCallback((_) => _map.move(center, 13));
      }
      if (mounted) setState(() => _loading = false);
      if (fit) _fitVisible();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _status = 'GIS data unavailable';
        });
        Ui.toast(context, e.message, icon: 'error');
      }
    }
  }

  Future<void> _locate() async {
    final point = await Location.tryCurrent();
    if (point == null || !mounted) return;
    if (!Geo.inCavite(point)) {
      Ui.toast(context, 'Your current location is outside Cavite', icon: 'warning');
      return;
    }
    setState(() {
      _userPoint = point;
      _userAccuracy = null;
    });
    _map.move(point, 16);
  }

  LatLngBounds? _visibleBounds() {
    final points = <LatLng>[];
    for (final h in _hazards) {
      if (_visible[h.layer] != true) continue;
      final b = h.shapes.bounds;
      if (b != null) points.addAll([b.southWest, b.northEast]);
    }
    if (_visible['safeZones'] == true) {
      points.addAll(_safeZones.map((s) => LatLng(dbl(s, 'latitude') ?? 0, dbl(s, 'longitude') ?? 0)));
    }
    if (_visible['centers'] == true) {
      points.addAll(_centers.map((s) => LatLng(dbl(s, 'latitude') ?? 0, dbl(s, 'longitude') ?? 0)));
    }
    if (points.isEmpty) return null;
    final bounds = LatLngBounds.fromPoints(points);
    final cavite = Geo.caviteBounds;
    final south = bounds.south > cavite.south ? bounds.south : cavite.south;
    final west = bounds.west > cavite.west ? bounds.west : cavite.west;
    final north = bounds.north < cavite.north ? bounds.north : cavite.north;
    final east = bounds.east < cavite.east ? bounds.east : cavite.east;
    if (south > north || west > east) return null;
    return LatLngBounds(LatLng(south, west), LatLng(north, east));
  }

  void _fitVisible() {
    final bounds = _visibleBounds();
    if (bounds == null) {
      Ui.toast(context, 'No visible Cavite map features to fit', icon: 'warning');
      return;
    }
    fitMap(_map, bounds);
  }

  void _applyHazardFilter(String value) {
    setState(() {
      _hazardFilter = value;
      for (final key in ['flood', 'storm', 'earthquake']) {
        _visible[key] = value.isEmpty || value == key;
      }
    });
    _fitVisible();
  }

  Future<void> _searchLocation() async {
    final query = _search.text.trim();
    if (query.length < 2) return;
    setState(() => _searching = true);
    try {
      const viewbox = '120.4161392,14.5856400,121.0776824,14.0568738';
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search?format=jsonv2&limit=5&countrycodes=ph&bounded=1&viewbox=$viewbox&q=${Uri.encodeQueryComponent('$query, Cavite, Philippines')}'),
        headers: {'Accept': 'application/json', 'User-Agent': 'DisasterMap/1.0 (com.disastermap.app)'},
      );
      if (response.statusCode != 200) throw Exception('Location search is temporarily unavailable');
      final results = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      if (results.isEmpty) throw Exception('Location not found within Cavite');
      final result = results.first as Map;
      final point = LatLng(double.parse(result['lat'].toString()), double.parse(result['lon'].toString()));
      if (!Geo.inCavite(point)) throw Exception('Location is outside Cavite');
      setState(() {
        _searchPoint = point;
        _searchLabel = result['display_name']?.toString();
      });
      final box = result['boundingbox'];
      if (box is List && box.length == 4) {
        final bounds = LatLngBounds(LatLng(double.parse(box[0].toString()), double.parse(box[2].toString())), LatLng(double.parse(box[1].toString()), double.parse(box[3].toString())));
        fitMap(_map, bounds, maxZoom: 17);
      } else {
        _map.move(point, 16);
      }
    } catch (e) {
      if (mounted) Ui.toast(context, e.toString().replaceFirst('Exception: ', ''), icon: 'error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _onTap(LatLng point) {
    _HazardFeature? hit;
    double? hitArea;
    for (final h in _hazards) {
      if (_visible[h.layer] != true) continue;
      for (final ring in h.shapes.polygons) {
        if (pointInRing(point, ring)) {
          final area = ringAreaDegrees(ring);
          if (hitArea == null || area < hitArea) {
            hit = h;
            hitArea = area;
          }
        }
      }
    }
    if (hit != null) _showHazard(hit);
  }

  void _showHazard(_HazardFeature h) {
    final row = h.row;
    showDetailSheet(
      context,
      title: str(row, 'hazard_name'),
      kicker: '${h.label} - ${str(row, 'risk_level')} risk',
      color: Domain.layerColors[h.layer]!,
      icon: Icons.warning_amber_rounded,
      body: str(row, 'description', 'No description'),
      rows: [('Municipality', str(row, 'municipality_name', 'Province-wide'))],
    );
  }

  void _showSafeZone(Map<String, dynamic> s) {
    showDetailSheet(
      context,
      title: str(s, 'safezone_name'),
      kicker: 'Safe zone',
      color: Domain.safeZoneColor,
      icon: Icons.shield_outlined,
      rows: [
        ('Address', str(s, 'address', '-')),
        ('Capacity', str(s, 'capacity', '-')),
        if (str(s, 'contact_person').isNotEmpty) ('Contact person', str(s, 'contact_person')),
        if (str(s, 'contact_number').isNotEmpty) ('Contact number', str(s, 'contact_number')),
        ('Municipality', str(s, 'municipality_name', '-')),
      ],
    );
  }

  void _showCenter(Map<String, dynamic> c) {
    showDetailSheet(
      context,
      title: str(c, 'center_name'),
      kicker: 'Evacuation center - ${str(c, 'status')}',
      color: Domain.centerColor,
      icon: Icons.home_work_outlined,
      rows: [
        ('Address', str(c, 'address', '-')),
        ('Capacity', str(c, 'capacity', '-')),
        if (str(c, 'contact_person').isNotEmpty) ('Contact person', str(c, 'contact_person')),
        if (str(c, 'contact_number').isNotEmpty) ('Contact number', str(c, 'contact_number')),
        ('Municipality', str(c, 'municipality_name', '-')),
      ],
    );
  }

  List<Widget> _layers() {
    final polygons = <Polygon>[];
    final markers = <Marker>[];
    for (final h in _hazards) {
      if (_visible[h.layer] != true) continue;
      final color = Domain.layerColors[h.layer]!;
      final fill = Domain.publicRiskColors[str(h.row, 'risk_level')] ?? color;
      for (final ring in h.shapes.polygons) {
        polygons.add(Polygon(points: ring, color: fill.withValues(alpha: .24), borderColor: color, borderStrokeWidth: 3.5));
      }
      for (final point in h.shapes.points) {
        markers.add(pinMarker(point, fill, Domain.layerIcons[h.layer] ?? Icons.warning_amber_rounded, onTap: () => _showHazard(h), size: 34));
      }
    }
    if (_visible['safeZones'] == true) {
      for (final s in _safeZones) {
        final point = LatLng(dbl(s, 'latitude') ?? 0, dbl(s, 'longitude') ?? 0);
        markers.add(facilityMarker(point, Domain.safeZoneColor, Icons.shield, compact: _compactPins, onTap: () => _showSafeZone(s)));
      }
    }
    if (_visible['centers'] == true) {
      for (final c in _centers) {
        final point = LatLng(dbl(c, 'latitude') ?? 0, dbl(c, 'longitude') ?? 0);
        markers.add(facilityMarker(point, Domain.centerColor, Icons.home, compact: _compactPins, onTap: () => _showCenter(c)));
      }
    }
    if (_searchPoint != null) {
      markers.add(
        pinMarker(
          _searchPoint!,
          Ui.red,
          Icons.search,
          size: 42,
          onTap: () {
            showDetailSheet(context, title: 'Cavite search result', kicker: 'Selected location', body: _searchLabel, color: Ui.red, icon: Icons.search);
          },
        ),
      );
    }
    if (_userPoint != null) {
      markers.add(
        circleMarker(
          _userPoint!,
          Domain.centerColor,
          size: 20,
          onTap: () {
            showDetailSheet(
              context,
              title: 'Your approximate location',
              kicker: 'Device location',
              body: _userAccuracy == null ? 'Current device location' : 'Accuracy: ${_userAccuracy!.round()} m',
              color: Domain.centerColor,
              icon: Icons.my_location,
            );
          },
        ),
      );
    }
    return [_satellite ? satelliteTileLayer() : osmTileLayer(), const CaviteMaskLayer(), PolygonLayer(polygons: polygons), MarkerLayer(markers: markers), osmAttribution()];
  }

  Future<void> _openLayerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Visible map layers', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(_status, style: const TextStyle(color: Ui.slate500, fontSize: 12)),
                const SizedBox(height: 8),
                for (final entry in {
                  'flood': ('Flood areas', 'Areas prone to flooding', Domain.layerColors['flood']!),
                  'storm': ('Storm surge areas', 'Coastal areas reached by storm surge', Domain.layerColors['storm']!),
                  'earthquake': ('Earthquake areas', 'Fault / ground-shaking hazard areas', Domain.layerColors['earthquake']!),
                  'safeZones': ('Safe zones', 'Open ground for temporary gathering', Domain.safeZoneColor),
                  'centers': ('Evacuation centers', 'Buildings for longer stays', Domain.centerColor),
                }.entries)
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    secondary: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: entry.value.$3, borderRadius: BorderRadius.circular(10)),
                      child: Icon(Domain.layerIcons[entry.key], color: Colors.white, size: 19),
                    ),
                    title: Text(entry.value.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(entry.value.$2, style: const TextStyle(fontSize: 11.5)),
                    value: _visible[entry.key] ?? true,
                    onChanged: (v) {
                      setSheet(() => _visible[entry.key] = v);
                      setState(() {});
                    },
                  ),
                const Divider(),
                const Text('Hazard risk level', style: TextStyle(fontWeight: FontWeight.w800)),
                const Text('The fill colour of a hazard area shows its risk; the icon on the pin shows the hazard type.', style: TextStyle(fontSize: 11.5, color: Ui.slate500)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  children: [
                    for (final e in Domain.publicRiskColors.entries)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.square_rounded, color: e.value, size: 14),
                          const SizedBox(width: 4),
                          Text(Ui.titleCase(e.key), style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Location search results are provided by OpenStreetMap Nominatim.', style: TextStyle(fontSize: 11, color: Ui.slate500)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _searchLocation(),
                      decoration: fieldDecoration('Barangay, municipality, or address').copyWith(prefixIcon: const Icon(Icons.search, size: 20)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
                    onPressed: _searching ? null : _searchLocation,
                    child: Text(_searching ? '...' : 'Search'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _municipalityId,
                      isExpanded: true,
                      decoration: fieldDecoration('Municipality'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All municipalities')),
                        ..._municipalities.map(
                          (m) => DropdownMenuItem(
                            value: str(m, 'id'),
                            child: Text(str(m, 'municipality_name'), overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() => _municipalityId = v ?? '');
                        _load(fit: true);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _hazardFilter,
                      isExpanded: true,
                      decoration: fieldDecoration('Hazard type'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All hazard types')),
                        DropdownMenuItem(value: 'flood', child: Text('Flood zones')),
                        DropdownMenuItem(value: 'storm', child: Text('Storm surge')),
                        DropdownMenuItem(value: 'earthquake', child: Text('Earthquake areas')),
                      ],
                      onChanged: (v) => _applyHazardFilter(v ?? ''),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: AppConfig.mapCenter,
                  initialZoom: AppConfig.mapZoom,
                  minZoom: AppConfig.mapMinZoom,
                  maxZoom: 19,
                  cameraConstraint: Geo.caviteConstraint,
                  onMapEvent: (event) {
                    reapplyCameraConstraint(_map, event);
                    final compact = event.camera.zoom < kFacilityPinZoom;
                    if (compact != _compactPins) setState(() => _compactPins = compact);
                  },
                  onTap: (_, point) => _onTap(point),
                ),
                children: _layers(),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_loading) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                      if (_loading) const SizedBox(width: 6),
                      Text(_status, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Column(
                  children: [
                    _mapButton(Icons.layers_outlined, 'Layers', _openLayerSheet),
                    const SizedBox(height: 8),
                    _mapButton(_satellite ? Icons.map_outlined : Icons.satellite_alt_outlined, _satellite ? 'Street map' : 'Satellite', () => setState(() => _satellite = !_satellite)),
                    const SizedBox(height: 8),
                    _mapButton(Icons.fit_screen_outlined, 'Fit visible layers', _fitVisible),
                    const SizedBox(height: 8),
                    _mapButton(Icons.my_location, 'My location', _locate),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Public GIS viewer'), centerTitle: false),
      body: body,
    );
  }

  Widget _mapButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 20, color: Ui.slate900)),
        ),
      ),
    );
  }
}
