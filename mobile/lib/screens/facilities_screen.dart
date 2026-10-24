import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../core/api.dart';
import '../core/domain.dart';
import '../core/geo.dart';
import '../core/geocode.dart';
import '../core/location.dart';
import '../core/session.dart';
import '../core/ui.dart';

/// Normalised facility row (normalizeFacilityRows in dashboard.js).
Map<String, dynamic> _normalize(Map<String, dynamic> item, bool center) {
  return {
    ...item,
    'facility_type': center ? 'evacuation_center' : 'safe_zone',
    'facility_label': center ? 'Evacuation center' : 'Safe zone',
    'facility_name': center ? str(item, 'center_name') : str(item, 'safezone_name'),
    'facility_status': str(item, 'status', center ? 'available' : 'active'),
  };
}

/// Safety facilities: safe zones + evacuation centers, nearest lookup with
/// road routing, and manager CRUD with PSGC barangay/geocoding helpers.
class FacilitiesScreen extends StatefulWidget {
  const FacilitiesScreen({super.key});

  @override
  State<FacilitiesScreen> createState() => _FacilitiesScreenState();
}

class _FacilitiesScreenState extends State<FacilitiesScreen> {
  final _map = MapController();
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _municipalities = [];
  String _filter = 'all';
  String _search = '';
  String _routeMode = 'driving';
  int _shown = 40;
  bool _compactPins = true;
  bool _loading = true;
  bool _satellite = false;
  bool _busyNearest = false;
  CameraConstraint? _cameraConstraint;

  // Route drawing.
  List<LatLng> _routeLine = [];
  LatLng? _routeStart;
  Map<String, dynamic>? _routeDestination;
  Map<String, dynamic>? _nearestResult;
  Widget? _routeSummary;

  // Manager form (rendered inline under the map so map taps can set the point).
  bool _formOpen = false;
  Map<String, dynamic>? _formItem;
  int _formVersion = 0;
  final _formKey = GlobalKey<_FacilityFormState>();
  LatLng? _draft;

  Session get _session => Session.instance;
  bool get _manager => _session.isManager;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final rows = rowsOf(await Api.instance.get('/municipalities/options'));
      if (!mounted) return;
      setState(() => _municipalities = rows);
      if (_session.municipalityId != null && _session.isSubadmin) {
        final own = rows.where((m) => intOf(m, 'id') == _session.municipalityId).firstOrNull;
        final center = Geo.municipalityCenter(own);
        if (center != null) {
          // Move before switching constraint so the camera already satisfies it.
          _map.move(center, 13);
          setState(() => _cameraConstraint = CaviteLock(focus: Geo.municipalityBox(center)));
        }
      }
    } catch (_) {}
    await _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([Api.instance.get('/safe-zones'), Api.instance.get('/evacuation-centers')]);
      final rows = [...rowsOf(results[0]).map((r) => _normalize(r, false)), ...rowsOf(results[1]).map((r) => _normalize(r, true))]
        ..sort((a, b) => str(a, 'facility_name').compareTo(str(b, 'facility_name')));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _nearestResult = null;
      });
      final points = rows.map(_point).toList();
      if (points.isNotEmpty && _cameraConstraint == null && !_session.isResident) fitMap(_map, LatLngBounds.fromPoints(points));
      if (_session.isResident) fitMap(_map, Geo.caviteBounds, padding: 8, maxZoom: 12);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        Ui.toast(context, e.message, icon: 'error');
      }
    }
  }

  LatLng _point(Map<String, dynamic> row) => LatLng(dbl(row, 'latitude') ?? 0, dbl(row, 'longitude') ?? 0);

  List<Map<String, dynamic>> get _filtered {
    final scoped = _filter == 'all' ? _rows : _rows.where((r) => str(r, 'facility_type') == _filter).toList();
    final term = _search.trim().toLowerCase();
    if (term.isEmpty) return scoped;
    return scoped
        .where(
          (r) => [
            r['facility_name'],
            r['facility_label'],
            r['municipality_name'],
            r['address'],
            r['contact_person'],
            r['contact_number'],
            r['capacity'],
          ].any((v) => (v ?? '').toString().toLowerCase().contains(term)),
        )
        .toList();
  }

  // ----------------------------------------------------------------- routing

  Future<Map<String, dynamic>?> _nearestCombined(LatLng start) async {
    final results = await Future.wait([
      Api.instance.get('/safe-zones/nearest?latitude=${start.latitude}&longitude=${start.longitude}&limit=1').catchError((_) => <dynamic>[]),
      Api.instance.get('/evacuation-centers/nearest?latitude=${start.latitude}&longitude=${start.longitude}&limit=1').catchError((_) => <dynamic>[]),
    ]);
    final rows = [...rowsOf(results[0]).map((r) => _normalize(r, false)), ...rowsOf(results[1]).map((r) => _normalize(r, true))].where((r) => r['distance_km'] != null).toList()
      ..sort((a, b) => (dbl(a, 'distance_km') ?? 0).compareTo(dbl(b, 'distance_km') ?? 0));
    return rows.firstOrNull;
  }

  Future<void> _routeTo({Map<String, dynamic>? item, String? nearestType}) async {
    final label = Domain.routeModeLabels[_routeMode] ?? 'Route';
    setState(() {
      _busyNearest = true;
      _routeSummary = _summaryBox('Calculating ${label.toLowerCase()}...', 'Please allow location access when prompted.');
    });
    try {
      final start = await Location.current();
      Map<String, dynamic>? destination = item;
      if (destination == null) {
        if (nearestType == null) {
          destination = await _nearestCombined(start);
        } else {
          final center = nearestType == 'evacuation_center';
          final rows = rowsOf(await Api.instance.get('${center ? '/evacuation-centers' : '/safe-zones'}/nearest?latitude=${start.latitude}&longitude=${start.longitude}&limit=1'));
          destination = rows.isEmpty ? null : _normalize(rows.first, center);
        }
      }
      if (destination == null) throw Exception('No ${nearestType == null ? 'safety facility' : nearestType.replaceAll('_', ' ')} found near your location');
      final road = mapOf(
        await Api.instance.get(
          '/evacuation-routes/road?mode=$_routeMode&start_lat=${start.latitude}&start_lng=${start.longitude}&end_lat=${dbl(destination, 'latitude')}&end_lng=${dbl(destination, 'longitude')}',
        ),
      );
      final shapes = Geo.parse(road['geojson_data']);
      final line = shapes.lines.isNotEmpty ? shapes.lines.first : [start, _point(destination)];
      final distance = ((dbl(road, 'distance_m') ?? 0) / 1000).toStringAsFixed(1);
      final duration = (dbl(road, 'duration_s') ?? 0) > 0 ? '${((dbl(road, 'duration_s') ?? 0) / 60).ceil()} min' : 'Unavailable';
      final mode = str(road, 'mode', _routeMode);
      final metrics = Domain.routeMetricLabels[mode] ?? Domain.routeMetricLabels[_routeMode] ?? ['Distance', 'Estimated time'];
      final sourceText = str(road, 'source') == 'osrm_mode_estimate' ? 'Road distance with mode-based time estimate' : '${Domain.routeModeLabels[mode] ?? label} estimate using mode-specific speed';
      final name = str(destination, 'facility_name');
      if (!mounted) return;
      setState(() {
        _routeLine = line;
        _routeStart = start;
        _routeDestination = destination;
        _nearestResult = item == null ? destination : null;
        _routeSummary = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .95), borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Domain.routeModeLabels[mode] ?? label,
                style: const TextStyle(fontSize: 11, color: Ui.slate500, fontWeight: FontWeight.w700),
              ),
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${metrics[0]}: $distance km   ${metrics[1]}: $duration', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text(sourceText, style: const TextStyle(fontSize: 11, color: Ui.slate500)),
            ],
          ),
        );
      });
      fitMap(_map, LatLngBounds.fromPoints([...line, start, _point(destination)]), padding: 55, maxZoom: 16);
      Ui.toast(context, '$label ready: $name');
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        setState(() => _routeSummary = _summaryBox('Route unavailable', message));
        Ui.toast(context, message, icon: 'error');
      }
    } finally {
      if (mounted) setState(() => _busyNearest = false);
    }
  }

  Widget _summaryBox(String title, String body) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .95), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(body, style: const TextStyle(fontSize: 12, color: Ui.slate500)),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- actions

  Future<Map<String, dynamic>?> _fetch(Map<String, dynamic> row) async {
    final center = str(row, 'facility_type') == 'evacuation_center';
    try {
      final raw = mapOf(await Api.instance.get('${center ? '/evacuation-centers' : '/safe-zones'}/${row['id']}'));
      return _normalize(raw, center);
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
      return null;
    }
  }

  void _showSheet(Map<String, dynamic> s) {
    final center = str(s, 'facility_type') == 'evacuation_center';
    final status = center ? Domain.centerStatusMeta(str(s, 'status')) : null;
    showDetailSheet(
      context,
      title: str(s, 'facility_name'),
      kicker: center ? 'Evacuation center${status != null ? ' - ${status.$1}' : ''}' : 'Designated safe zone',
      color: center ? Domain.centerColor : Domain.safeZoneColor,
      icon: center ? Icons.home_work_outlined : Icons.shield_outlined,
      rows: [
        ('Address', str(s, 'address', 'No address provided')),
        ('Municipality', str(s, 'municipality_name', 'Municipality unavailable')),
        if (s['distance_km'] != null) ('Distance', '${s['distance_km']} km away'),
        ('Capacity', intOf(s, 'capacity') > 0 ? str(s, 'capacity') : 'Not specified'),
        if (str(s, 'contact_person').isNotEmpty || str(s, 'contact_number').isNotEmpty)
          ('Contact', '${str(s, 'contact_person', 'No contact person')}\n${str(s, 'contact_number', 'No number provided')}'),
        if (!center && str(s, 'description').isNotEmpty) ('Description', str(s, 'description')),
        if (status != null) ('Status note', status.$3),
        ('Coordinates', '${(dbl(s, 'latitude') ?? 0).toStringAsFixed(4)}, ${(dbl(s, 'longitude') ?? 0).toStringAsFixed(4)}'),
      ],
      actions: [
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            _routeTo(item: s);
          },
          icon: const Icon(Icons.route_outlined, size: 18),
          label: const Text('Route here'),
        ),
        if (_manager)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openForm(s);
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
      ],
    );
  }

  Future<void> _view(Map<String, dynamic> row) async {
    final item = await _fetch(row);
    if (item == null || !mounted) return;
    _map.move(_point(item), 15);
    _showSheet(item);
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final center = str(row, 'facility_type') == 'evacuation_center';
    if (!await Ui.confirm(context, 'Delete ${str(row, 'facility_name')}?', confirmText: 'Delete')) return;
    try {
      await Api.instance.delete('${center ? '/evacuation-centers' : '/safe-zones'}/${row['id']}');
      if (mounted) Ui.toast(context, center ? 'Evacuation center deleted' : 'Safe zone deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
    }
  }

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    Map<String, dynamic>? full = item;
    if (item != null) {
      full = await _fetch(item);
      if (full == null) return;
    }
    if (!mounted) return;
    setState(() {
      _formOpen = true;
      _formItem = full;
      _formVersion++;
      _draft = full == null ? null : _point(full);
    });
    if (full != null) _map.move(_point(full), 15);
  }

  void _closeForm({bool saved = false, bool editing = false}) {
    setState(() {
      _formOpen = false;
      _formItem = null;
      _draft = null;
    });
    if (saved) {
      Ui.toast(context, editing ? 'Facility updated' : 'Facility added');
      _load();
    }
  }

  void _onMapTap(LatLng point) {
    if (_manager && _formOpen) {
      setState(() => _draft = point);
      _formKey.currentState?.setPoint(point);
    }
  }

  // ------------------------------------------------------------------ layers

  List<Widget> _layers() {
    final markers = <Marker>[];
    final visible = _nearestResult != null ? [_nearestResult!] : _filtered;
    for (final s in visible) {
      final center = str(s, 'facility_type') == 'evacuation_center';
      final nearest = _nearestResult != null && s['distance_km'] != null;
      markers.add(
        nearest
            ? pinMarker(_point(s), Domain.nearestColor, Icons.star, onTap: () => _showSheet(s))
            : facilityMarker(
                _point(s),
                center ? Domain.centerColor : Domain.safeZoneColor,
                center ? Icons.home : Icons.shield,
                compact: _compactPins && _nearestResult == null,
                onTap: () => _showSheet(s),
              ),
      );
    }
    if (_routeStart != null) markers.add(circleMarker(_routeStart!, const Color(0xFF2563EB), size: 20));
    if (_routeDestination != null && !visible.contains(_routeDestination)) {
      final center = str(_routeDestination, 'facility_type') == 'evacuation_center';
      markers.add(pinMarker(_point(_routeDestination!), center ? Domain.centerColor : Domain.safeZoneColor, center ? Icons.home : Icons.shield, onTap: () => _showSheet(_routeDestination!)));
    }
    if (_draft != null) markers.add(pinMarker(_draft!, Domain.draftColor, Icons.add, size: 42));
    final routeColor = str(_routeDestination, 'facility_type') == 'evacuation_center' ? Domain.centerColor : Domain.safeZoneColor;
    return [
      _satellite ? satelliteTileLayer() : osmTileLayer(),
      const CaviteMaskLayer(),
      if (_routeLine.isNotEmpty)
        PolylineLayer(
          polylines: [
            Polyline(points: _routeLine, color: Colors.white, strokeWidth: 9),
            Polyline(points: _routeLine, color: routeColor, strokeWidth: 5),
          ],
        ),
      MarkerLayer(markers: markers),
      osmAttribution(),
    ];
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final counts = {
      'all': _rows.length,
      'safe_zone': _rows.where((r) => str(r, 'facility_type') == 'safe_zone').length,
      'evacuation_center': _rows.where((r) => str(r, 'facility_type') == 'evacuation_center').length,
    };
    final mapHeight = MediaQuery.of(context).size.height * .42;
    return Column(
      children: [
        SizedBox(
          height: mapHeight,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(bounds: Geo.caviteBounds, padding: const EdgeInsets.all(8)),
                  minZoom: AppConfig.mapMinZoom,
                  maxZoom: 19,
                  cameraConstraint: _cameraConstraint ?? Geo.caviteConstraint,
                  onMapEvent: (event) {
                    reapplyCameraConstraint(_map, event);
                    final compact = event.camera.zoom < kFacilityPinZoom;
                    if (compact != _compactPins) setState(() => _compactPins = compact);
                  },
                  onTap: (_, point) => _onMapTap(point),
                ),
                children: _layers(),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: Row(
                  children: [
                    for (final mode in const [('driving', Icons.directions_car, 'Car'), ('motorcycle', Icons.two_wheeler, 'Motorcycle'), ('walking', Icons.directions_walk, 'Walk')])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Material(
                          color: _routeMode == mode.$1 ? Ui.indigo : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          elevation: 2,
                          child: InkWell(
                            onTap: () => setState(() => _routeMode = mode.$1),
                            borderRadius: BorderRadius.circular(10),
                            child: Tooltip(
                              message: '${mode.$3} route',
                              child: SizedBox(width: 38, height: 38, child: Icon(mode.$2, size: 20, color: _routeMode == mode.$1 ? Colors.white : Ui.slate900)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                right: 10,
                top: 10,
                child: Column(
                  children: [
                    _mapButton(_satellite ? Icons.map_outlined : Icons.satellite_alt_outlined, () => setState(() => _satellite = !_satellite)),
                    const SizedBox(height: 6),
                    _mapButton(Icons.fit_screen_outlined, () {
                      final points = rows.map(_point).toList();
                      if (points.isNotEmpty) fitMap(_map, LatLngBounds.fromPoints(points));
                    }),
                    if (_routeLine.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _mapButton(
                        Icons.close,
                        () => setState(() {
                          _routeLine = [];
                          _routeStart = null;
                          _routeDestination = null;
                          _routeSummary = null;
                          _nearestResult = null;
                        }),
                      ),
                    ],
                  ],
                ),
              ),
              if (_routeSummary != null) Positioned(left: 10, right: 10, bottom: 10, child: _routeSummary!),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ModuleHeader(
                  eyebrow: 'Safety facilities',
                  title: 'Safe zones & evacuation centers',
                  subtitle: 'Green shield pins are safe zones, blue house pins are evacuation centers. Use your location to route to the nearest facility.',
                  icon: Icons.shield_outlined,
                  actions: [
                    BannerButton(
                      label: 'Nearest safe zone',
                      icon: Icons.shield_outlined,
                      onPressed: _busyNearest ? null : () => _routeTo(nearestType: 'safe_zone'),
                    ),
                    BannerButton(
                      label: 'Nearest center',
                      icon: Icons.home_work_outlined,
                      onPressed: _busyNearest ? null : () => _routeTo(nearestType: 'evacuation_center'),
                    ),
                    BannerButton(label: 'Route to nearest', icon: Icons.near_me_outlined, primary: false, onPressed: _busyNearest ? null : () => _routeTo()),
                    if (_manager) BannerButton(label: 'Add facility', icon: Icons.add, primary: false, onPressed: () => _openForm()),
                    if (_manager)
                      BannerButton(
                        label: 'Export CSV',
                        icon: Icons.download_outlined,
                        primary: false,
                        onPressed: rows.isEmpty
                            ? null
                            : () => Ui.exportCsv(
                                context,
                                'safety-facilities',
                                ['Facility', 'Type', 'Municipality', 'Address', 'Contact person', 'Contact number', 'Capacity', 'Latitude', 'Longitude'],
                                rows
                                    .map(
                                      (r) => [
                                        r['facility_name'],
                                        r['facility_label'],
                                        r['municipality_name'],
                                        r['address'],
                                        r['contact_person'],
                                        r['contact_number'],
                                        r['capacity'],
                                        r['latitude'],
                                        r['longitude'],
                                      ],
                                    )
                                    .toList(),
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _explainers(counts),
                const SizedBox(height: 10),
                _legend(),
                const SizedBox(height: 12),
                if (_formOpen && _manager) ...[
                  _FacilityForm(
                    key: _formKey,
                    version: _formVersion,
                    item: _formItem,
                    municipalities: _municipalities,
                    mapController: _map,
                    onDraft: (point) => setState(() => _draft = point),
                    onClose: (saved) => _closeForm(saved: saved, editing: _formItem != null),
                  ),
                  const SizedBox(height: 12),
                ],
                SegmentedChips(
                  value: _filter,
                  options: [('all', 'All', counts['all']), ('safe_zone', 'Safe zones', counts['safe_zone']), ('evacuation_center', 'Centers', counts['evacuation_center'])],
                  onChanged: (v) => setState(() {
                    _filter = v;
                    _shown = 40;
                    _nearestResult = null;
                  }),
                ),
                const SizedBox(height: 10),
                SearchField(
                  hint: 'Search facility, municipality, address',
                  onChanged: (v) => setState(() {
                    _search = v;
                    _shown = 40;
                  }),
                ),
                ListHeading('Directory', count: rows.length),
                if (_loading)
                  const Center(
                    child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
                  ),
                if (!_loading && rows.isEmpty)
                  EmptyNote(
                    'No ${_filter == 'safe_zone'
                        ? 'safe zones'
                        : _filter == 'evacuation_center'
                        ? 'evacuation centers'
                        : 'safety facilities'} found.',
                  ),
                ...rows.take(_shown).map((s) {
                  final center = str(s, 'facility_type') == 'evacuation_center';
                  final status = Domain.centerStatusMeta(str(s, 'status'));
                  return RecordCard(
                    title: str(s, 'facility_name'),
                    subtitle: str(s, 'address', 'No address provided'),
                    icon: center ? Icons.home_work_outlined : Icons.shield_outlined,
                    accent: center ? kGradBlue : kGradGreen,
                    onTap: () => _view(s),
                    body: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          _facilityStat('Capacity', intOf(s, 'capacity') > 0 ? str(s, 'capacity') : 'Not specified', Ui.violet),
                          const SizedBox(width: 8),
                          _facilityStat('Contact', str(s, 'contact_person', str(s, 'contact_number', 'Not provided')), Ui.sky),
                          if (s['distance_km'] != null) ...[const SizedBox(width: 8), _facilityStat('Distance', '${s['distance_km']} km', Ui.emerald)],
                        ],
                      ),
                    ),
                    pills: [
                      Pill(str(s, 'facility_label'), color: center ? Domain.centerColor : Domain.safeZoneColor),
                      Pill(str(s, 'municipality_name', '-'), color: Ui.slate500),
                      if (center) Pill(status.$1, color: status.$2),
                    ],
                    actions: [
                      ActionIconButton(icon: Icons.visibility_outlined, tooltip: 'View facility', color: Ui.sky, onPressed: () => _view(s)),
                      ActionIconButton(
                        icon: Icons.route_outlined,
                        tooltip: 'Route to facility',
                        color: Ui.emerald,
                        onPressed: () => _routeTo(item: s),
                      ),
                      if (_manager) ...[
                        ActionIconButton(icon: Icons.edit_outlined, tooltip: 'Edit facility', color: Ui.amber, onPressed: () => _openForm(s)),
                        ActionIconButton(icon: Icons.delete_outline, tooltip: 'Delete facility', color: Ui.red, onPressed: () => _delete(s)),
                      ],
                    ],
                  );
                }),
                if (rows.length > _shown)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: OutlinedButton.icon(onPressed: () => setState(() => _shown += 60), icon: const Icon(Icons.expand_more), label: Text('Show more (${rows.length - _shown} remaining)')),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _facilityStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Ui.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: Ui.slate400),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend() {
    final items = <(String, Color, IconData)>[
      ('Safe zone', Domain.safeZoneColor, Icons.shield),
      ('Evacuation center', Domain.centerColor, Icons.home),
      ('Nearest result', Domain.nearestColor, Icons.star),
      ('Your location', const Color(0xFF2563EB), Icons.my_location),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final e in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: e.$2,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3)],
                ),
                child: Icon(e.$3, size: 12, color: Colors.white),
              ),
              const SizedBox(width: 5),
              Text(e.$1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
      ],
    );
  }

  /// Mirrors the web "Safety facilities" explainer cards.
  Widget _explainers(Map<String, int> counts) {
    Widget card(Color color, IconData icon, String title, String body, int count) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: color, width: 4),
          top: const BorderSide(color: Ui.line),
          right: const BorderSide(color: Ui.line),
          bottom: const BorderSide(color: Ui.line),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                    Text(
                      '$count',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 12, color: Ui.slate500, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      children: [
        card(
          Domain.safeZoneColor,
          Icons.shield,
          'Safe zone',
          'Open, hazard-free ground (plaza, school field, covered court, high ground) where residents gather temporarily during and right after a disaster.',
          counts['safe_zone'] ?? 0,
        ),
        const SizedBox(height: 8),
        card(
          Domain.centerColor,
          Icons.home,
          'Evacuation center',
          'A building for longer stays once evacuation is ordered: roof, toilets, sleeping space and relief goods (schools, gyms, barangay halls).',
          counts['evacuation_center'] ?? 0,
        ),
      ],
    );
  }

  Widget _mapButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 19, color: Ui.slate900)),
      ),
    );
  }
}

/// Add/edit facility form (safeZoneForm in admin/views/safezones.html).
/// Rendered inline below the map so a map tap can set the coordinates.
class _FacilityForm extends StatefulWidget {
  const _FacilityForm({super.key, required this.version, this.item, required this.municipalities, required this.mapController, required this.onDraft, required this.onClose});

  /// Bumped by the parent whenever the form should reset to [item].
  final int version;
  final Map<String, dynamic>? item;
  final List<Map<String, dynamic>> municipalities;
  final MapController mapController;
  final ValueChanged<LatLng?> onDraft;
  final ValueChanged<bool> onClose;

  @override
  State<_FacilityForm> createState() => _FacilityFormState();
}

class _FacilityFormState extends State<_FacilityForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _exactAddress = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _capacity = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactNumber = TextEditingController();
  final _description = TextEditingController();
  String _facilityType = 'safe_zone';
  String _centerStatus = 'available';
  String _municipalityId = '';
  List<Map<String, dynamic>> _barangays = [];
  String _barangay = '';
  bool _barangaysLoading = false;
  bool _geocoding = false;
  bool _busy = false;
  String? _error;
  Timer? _addressTimer;

  Session get _session => Session.instance;

  String get _cityName {
    if (_session.isSubadmin && _session.municipalityName.isNotEmpty) return _session.municipalityName;
    final option = widget.municipalities.where((m) => str(m, 'id') == _municipalityId).firstOrNull;
    return str(option, 'municipality_name', str(widget.item, 'municipality_name'));
  }

  @override
  void initState() {
    super.initState();
    _loadItem();
  }

  @override
  void didUpdateWidget(covariant _FacilityForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.version != widget.version) _loadItem();
  }

  @override
  void dispose() {
    _addressTimer?.cancel();
    for (final c in [_name, _exactAddress, _latitude, _longitude, _capacity, _contactPerson, _contactNumber, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadItem() {
    final item = widget.item;
    setState(() {
      _facilityType = str(item, 'facility_type', 'safe_zone');
      _name.text = str(item, 'facility_name');
      _exactAddress.text = str(item, 'address');
      _latitude.text = str(item, 'latitude');
      _longitude.text = str(item, 'longitude');
      _capacity.text = str(item, 'capacity');
      _contactPerson.text = str(item, 'contact_person');
      _contactNumber.text = str(item, 'contact_number');
      _description.text = str(item, 'description');
      _centerStatus = str(item, 'status', 'available');
      _municipalityId = _session.isSubadmin ? (_session.municipalityId?.toString() ?? '') : str(item, 'municipality_id');
      _barangays = [];
      _barangay = '';
      _error = null;
      _busy = false;
    });
    if (_municipalityId.isNotEmpty) _loadBarangays(matchFrom: str(item, 'address'));
  }

  /// Called by the parent when the manager taps the map.
  void setPoint(LatLng point) {
    setState(() {
      _latitude.text = point.latitude.toStringAsFixed(7);
      _longitude.text = point.longitude.toStringAsFixed(7);
    });
  }

  Future<List<Map<String, dynamic>>> _loadBarangays({String matchFrom = ''}) async {
    if (_cityName.isEmpty) return [];
    setState(() => _barangaysLoading = true);
    try {
      final rows = await Geocode.barangays(_cityName);
      if (!mounted) return rows;
      final match = matchFrom.isEmpty ? null : Geocode.matchBarangay(rows, matchFrom);
      setState(() {
        _barangays = rows;
        _barangaysLoading = false;
        if (match != null) _barangay = match['name'].toString();
        if (_barangay.isNotEmpty && !rows.any((r) => r['name'] == _barangay)) _barangay = '';
      });
      return rows;
    } catch (e) {
      if (mounted) {
        setState(() {
          _barangays = [];
          _barangaysLoading = false;
        });
        Ui.toast(context, e.toString().replaceFirst('Exception: ', ''), icon: 'error');
      }
      return [];
    }
  }

  String _composeAddress() {
    final parts = [_exactAddress.text.trim(), if (_barangay.isNotEmpty) 'Barangay $_barangay', _cityName, 'Cavite', 'Philippines'].where((p) => p.isNotEmpty).toList();
    return parts.join(', ');
  }

  List<String> _addressQueries() {
    final exact = _exactAddress.text.trim();
    final brgy = _barangay.isNotEmpty ? 'Barangay $_barangay' : '';
    final city = _cityName;
    final variants = [
      [exact, brgy, city, 'Cavite', 'Philippines'],
      [exact, city, 'Cavite', 'Philippines'],
      [brgy, city, 'Cavite', 'Philippines'],
      [city, 'Cavite', 'Philippines'],
    ].map((parts) => parts.where((p) => p.isNotEmpty).join(', ')).where((q) => q.isNotEmpty).toList();
    return variants.toSet().toList();
  }

  void _scheduleAddressLookup() {
    _addressTimer?.cancel();
    _addressTimer = Timer(const Duration(milliseconds: 600), () => _inferAddressFields(false));
  }

  /// inferSafeZoneAddressFields: detect city/barangay from the typed address.
  Future<void> _inferAddressFields(bool showToast) async {
    final exact = _exactAddress.text.trim();
    if (exact.isEmpty) return;
    if (_session.isSubadmin) {
      if (_barangays.isNotEmpty) {
        final match = Geocode.matchBarangay(_barangays, exact);
        if (match != null && mounted) setState(() => _barangay = match['name'].toString());
      }
      return;
    }
    try {
      final typedCity = Geocode.matchMunicipality(widget.municipalities, exact);
      Map<String, dynamic>? feature;
      if (exact.length > 2) feature = await Geocode.photonFeature('$exact, Cavite, Philippines');
      final props = mapOf(feature?['properties']);
      final searchText = [
        exact,
        props['name'],
        props['street'],
        props['locality'],
        props['district'],
        props['city'],
        props['county'],
        props['state'],
      ].where((v) => v != null && v.toString().isNotEmpty).join(' ');
      final cityOption = typedCity ?? Geocode.matchMunicipality(widget.municipalities, searchText);
      var rows = <Map<String, dynamic>>[];
      if (cityOption != null && str(cityOption, 'id') != _municipalityId) {
        if (!mounted) return;
        setState(() {
          _municipalityId = str(cityOption, 'id');
          _latitude.clear();
          _longitude.clear();
        });
        rows = await _loadBarangays();
      } else if (_municipalityId.isNotEmpty) {
        rows = _barangays.isNotEmpty ? _barangays : await _loadBarangays();
      }
      if (rows.isNotEmpty) {
        final match = Geocode.matchBarangay(rows, searchText);
        if (match != null && mounted) setState(() => _barangay = match['name'].toString());
      }
      if (_municipalityId.isNotEmpty && _barangay.isNotEmpty) {
        await _geocode(false);
      } else if (showToast && mounted) {
        Ui.toast(context, 'City detected. Select barangay if it was not found automatically.', icon: 'info');
      }
    } catch (e) {
      if (showToast && mounted) Ui.toast(context, e.toString().replaceFirst('Exception: ', ''), icon: 'error');
    }
  }

  Future<void> _geocode(bool showToast) async {
    if (_barangay.isEmpty || _municipalityId.isEmpty) {
      if (showToast) Ui.toast(context, 'Select the municipality and barangay first.', icon: 'warning');
      return;
    }
    setState(() => _geocoding = true);
    try {
      LatLng? point;
      String matched = '';
      for (final query in _addressQueries()) {
        point = await Geocode.photonSearch(query) ?? await Geocode.nominatimSearch(query);
        if (point != null) {
          matched = query;
          break;
        }
      }
      if (point == null) throw Exception('Address was not found. Try a more specific landmark or tap the map to set the point.');
      if (!mounted) return;
      setPoint(point);
      widget.onDraft(point);
      widget.mapController.move(point, 16);
      if (showToast) Ui.toast(context, matched == _composeAddress() ? 'Latitude and longitude detected' : 'Nearest available location detected. Check the map pin.');
    } catch (e) {
      if (showToast && mounted) Ui.toast(context, e.toString().replaceFirst('Exception: ', ''), icon: 'error');
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final center = _facilityType == 'evacuation_center';
    final base = {
      'municipality_id': _session.isSubadmin ? (_session.municipalityId?.toString() ?? '') : _municipalityId,
      'address': _composeAddress(),
      'latitude': _latitude.text.trim(),
      'longitude': _longitude.text.trim(),
      'capacity': _capacity.text.trim(),
      'contact_person': _contactPerson.text.trim(),
      'contact_number': _contactNumber.text.trim(),
    };
    try {
      final id = widget.item?['id'];
      if (center) {
        final payload = {...base, 'center_name': _name.text.trim(), 'status': _centerStatus};
        if (id != null) {
          await Api.instance.put('/evacuation-centers/$id', payload);
        } else {
          await Api.instance.post('/evacuation-centers', payload);
        }
      } else {
        final payload = {...base, 'safezone_name': _name.text.trim(), 'description': _description.text.trim()};
        if (id != null) {
          await Api.instance.put('/safe-zones/$id', payload);
        } else {
          await Api.instance.post('/safe-zones', payload);
        }
      }
      if (mounted) widget.onClose(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.errors.isEmpty ? e.message : '${e.message}\n${e.errors.values.join('\n')}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    final center = _facilityType == 'evacuation_center';
    final municipalityItems = [
      const DropdownMenuItem(value: '', child: Text('Select city / municipality')),
      ...widget.municipalities.map(
        (m) => DropdownMenuItem(
          value: str(m, 'id'),
          child: Text(str(m, 'municipality_name'), overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
    if (_municipalityId.isNotEmpty && !municipalityItems.any((i) => i.value == _municipalityId)) {
      municipalityItems.add(DropdownMenuItem(value: _municipalityId, child: Text(_cityName.isEmpty ? 'Municipality #$_municipalityId' : _cityName)));
    }
    return SectionCard(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FACILITY RECORD',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Ui.slate500, letterSpacing: .6),
                      ),
                      Text(
                        editing ? (center ? 'Edit evacuation center' : 'Edit safe zone') : (center ? 'Add evacuation center' : 'Add safe zone'),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                IconButton(onPressed: () => widget.onClose(false), icon: const Icon(Icons.close), tooltip: 'Close form'),
              ],
            ),
            const Text('Fill the location fields, then verify the detected map point. Tap the map to set the point manually.', style: TextStyle(fontSize: 12.5, color: Ui.slate500)),
            const FieldLabel('Facility type'),
            DropdownButtonFormField<String>(
              key: ValueKey('facility-type-${widget.version}'),
              initialValue: _facilityType,
              decoration: fieldDecoration('Facility type'),
              items: const [
                DropdownMenuItem(value: 'safe_zone', child: Text('Safe zone')),
                DropdownMenuItem(value: 'evacuation_center', child: Text('Evacuation center')),
              ],
              onChanged: editing ? null : (v) => setState(() => _facilityType = v ?? 'safe_zone'),
            ),
            const FieldLabel('Facility name'),
            TextFormField(controller: _name, decoration: fieldDecoration('e.g. Barangay Hall Covered Court'), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the facility name' : null),
            const FieldLabel('Municipality / city'),
            if (_session.isSubadmin)
              TextFormField(
                key: ValueKey('facility-city-${widget.version}'),
                initialValue: _session.municipalityName.isEmpty ? 'Assigned municipality' : _session.municipalityName,
                enabled: false,
                decoration: fieldDecoration(''),
              )
            else
              DropdownButtonFormField<String>(
                key: ValueKey('facility-municipality-${widget.version}-$_municipalityId'),
                initialValue: _municipalityId,
                isExpanded: true,
                decoration: fieldDecoration('Select city / municipality'),
                items: municipalityItems,
                validator: (v) => (v == null || v.isEmpty) ? 'Select the municipality' : null,
                onChanged: (v) {
                  setState(() {
                    _municipalityId = v ?? '';
                    _barangay = '';
                    _latitude.clear();
                    _longitude.clear();
                  });
                  _loadBarangays();
                },
              ),
            const FieldLabel('Barangay'),
            DropdownButtonFormField<String>(
              key: ValueKey('barangay-${widget.version}-$_municipalityId-${_barangays.length}-$_barangay'),
              initialValue: _barangay,
              isExpanded: true,
              decoration: fieldDecoration(_barangaysLoading ? 'Loading barangays...' : 'Select barangay'),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(
                    _barangaysLoading
                        ? 'Loading barangays...'
                        : (_municipalityId.isEmpty
                              ? 'Select the municipality first'
                              : _barangays.isEmpty
                              ? 'Barangays unavailable'
                              : 'Select barangay'),
                  ),
                ),
                ..._barangays.map(
                  (b) => DropdownMenuItem(
                    value: b['name'].toString(),
                    child: Text(b['name'].toString(), overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: _barangays.isEmpty
                  ? null
                  : (v) {
                      setState(() => _barangay = v ?? '');
                      if (_barangay.isNotEmpty) _geocode(false);
                    },
            ),
            const FieldLabel('Exact address'),
            TextFormField(
              controller: _exactAddress,
              maxLength: 160,
              decoration: fieldDecoration('Street, building, school, court, or landmark'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the exact address' : null,
              onChanged: (_) => _scheduleAddressLookup(),
            ),
            OutlinedButton.icon(
              onPressed: _geocoding
                  ? null
                  : () async {
                      await _inferAddressFields(false);
                      await _geocode(true);
                    },
              icon: const Icon(Icons.travel_explore_outlined, size: 18),
              label: Text(_geocoding ? 'Detecting...' : 'Detect latitude and longitude'),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('Latitude'),
                      TextFormField(
                        controller: _latitude,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: fieldDecoration('Auto detected'),
                        validator: (v) => double.tryParse(v ?? '') == null ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('Longitude'),
                      TextFormField(
                        controller: _longitude,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: fieldDecoration('Auto detected'),
                        validator: (v) => double.tryParse(v ?? '') == null ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const FieldLabel('Capacity'),
            TextFormField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: fieldDecoration('Number of people'),
              validator: (v) => (int.tryParse(v ?? '') ?? -1) < 0 ? 'Enter the capacity' : null,
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('Contact person'),
                      TextFormField(controller: _contactPerson, maxLength: 120, decoration: fieldDecoration('Focal person or caretaker')),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('Contact number'),
                      TextFormField(controller: _contactNumber, maxLength: 30, keyboardType: TextInputType.phone, decoration: fieldDecoration('Mobile or telephone')),
                    ],
                  ),
                ),
              ],
            ),
            if (center) ...[
              const FieldLabel('Status'),
              DropdownButtonFormField<String>(
                key: ValueKey('center-status-${widget.version}'),
                initialValue: Domain.centerStatuses.containsKey(_centerStatus) ? _centerStatus : 'available',
                decoration: fieldDecoration('Status'),
                items: Domain.centerStatuses.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setState(() => _centerStatus = v ?? 'available'),
              ),
            ] else ...[
              const FieldLabel('Description'),
              TextFormField(controller: _description, maxLines: 3, maxLength: 5000, decoration: fieldDecoration('Notes, access instructions, or facility details')),
            ],
            ErrorBanner(_error),
            const SizedBox(height: 14),
            PrimaryButton(label: _busy ? 'Saving...' : 'Save facility', icon: Icons.save_outlined, onPressed: _busy ? null : _submit),
          ],
        ),
      ),
    );
  }
}
