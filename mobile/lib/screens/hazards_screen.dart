import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../core/api.dart';
import '../core/domain.dart';
import '../core/geo.dart';
import '../core/session.dart';
import '../core/ui.dart';

class _HazardRow {
  _HazardRow(this.row) : shapes = Geo.parse(row['geojson_data']);

  final Map<String, dynamic> row;
  final GeoShapes shapes;

  int get id => intOf(row, 'id');
}

/// Hazard mapping (manager only): draw rectangle/polygon boundaries, edit
/// vertices, upload GeoJSON, look up covered locations and manage records.
class HazardsScreen extends StatefulWidget {
  const HazardsScreen({super.key});

  @override
  State<HazardsScreen> createState() => _HazardsScreenState();
}

class _HazardsScreenState extends State<HazardsScreen> {
  final _map = MapController();
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _typeOther = TextEditingController();
  final _description = TextEditingController();
  final _geojsonText = TextEditingController();

  List<_HazardRow> _rows = [];
  List<Map<String, dynamic>> _municipalities = [];
  String _typeFilter = '';
  String _riskFilter = '';
  bool _loading = true;
  bool _satellite = false;
  CameraConstraint? _cameraConstraint;

  // Drawing state.
  String? _drawMode;
  final List<LatLng> _drawPoints = [];
  String _drawStatus = 'Choose Rectangle or Polygon to map a hazard area.';
  String _drawTone = 'info';

  // Form state.
  bool _formOpen = false;
  int? _editingId;
  Map<String, dynamic>? _originalGeojson;
  Map<String, dynamic>? _geojson;
  String _type = 'flood_zone';
  String _risk = 'low';
  String _municipalityId = '';
  String? _formError;
  bool _saving = false;
  int? _hiddenId;

  // Vertex editing.
  List<LatLng> _handles = [];
  int? _selectedHandle;

  // Coverage lookup.
  Map<String, dynamic>? _coverage;
  bool _coverageLoading = false;
  String? _coverageError;

  Session get _session => Session.instance;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _name.dispose();
    _typeOther.dispose();
    _description.dispose();
    _geojsonText.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final rows = rowsOf(await Api.instance.get('/municipalities/options'));
      if (!mounted) return;
      setState(() => _municipalities = rows);
      if (_session.isSubadmin) {
        _municipalityId = _session.municipalityId?.toString() ?? '';
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

  String get _filterQuery {
    final params = <String, String>{};
    if (_session.isSubadmin && _session.municipalityId != null) params['municipality_id'] = '${_session.municipalityId}';
    if (_typeFilter.isNotEmpty) params['hazard_type'] = _typeFilter;
    if (_riskFilter.isNotEmpty) params['risk_level'] = _riskFilter;
    if (params.isEmpty) return '';
    return '?${params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
  }

  Future<void> _load() async {
    try {
      final rows = rowsOf(await Api.instance.get('/hazards$_filterQuery'));
      if (mounted) {
        setState(() {
          _rows = rows.map(_HazardRow.new).toList();
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        Ui.toast(context, e.message, icon: 'error');
      }
    }
  }

  void _setStatus(String message, [String tone = 'info']) {
    setState(() {
      _drawStatus = message;
      _drawTone = tone;
    });
  }

  // ---------------------------------------------------------------- drawing

  void _startDrawing(String mode) {
    _stopDrawing(clear: false);
    if (!_formOpen) _openForm();
    setState(() {
      _drawMode = mode;
      _selectedHandle = null;
    });
    _setStatus(mode == 'rectangle' ? 'Tap the first corner, then tap the opposite corner.' : 'Tap each boundary point, then select Finish.', 'active');
  }

  void _stopDrawing({required bool clear}) {
    setState(() {
      _drawMode = null;
      _drawPoints.clear();
      if (clear) {
        _geojson = null;
        _geojsonText.clear();
        _handles = [];
        _selectedHandle = null;
        _coverage = null;
        _coverageError = null;
      }
    });
    if (clear) _setStatus('Choose Rectangle or Polygon to map a hazard area.');
  }

  void _redraw() {
    setState(() {
      _handles = [];
      _selectedHandle = null;
      _drawMode = null;
      _drawPoints.clear();
      _geojson = null;
      _geojsonText.clear();
      _hiddenId = _editingId;
      _coverage = null;
      _coverageError = null;
    });
    _setStatus('Existing boundary is temporarily hidden. Draw a new boundary, or save details to keep the original boundary.', 'active');
  }

  void _finishPolygon() {
    if (_drawMode != 'polygon') return;
    if (_drawPoints.length < 3) {
      _setStatus('Add at least three boundary points before finishing.', 'error');
      return;
    }
    _completeDrawing(Geo.polygonFromPoints(_drawPoints));
  }

  void _undoPoint() {
    if (_drawMode == 'polygon' && _drawPoints.isNotEmpty) {
      setState(() => _drawPoints.removeLast());
      _setStatus('${_drawPoints.length} boundary point${_drawPoints.length == 1 ? '' : 's'} added.', 'active');
    }
  }

  void _completeDrawing(Map<String, dynamic> geojson) {
    if (!_formOpen) _openForm();
    setState(() {
      _geojson = geojson;
      _geojsonText.text = const JsonEncoder.withIndent('  ').convert(geojson);
      _drawMode = null;
      _drawPoints.clear();
      _coverage = null;
      _coverageError = null;
    });
    _showEditHandles(geojson);
    final ring = Geo.editableRing(geojson);
    final hectares = ring == null ? 0 : Geo.areaSquareMeters(ring) / 10000;
    _setStatus('Area captured - ${hectares.toStringAsFixed(2)} hectares', 'success');
    _fitGeojson(geojson);
    _lookupCoverage(geojson);
  }

  void _onMapTap(LatLng point) {
    if (_selectedHandle != null && _handles.isNotEmpty) {
      _moveHandle(_selectedHandle!, point);
      return;
    }
    if (_drawMode == 'rectangle') {
      if (_drawPoints.isEmpty) {
        setState(() => _drawPoints.add(point));
        _setStatus('First corner set. Tap the opposite corner.', 'active');
      } else {
        _completeDrawing(Geo.rectangleFromCorners(_drawPoints.first, point));
      }
      return;
    }
    if (_drawMode == 'polygon') {
      setState(() => _drawPoints.add(point));
      _setStatus('${_drawPoints.length} boundary point${_drawPoints.length == 1 ? '' : 's'} added. ${_drawPoints.length >= 3 ? 'Select Finish when ready.' : ''}', 'active');
      return;
    }
    // Hit test saved hazards.
    _HazardRow? hit;
    double? hitArea;
    for (final h in _rows) {
      if (_hiddenId != null && h.id == _hiddenId) continue;
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
    if (hit != null) _showHazardSheet(hit.row);
  }

  // ---------------------------------------------------------- vertex editing

  void _showEditHandles(Map<String, dynamic> geojson) {
    final ring = Geo.editableRing(geojson);
    if (ring == null || ring.length < 4) {
      setState(() => _handles = []);
      return;
    }
    setState(() {
      _handles = ring.sublist(0, ring.length - 1).map((p) => LatLng(p[1], p[0])).toList();
      _selectedHandle = null;
    });
  }

  void _moveHandle(int index, LatLng point) {
    setState(() {
      _handles[index] = point;
      _selectedHandle = null;
    });
    final ring = _handles.map((p) => [Geo.round7(p.longitude), Geo.round7(p.latitude)]).toList();
    ring.add([...ring.first]);
    final next = Geo.geojsonWithRing(
      _geojson ??
          {
            'type': 'Polygon',
            'coordinates': [ring],
          },
      ring,
    );
    setState(() {
      _geojson = next;
      _geojsonText.text = const JsonEncoder.withIndent('  ').convert(next);
    });
    _setStatus('Boundary updated. Save the hazard to keep these map changes.', 'success');
    _lookupCoverage(next);
  }

  // ------------------------------------------------------------ coverage API

  Future<void> _lookupCoverage(Map<String, dynamic> geojson) async {
    setState(() {
      _coverageLoading = true;
      _coverageError = null;
    });
    try {
      final result = mapOf(await Api.instance.post('/gis/covered-locations', {'geojson_data': geojson}));
      if (!mounted) return;
      final municipalities = rowsOf(result['municipalities']);
      setState(() {
        _coverage = result;
        _coverageLoading = false;
        if (_session.isAdmin && municipalities.isNotEmpty) _municipalityId = str(municipalities.first, 'id');
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _coverageLoading = false;
          _coverageError = e.message;
        });
      }
    }
  }

  // ------------------------------------------------------------------- form

  void _openForm([Map<String, dynamic>? item]) {
    setState(() {
      _formOpen = true;
      _formError = null;
      _editingId = item == null ? null : intOf(item, 'id');
      _originalGeojson = item == null ? null : Geo.deepCopy(item['geojson_data']) as Map<String, dynamic>?;
      _hiddenId = null;
      _name.text = str(item, 'hazard_name');
      final type = str(item, 'hazard_type', 'flood_zone');
      if (Domain.standardHazardTypes.contains(type)) {
        _type = type;
        _typeOther.clear();
      } else {
        _type = 'other';
        _typeOther.text = Domain.hazardTypeLabel(type);
      }
      _municipalityId = _session.isSubadmin ? (_session.municipalityId?.toString() ?? '') : str(item, 'municipality_id');
      _risk = str(item, 'risk_level', 'low');
      _description.text = str(item, 'description');
      _geojson = item == null ? null : Geo.deepCopy(item['geojson_data']) as Map<String, dynamic>?;
      _geojsonText.text = _geojson == null ? '' : const JsonEncoder.withIndent('  ').convert(_geojson);
      _coverage = null;
      _coverageError = null;
      _drawMode = null;
      _drawPoints.clear();
      _handles = [];
      _selectedHandle = null;
    });
    if (item != null && _geojson != null) {
      _showEditHandles(_geojson!);
      _setStatus('Editing existing boundary. Tap an orange point, then tap its new position.', 'active');
      _fitGeojson(_geojson!);
      _lookupCoverage(_geojson!);
    }
  }

  void _closeForm() {
    setState(() {
      _formOpen = false;
      _editingId = null;
      _hiddenId = null;
      _geojson = null;
      _handles = [];
      _selectedHandle = null;
      _drawMode = null;
      _drawPoints.clear();
      _coverage = null;
    });
  }

  Future<void> _pickGeojsonFile() async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.any);
      final file = picked.firstOrNull;
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 2097152) throw Exception('GeoJSON file must not exceed 2 MB');
      final geojson = jsonDecode(utf8.decode(bytes));
      if (geojson is! Map) throw Exception('Invalid GeoJSON file');
      final parsed = Geo.parse(geojson);
      if (parsed.isEmpty) throw Exception('The GeoJSON file has no drawable geometry');
      if (!_formOpen) _openForm();
      setState(() {
        _formError = null;
        _geojson = Map<String, dynamic>.from(geojson);
        _geojsonText.text = const JsonEncoder.withIndent('  ').convert(geojson);
        _drawMode = null;
        _drawPoints.clear();
      });
      _showEditHandles(_geojson!);
      _fitGeojson(_geojson!);
      _lookupCoverage(_geojson!);
    } catch (e) {
      setState(() => _formError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      Map<String, dynamic>? geojson;
      final text = _geojsonText.text.trim();
      if (text.isNotEmpty) {
        final decoded = jsonDecode(text);
        if (decoded is! Map) throw Exception('GeoJSON must be an object');
        geojson = Map<String, dynamic>.from(decoded);
      } else if (_editingId != null && _originalGeojson != null) {
        geojson = _originalGeojson;
      }
      if (geojson == null) throw Exception('Draw or upload a hazard boundary before saving.');
      if (_type == 'other' && _typeOther.text.trim().length < 2) throw Exception('Enter the other hazard type.');
      final payload = {
        'hazard_name': _name.text.trim(),
        'hazard_type': _type,
        if (_type == 'other') 'hazard_type_other': _typeOther.text.trim(),
        'municipality_id': _municipalityId,
        'risk_level': _risk,
        'description': _description.text.trim(),
        'geojson_data': geojson,
      };
      if (_editingId != null) {
        await Api.instance.put('/hazards/$_editingId', payload);
      } else {
        await Api.instance.post('/hazards', payload);
      }
      if (!mounted) return;
      Ui.toast(context, _editingId != null ? 'Hazard updated' : 'Hazard added');
      _openForm();
      _setStatus('Hazard saved. Choose a shape to map another area.', 'success');
      _load();
    } on ApiException catch (e) {
      setState(() => _formError = e.errors.isEmpty ? e.message : '${e.message}\n${e.errors.values.join('\n')}');
    } catch (e) {
      setState(() => _formError = e.toString().replaceFirst('Exception: ', '').replaceFirst('FormatException: ', 'Invalid GeoJSON: '));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------- actions

  Future<Map<String, dynamic>?> _fetch(int id) async {
    try {
      return mapOf(await Api.instance.get('/hazards/$id'));
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
      return null;
    }
  }

  void _fitGeojson(dynamic geojson) {
    final bounds = Geo.parse(geojson).bounds;
    if (bounds != null) fitMap(_map, bounds, maxZoom: 15);
  }

  Future<void> _viewOnMap(int id) async {
    final item = await _fetch(id);
    if (item == null || !mounted) return;
    _stopDrawing(clear: false);
    _fitGeojson(item['geojson_data']);
    _showHazardSheet(item);
  }

  void _showHazardSheet(Map<String, dynamic> h) {
    final risk = str(h, 'risk_level');
    showDetailSheet(
      context,
      title: str(h, 'hazard_name'),
      kicker: '${Domain.riskLabel(risk)} - ${Domain.hazardTypeLabel(h['hazard_type'])}',
      color: Domain.riskColor(risk),
      icon: Icons.warning_amber_rounded,
      rows: [('Municipality', str(h, 'municipality_name', 'Province-wide')), ('Details', str(h, 'description', 'No description provided.'))],
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            _editHazard(intOf(h, 'id'));
          },
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Ui.red),
          onPressed: () {
            Navigator.pop(context);
            _deleteHazard(h);
          },
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Delete'),
        ),
      ],
    );
  }

  Future<void> _editHazard(int id) async {
    final item = await _fetch(id);
    if (item != null && mounted) _openForm(item);
  }

  Future<void> _deleteHazard(Map<String, dynamic> item) async {
    if (!await Ui.confirm(context, 'Delete ${str(item, 'hazard_name')}?', confirmText: 'Delete')) return;
    try {
      await Api.instance.delete('/hazards/${item['id']}');
      if (!mounted) return;
      Ui.toast(context, 'Hazard deleted');
      if (_editingId == intOf(item, 'id')) _closeForm();
      _load();
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
    }
  }

  // ------------------------------------------------------------------ layers

  List<Widget> _layers() {
    final polygons = <Polygon>[];
    final polylines = <Polyline>[];
    final markers = <Marker>[];
    for (final h in _rows) {
      if (_hiddenId != null && h.id == _hiddenId) continue;
      final risk = str(h.row, 'risk_level');
      final color = Domain.riskColor(risk);
      final fill = {'critical': .46, 'high': .42, 'moderate': .34, 'low': .26}[risk] ?? .3;
      final weight = {'critical': 4.0, 'high': 3.5, 'moderate': 3.0, 'low': 2.5}[risk] ?? 3.0;
      for (final ring in h.shapes.polygons) {
        polygons.add(
          Polygon(
            points: ring,
            color: color.withValues(alpha: fill),
            borderColor: color,
            borderStrokeWidth: weight,
          ),
        );
      }
      for (final line in h.shapes.lines) {
        polylines.add(Polyline(points: line, color: color, strokeWidth: weight));
      }
      for (final point in h.shapes.points) {
        markers.add(circleMarker(point, color, onTap: () => _showHazardSheet(h.row)));
      }
    }
    // Preview of the boundary being edited/drawn.
    if (_geojson != null && _formOpen) {
      final shapes = Geo.parse(_geojson);
      for (final ring in shapes.polygons) {
        polygons.add(Polygon(points: ring, color: Ui.indigo.withValues(alpha: .25), borderColor: Ui.indigo, borderStrokeWidth: 3));
      }
      for (final line in shapes.lines) {
        polylines.add(Polyline(points: line, color: Ui.indigo, strokeWidth: 3));
      }
      for (final point in shapes.points) {
        markers.add(circleMarker(point, Ui.indigo));
      }
    }
    if (_drawPoints.isNotEmpty) {
      polylines.add(
        Polyline(
          points: _drawPoints,
          color: const Color(0xFF2563EB),
          strokeWidth: 3,
          pattern: StrokePattern.dashed(segments: const [7, 6]),
        ),
      );
      for (final point in _drawPoints) {
        markers.add(circleMarker(point, const Color(0xFF2563EB), size: 14));
      }
    }
    for (var i = 0; i < _handles.length; i++) {
      final selected = _selectedHandle == i;
      markers.add(
        circleMarker(
          _handles[i],
          selected ? Ui.red : Ui.orange,
          size: selected ? 26 : 20,
          onTap: () {
            setState(() => _selectedHandle = selected ? null : i);
            _setStatus(selected ? 'Vertex deselected.' : 'Vertex selected. Tap the map where it should move.', 'active');
          },
        ),
      );
    }
    return [
      _satellite ? satelliteTileLayer() : osmTileLayer(),
      const CaviteMaskLayer(),
      PolygonLayer(polygons: polygons),
      PolylineLayer(polylines: polylines),
      MarkerLayer(markers: markers),
      osmAttribution(),
    ];
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final mapHeight = MediaQuery.of(context).size.height * .42;
    final toneColor = switch (_drawTone) {
      'success' => Ui.emerald,
      'error' => Ui.red,
      'active' => Ui.indigo,
      _ => Ui.slate500,
    };
    return Column(
      children: [
        SizedBox(
          height: mapHeight,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: AppConfig.mapCenter,
                  initialZoom: AppConfig.mapZoom,
                  minZoom: AppConfig.mapMinZoom,
                  maxZoom: 19,
                  cameraConstraint: _cameraConstraint ?? Geo.caviteConstraint,
                  onMapEvent: (event) => reapplyCameraConstraint(_map, event),
                  onTap: (_, point) => _onMapTap(point),
                ),
                children: _layers(),
              ),
              Positioned(
                left: 10,
                top: 10,
                right: 60,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _drawChip('Rectangle', Icons.crop_square, _drawMode == 'rectangle', () => _startDrawing('rectangle')),
                    _drawChip('Polygon', Icons.timeline, _drawMode == 'polygon', () => _startDrawing('polygon')),
                    if (_drawMode == 'polygon') _drawChip('Finish', Icons.check, false, _finishPolygon),
                    if (_drawMode == 'polygon') _drawChip('Undo', Icons.undo, false, _undoPoint),
                    if (_editingId != null) _drawChip('Redraw', Icons.refresh, false, _redraw),
                    _drawChip('Clear', Icons.close, false, () => _stopDrawing(clear: true)),
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
                      final points = <LatLng>[];
                      for (final h in _rows) {
                        final b = h.shapes.bounds;
                        if (b != null) points.addAll([b.southWest, b.northEast]);
                      }
                      if (points.isNotEmpty) fitMap(_map, LatLngBounds.fromPoints(points));
                    }),
                  ],
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: toneColor.withValues(alpha: .4)),
                  ),
                  child: Text(
                    _drawStatus,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: toneColor),
                  ),
                ),
              ),
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
                  eyebrow: 'Hazard command',
                  title: 'Hazard mapping',
                  subtitle: 'Draw a rectangle or polygon on the map, classify the risk, then publish the hazard record.',
                  icon: Icons.warning_amber_rounded,
                  actions: [
                    BannerButton(label: 'Draw hazard area', icon: Icons.draw_outlined, onPressed: () => _startDrawing('polygon')),
                    BannerButton(label: 'Upload GeoJSON', icon: Icons.upload_file_outlined, primary: false, onPressed: _pickGeojsonFile),
                    BannerButton(
                      label: 'Export CSV',
                      icon: Icons.download_outlined,
                      primary: false,
                      onPressed: _rows.isEmpty
                          ? null
                          : () => Ui.exportCsv(context, 'hazards', [
                              'Hazard',
                              'Type',
                              'Municipality',
                              'Risk',
                              'Description',
                            ], _rows.map((h) => [h.row['hazard_name'], Domain.hazardTypeLabel(h.row['hazard_type']), h.row['municipality_name'], h.row['risk_level'], h.row['description']]).toList()),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _legend(),
                const SizedBox(height: 12),
                if (_formOpen) _formCard(),
                if (_formOpen) const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _typeFilter,
                        isExpanded: true,
                        decoration: fieldDecoration('Type'),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('All Type')),
                          ...Domain.hazardTypeLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                        ],
                        onChanged: (v) {
                          setState(() => _typeFilter = v ?? '');
                          _load();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _riskFilter,
                        isExpanded: true,
                        decoration: fieldDecoration('Risk'),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('All Risk')),
                          ...Domain.riskOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                        ],
                        onChanged: (v) {
                          setState(() => _riskFilter = v ?? '');
                          _load();
                        },
                      ),
                    ),
                  ],
                ),
                ListHeading('Hazard records', count: _rows.length),
                if (_loading)
                  const Center(
                    child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
                  ),
                if (!_loading && _rows.isEmpty) const EmptyNote('No hazards found.'),
                ..._rows.map((h) {
                  final risk = str(h.row, 'risk_level');
                  final accent = switch (risk) {
                    'critical' => kGradRed,
                    'high' => kGradOrange,
                    'moderate' => const [Color(0xFFFBBF24), Color(0xFFD97706)],
                    _ => kGradGreen,
                  };
                  return RecordCard(
                    title: str(h.row, 'hazard_name'),
                    subtitle: str(h.row, 'description', 'No description provided.'),
                    icon: Icons.warning_amber_rounded,
                    accent: accent,
                    onTap: () => _viewOnMap(h.id),
                    pills: [
                      Pill(Domain.hazardTypeLabel(h.row['hazard_type']), color: Ui.indigo),
                      Pill(str(h.row, 'municipality_name', 'Province-wide'), color: Ui.slate500),
                      Pill(Domain.riskLabel(risk), color: Domain.riskColor(risk)),
                    ],
                    actions: [
                      ActionIconButton(icon: Icons.visibility_outlined, tooltip: 'View hazard', color: Ui.sky, onPressed: () => _viewOnMap(h.id)),
                      ActionIconButton(icon: Icons.edit_outlined, tooltip: 'Edit hazard', color: Ui.amber, onPressed: () => _editHazard(h.id)),
                      ActionIconButton(icon: Icons.delete_outline, tooltip: 'Delete hazard', color: Ui.red, onPressed: () => _deleteHazard(h.row)),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend() {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        const Text(
          'Heatmap guide:',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Ui.slate500),
        ),
        for (final e in {'High Risk': Domain.riskColors['high']!, 'Medium': Domain.riskColors['moderate']!, 'Low': Domain.riskColors['low']!, 'Safe': Ui.emerald}.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.square_rounded, size: 12, color: e.value),
              const SizedBox(width: 4),
              Text(e.key, style: const TextStyle(fontSize: 12)),
            ],
          ),
      ],
    );
  }

  Widget _formCard() {
    final municipalityItems = [
      const DropdownMenuItem(value: '', child: Text('Select municipality')),
      ..._municipalities.map(
        (m) => DropdownMenuItem(
          value: str(m, 'id'),
          child: Text(str(m, 'municipality_name'), overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
    if (_municipalityId.isNotEmpty && !municipalityItems.any((i) => i.value == _municipalityId)) {
      municipalityItems.add(DropdownMenuItem(value: _municipalityId, child: Text(_session.municipalityName.isEmpty ? 'Municipality #$_municipalityId' : _session.municipalityName)));
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
                        'HAZARD RECORD',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Ui.slate500, letterSpacing: .6),
                      ),
                      Text(_editingId != null ? 'Edit hazard' : 'Add hazard', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                IconButton(onPressed: _closeForm, icon: const Icon(Icons.close), tooltip: 'Close form'),
              ],
            ),
            const FieldLabel('Hazard name'),
            TextFormField(controller: _name, decoration: fieldDecoration('e.g. Barangay flood-prone zone'), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the hazard name' : null),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('Hazard type'),
                      DropdownButtonFormField<String>(
                        initialValue: _type,
                        isExpanded: true,
                        decoration: fieldDecoration('Type'),
                        items: [
                          ...Domain.standardHazardTypes.map((t) => DropdownMenuItem(value: t, child: Text(Domain.hazardTypeLabels[t]!))),
                          const DropdownMenuItem(value: 'other', child: Text('Other')),
                        ],
                        onChanged: (v) => setState(() => _type = v ?? 'flood_zone'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('Risk level'),
                      DropdownButtonFormField<String>(
                        initialValue: _risk,
                        isExpanded: true,
                        decoration: fieldDecoration('Risk'),
                        items: Domain.riskOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                        onChanged: (v) => setState(() => _risk = v ?? 'low'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_type == 'other') ...[const FieldLabel('Other hazard type'), TextFormField(controller: _typeOther, maxLength: 80, decoration: fieldDecoration('Enter hazard type'))],
            const FieldLabel('Municipality'),
            if (_session.isSubadmin)
              TextFormField(initialValue: _session.municipalityName.isEmpty ? 'Assigned municipality' : _session.municipalityName, enabled: false, decoration: fieldDecoration(''))
            else
              DropdownButtonFormField<String>(
                key: ValueKey('municipality-$_municipalityId'),
                initialValue: _municipalityId,
                isExpanded: true,
                decoration: fieldDecoration('Select municipality'),
                items: municipalityItems,
                validator: (v) => (v == null || v.isEmpty) ? 'Select a municipality' : null,
                onChanged: (v) => setState(() => _municipalityId = v ?? ''),
              ),
            const FieldLabel('Description'),
            TextFormField(controller: _description, maxLines: 3, maxLength: 5000, decoration: fieldDecoration('Add affected areas, known triggers, or response notes.')),
            const FieldLabel('Boundary data (GeoJSON)'),
            TextFormField(
              controller: _geojsonText,
              maxLines: 4,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: fieldDecoration('GeoJSON appears here after drawing or upload'),
            ),
            const SizedBox(height: 8),
            _coverageCard(),
            ErrorBanner(_formError),
            const SizedBox(height: 14),
            PrimaryButton(label: _saving ? 'Saving...' : 'Save hazard', icon: Icons.save_outlined, onPressed: _saving ? null : _save),
          ],
        ),
      ),
    );
  }

  Widget _coverageCard() {
    if (_coverageLoading) {
      return const Text('Checking covered locations... Comparing the area with verified GIS coordinates.', style: TextStyle(fontSize: 12, color: Ui.slate500));
    }
    if (_coverageError != null) {
      return Text('Location lookup failed: $_coverageError', style: const TextStyle(fontSize: 12, color: Ui.red));
    }
    final coverage = _coverage;
    if (coverage == null) return const SizedBox.shrink();
    final municipalities = rowsOf(coverage['municipalities']);
    final safeZones = rowsOf(coverage['safe_zones']);
    final centers = rowsOf(coverage['evacuation_centers']);
    final names = municipalities.map((m) => str(m, 'municipality_name')).join(', ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Covered locations',
            style: TextStyle(fontSize: 11, color: Ui.slate500, fontWeight: FontWeight.w700),
          ),
          Text(names.isEmpty ? 'No municipality center detected' : names, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('${municipalities.length} municipalities - ${safeZones.length} safe zones - ${centers.length} evacuation centers', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            safeZones.isEmpty && centers.isEmpty ? 'Only locations with verified coordinates can be detected.' : [...safeZones, ...centers].map((x) => str(x, 'name')).join(' - '),
            style: const TextStyle(fontSize: 12, color: Ui.slate500),
          ),
        ],
      ),
    );
  }

  Widget _drawChip(String label, IconData icon, bool active, VoidCallback onTap) {
    return Material(
      color: active ? Ui.indigo : Colors.white,
      borderRadius: BorderRadius.circular(999),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: active ? Colors.white : Ui.slate900),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.white : Ui.slate900),
              ),
            ],
          ),
        ),
      ),
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
