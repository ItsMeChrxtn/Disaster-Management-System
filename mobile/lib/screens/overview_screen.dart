import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/location.dart';
import '../core/notifications.dart';
import '../core/session.dart';
import '../core/ui.dart';

/// Role-aware dashboard overview (overview() + renderCards/renderCharts).
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key, required this.onOpenView});

  final void Function(String view) onOpenView;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  static const Map<String, (String, String, Color)> _cardMeta = {
    'total_residents': ('Total Residents', 'People', Ui.indigo),
    'total_municipalities': ('Total Municipalities', 'Areas', Ui.sky),
    'total_hazards': ('Total Hazards', 'Active', Ui.orange),
    'total_safe_zones': ('Total Safe Zones', 'Available', Ui.emerald),
    'total_evacuation_centers': ('Total Evacuation Centers', 'Available', Ui.violet),
    'total_alerts': ('Total Alerts', 'Published', Ui.red),
    'total_reports': ('Total Reports', 'Generated', Ui.sky),
    'active_alerts': ('Active Alerts', 'Current', Ui.red),
    'nearby_safe_zones': ('Nearby Safe Zones', 'Municipality', Ui.emerald),
    'nearby_evacuation_centers': ('Nearby Evacuation Centers', 'Municipality', Ui.violet),
    'weather_status': ('Weather Status', 'Live', Ui.sky),
  };

  Map<String, dynamic>? _dashboard;
  List<Map<String, dynamic>> _alerts = [];
  String? _weatherText;
  String? _weatherLevel;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _rainfall;
  bool _rainfallFailed = false;

  static const Map<String, (String, Color, IconData)> _hazardTypes = {
    'flood_zone': ('Flood', Color(0xFF2563EB), Icons.water_drop),
    'storm_surge_area': ('Storm surge', Color(0xFF7C3AED), Icons.waves),
    'landslide': ('Landslide', Color(0xFFA16207), Icons.landslide_outlined),
    'earthquake_area': ('Earthquake', Color(0xFFBE123C), Icons.vibration),
    'tsunami': ('Tsunami', Color(0xFF0891B2), Icons.tsunami_outlined),
    'volcanic': ('Volcanic / ashfall', Color(0xFF57534E), Icons.volcano_outlined),
    'fire': ('Fire', Color(0xFFDC2626), Icons.local_fire_department_outlined),
  };
  static const Map<String, String> _cardViews = {
    'active_alerts': 'alerts',
    'total_alerts': 'alerts',
    'nearby_safe_zones': 'safezones',
    'nearby_evacuation_centers': 'safezones',
    'total_safe_zones': 'safezones',
    'total_evacuation_centers': 'safezones',
    'weather_status': 'weather',
    'total_hazards': 'hazards',
    'total_reports': 'reports',
    'total_municipalities': 'municipalities',
    'total_residents': 'users',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = Session.instance;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      LatLng? position;
      if (session.isResident) position = await Location.tryCurrent(timeout: const Duration(seconds: 5));
      final query = position != null ? '?latitude=${position.latitude}&longitude=${position.longitude}' : '';
      final results = await Future.wait([Api.instance.get('/dashboard$query'), Api.instance.get(session.isManager ? '/alerts/manage' : '/notifications/history')]);
      final dashboard = mapOf(results[0]);
      final alerts = rowsOf(results[1]).where((a) => str(a, 'status').isEmpty || str(a, 'status') == 'sent').toList();
      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
        _alerts = alerts;
        _loading = false;
      });
      _loadRainfall();
      if (session.isResident) {
        final center = mapOf(dashboard['municipality_center']);
        _loadWeather(position ?? (center.isEmpty ? null : LatLng(dbl(center, 'latitude') ?? 0, dbl(center, 'longitude') ?? 0)));
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _loadRainfall() async {
    try {
      final data = mapOf(await Api.instance.get('/weather/municipalities'));
      if (mounted) setState(() => _rainfall = data);
    } catch (_) {
      if (mounted) setState(() => _rainfallFailed = true);
    }
  }

  void _showAlert(Map<String, dynamic> a) {
    final critical = str(a, 'alert_level') == 'critical';
    if (!Session.instance.isManager && !isRead(a)) AlertNotifier.instance.markRead(a['id'] ?? '').catchError((_) {});
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (str(a, 'alert_level').isNotEmpty) Pill(Ui.titleCase(str(a, 'alert_level')), color: critical ? Ui.red : Ui.amber),
                  if (str(a, 'alert_type').isNotEmpty) Pill(Ui.titleCase(str(a, 'alert_type')), color: Ui.indigo),
                  Pill(str(a, 'municipality_name', 'Province-wide'), color: Ui.slate500),
                ],
              ),
              const SizedBox(height: 10),
              Text(str(a, 'title'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(Ui.formatDateTime(a['sent_at'] ?? a['created_at']), style: const TextStyle(fontSize: 12, color: Ui.slate500)),
              const SizedBox(height: 12),
              Text(str(a, 'message'), style: const TextStyle(fontSize: 14.5, height: 1.55)),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onOpenView('alerts');
                },
                icon: const Icon(Icons.notifications_outlined),
                label: const Text('Open alert center'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Collapsible panel like the web overview dropdowns: summary chips when closed, details when open.
  Widget _dropdown(String kicker, String title, List<Widget> chips, Widget body) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ui.line),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(kicker, color: Ui.slate400),
              const SizedBox(height: 2),
              Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: chips),
            ],
          ),
          children: [body],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
    ),
  );

  Widget _multiHazard(Map<String, dynamic> charts) {
    final counts = <String, int>{};
    for (final row in rowsOf(charts['hazards_by_type'])) {
      final key = _hazardTypes.containsKey(str(row, 'label')) ? str(row, 'label') : 'other';
      counts[key] = (counts[key] ?? 0) + intOf(row, 'value');
    }
    final active = counts.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    (String, Color, IconData) meta(String key) => _hazardTypes[key] ?? ('Other hazards', const Color(0xFF475569), Icons.add_circle_outline);
    final tiles = [..._hazardTypes.keys, 'other'].map((key) {
      final m = meta(key), count = counts[key] ?? 0;
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: count > 0 ? Colors.white : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: count > 0 ? m.$2.withValues(alpha: .35) : Ui.line),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: count > 0 ? m.$2 : m.$2.withValues(alpha: .12), borderRadius: BorderRadius.circular(9)),
              child: Icon(m.$3, size: 16, color: count > 0 ? Colors.white : m.$2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                m.$1,
                style: const TextStyle(fontSize: 11.5, color: Ui.slate500, fontWeight: FontWeight.w600),
                maxLines: 2,
              ),
            ),
            Text('$count', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
      );
    }).toList();
    return _dropdown(
      'All disasters & calamities',
      'Multi-hazard status',
      active.isEmpty
          ? [_chip('No active hazard records', Ui.emerald)]
          : [for (final e in active.take(4)) _chip('${meta(e.key).$1} ${e.value}', meta(e.key).$2), if (active.length > 4) _chip('+${active.length - 4} more', Ui.slate500)],
      GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.6, children: tiles),
    );
  }

  Widget _rainfallWatch() {
    const colors = {'red': Color(0xFFDC2626), 'orange': Color(0xFFF97316), 'yellow': Color(0xFFEAB308)};
    final rows = rowsOf(_rainfall?['municipalities']);
    final summary = mapOf(mapOf(_rainfall?['summary'])['rainfall']);
    final warned = ['red', 'orange', 'yellow'].where((c) => intOf(summary, c) > 0).toList();
    final chips = _rainfallFailed
        ? [_chip('Rainfall feed unavailable', Ui.slate500)]
        : _rainfall == null
        ? [_chip('Checking ${rows.isEmpty ? 23 : rows.length} municipalities…', Ui.slate500)]
        : warned.isEmpty
        ? [_chip('No rainfall warning · all ${rows.length} municipalities', Ui.emerald)]
        : [for (final c in warned) _chip('${Ui.titleCase(c)} ${intOf(summary, c)}', colors[c]!)];
    const order = {'red': 0, 'orange': 1, 'yellow': 2, 'none': 3};
    final sorted = [...rows]..sort((a, b) => (order[str(mapOf(a['rainfall_warning']), 'color', 'none')] ?? 3).compareTo(order[str(mapOf(b['rainfall_warning']), 'color', 'none')] ?? 3));
    return _dropdown(
      'PAGASA rainfall warning',
      'Rainfall watch by municipality',
      chips,
      Column(
        children: [
          for (final m in sorted)
            Builder(
              builder: (context) {
                final warning = mapOf(m['rainfall_warning']), current = mapOf(m['current']);
                final color = colors[str(warning, 'color')] ?? Ui.slate400;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border(left: BorderSide(color: color, width: 4)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(str(m, 'municipality_name'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                      Text('${str(warning, 'mm_per_hour', '0')} mm/hr · ${(dbl(current, 'temperature_c') ?? 0).round()}°C', style: const TextStyle(fontSize: 12, color: Ui.slate500)),
                    ],
                  ),
                );
              },
            ),
          if (sorted.isEmpty) const Text('Rainfall data is loading or unavailable.', style: TextStyle(fontSize: 12.5, color: Ui.slate500)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => widget.onOpenView('weather'), child: const Text('Weather monitoring')),
          ),
        ],
      ),
    );
  }

  Future<void> _loadWeather(LatLng? position) async {
    try {
      final query = position != null ? '?latitude=${position.latitude}&longitude=${position.longitude}' : '';
      final data = mapOf(await Api.instance.get('/weather/current$query'));
      final current = mapOf(data['current']);
      if (!mounted) return;
      setState(() {
        _weatherText = '${str(current, 'condition')} - ${(dbl(current, 'temperature_c') ?? 0).round()} C';
        _weatherLevel = str(data, 'warning_level');
      });
    } catch (_) {
      if (mounted) setState(() => _weatherText = 'Unavailable');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _dashboard == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _dashboard == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Ui.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final dashboard = _dashboard!;
    final cards = mapOf(dashboard['cards']);
    final charts = mapOf(dashboard['charts']);
    final role = str(dashboard, 'role');
    final titles = {'admin': 'Admin Dashboard', 'subadmin': 'Municipal Dashboard', 'resident': 'Resident Dashboard'};

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: kNavyGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x590F172A), blurRadius: 40, offset: Offset(0, 22), spreadRadius: -18)],
            ),
            child: Stack(
              children: [
                const Positioned.fill(child: GridOverlay()),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('Live command overview', color: Color(0xFF93C5FD)),
                      const SizedBox(height: 8),
                      Text(
                        titles[role] ?? 'Situational overview',
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.6),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Monitor active hazards, public alerts, response facilities, and municipal readiness from one operating view.',
                        style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5, height: 1.45),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: .18)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFF34D399),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: const Color(0xFF34D399).withValues(alpha: .4), spreadRadius: 4)],
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Operational',
                              style: TextStyle(color: Color(0xFFBBF7D0), fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            const Spacer(),
                            Text('Updated ${Ui.formatDateTime(dashboard['generated_at'])}', style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.25,
            children: cards.entries.map((entry) {
              final meta = _cardMeta[entry.key] ?? (entry.key, '', Ui.indigo);
              var value = entry.value?.toString() ?? 'Loading...';
              if (entry.key == 'weather_status' && _weatherText != null) value = _weatherText!;
              final accent = _cardGradient(entry.key);
              final target = _cardViews[entry.key];
              return GestureDetector(
                onTap: target == null ? null : () => widget.onOpenView(target),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Ui.line),
                    boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 14, offset: Offset(0, 6), spreadRadius: -6)],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: accent, begin: Alignment.topCenter, end: Alignment.bottomCenter),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: GradientTile(icon: _cardIcon(entry.key), colors: accent, size: 36),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    meta.$1,
                                    style: const TextStyle(fontSize: 11.5, color: Ui.slate500, fontWeight: FontWeight.w600, height: 1.25),
                                    maxLines: 3,
                                  ),
                                ),
                                Pill(meta.$2, color: meta.$3),
                              ],
                            ),
                            const Spacer(),
                            Padding(
                              padding: const EdgeInsets.only(right: 44),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  value,
                                  style: TextStyle(fontSize: entry.key == 'weather_status' ? 15 : 28, fontWeight: FontWeight.w800, color: Ui.slate900, letterSpacing: -.8),
                                ),
                              ),
                            ),
                            if (entry.key == 'weather_status' && _weatherLevel != null) Text('Warning level: $_weatherLevel', style: const TextStyle(fontSize: 11, color: Ui.slate500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _multiHazard(charts),
          const SizedBox(height: 10),
          _rainfallWatch(),
          const SizedBox(height: 16),
          _chartCard('Risk profile', 'Hazards by severity', _doughnut(rowsOf(charts['hazards_by_severity']))),
          const SizedBox(height: 12),
          _chartCard('Notification trend', 'Alert activity', _line(rowsOf(charts['alerts_last_six_months']))),
          const SizedBox(height: 12),
          _chartCard(
            'Current advisories',
            'Active alerts',
            _alerts.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No active alerts.', style: TextStyle(color: Ui.slate500, fontSize: 13)),
                  )
                : Column(
                    children: _alerts.take(5).map((a) {
                      final critical = str(a, 'alert_level') == 'critical';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showAlert(a),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border(left: BorderSide(color: critical ? Ui.red : Ui.amber, width: 4)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(str(a, 'title'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                                        const SizedBox(height: 4),
                                        Text(
                                          str(a, 'message'),
                                          style: const TextStyle(fontSize: 12.5, color: Ui.slate500),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Tap for details',
                                          style: TextStyle(fontSize: 11, color: Ui.indigo, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: Ui.slate400),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
            action: TextButton(onPressed: () => widget.onOpenView('alerts'), child: const Text('Open alerts')),
          ),
          const SizedBox(height: 12),
          _chartCard('Response capacity', 'Response facilities', _bar(rowsOf(charts['facilities']))),
        ],
      ),
    );
  }

  static List<Color> _cardGradient(String key) => switch (key) {
    'total_hazards' || 'active_alerts' || 'total_alerts' => kGradRed,
    'total_safe_zones' || 'nearby_safe_zones' => kGradGreen,
    'total_evacuation_centers' || 'nearby_evacuation_centers' => kGradViolet,
    'weather_status' || 'total_reports' || 'total_municipalities' => kGradSky,
    _ => kGradBlue,
  };

  static IconData _cardIcon(String key) => switch (key) {
    'total_residents' => Icons.people_outline,
    'total_municipalities' => Icons.location_city_outlined,
    'total_hazards' => Icons.warning_amber_rounded,
    'total_safe_zones' || 'nearby_safe_zones' => Icons.shield_outlined,
    'total_evacuation_centers' || 'nearby_evacuation_centers' => Icons.home_work_outlined,
    'total_alerts' || 'active_alerts' => Icons.notifications_outlined,
    'total_reports' => Icons.description_outlined,
    'weather_status' => Icons.cloud_outlined,
    _ => Icons.insights_outlined,
  };

  Widget _chartCard(String kicker, String title, Widget child, {Widget? action}) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ui.line),
        boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 16, offset: Offset(0, 6), spreadRadius: -8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFFBFCFE), Colors.white], begin: Alignment.topCenter, end: Alignment.bottomCenter),
              border: Border(bottom: BorderSide(color: Ui.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(kicker, color: Ui.slate400),
                      const SizedBox(height: 2),
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -.3)),
                    ],
                  ),
                ),
                ?action,
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  Widget _doughnut(List<Map<String, dynamic>> rows) {
    const palette = [Color(0xFFDC2626), Color(0xFFF97316), Color(0xFFF59E0B), Color(0xFF10B981)];
    final total = rows.fold<int>(0, (sum, r) => sum + intOf(r, 'value'));
    if (rows.isEmpty || total == 0) return const Text('No hazard data.', style: TextStyle(color: Ui.slate500, fontSize: 13));
    return Row(
      children: [
        SizedBox(
          width: 150,
          height: 150,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 38,
              sections: [for (var i = 0; i < rows.length; i++) PieChartSectionData(value: intOf(rows[i], 'value').toDouble(), color: palette[i % palette.length], radius: 34, showTitle: false)],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < rows.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: palette[i % palette.length]),
                      const SizedBox(width: 6),
                      Expanded(child: Text(str(rows[i], 'label'), style: const TextStyle(fontSize: 12.5))),
                      Text('${intOf(rows[i], 'value')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _line(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const Text('No alert data.', style: TextStyle(color: Ui.slate500, fontSize: 13));
    final maxValue = rows.fold<int>(0, (m, r) => intOf(r, 'value') > m ? intOf(r, 'value') : m);
    return SizedBox(
      height: 190,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: (maxValue < 4 ? 4 : maxValue * 1.2).toDouble(),
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, interval: 1)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= rows.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(str(rows[index], 'label'), style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < rows.length; i++) FlSpot(i.toDouble(), intOf(rows[i], 'value').toDouble())],
              isCurved: true,
              color: Ui.indigo,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: Ui.indigo.withValues(alpha: .15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const Text('No facility data.', style: TextStyle(color: Ui.slate500, fontSize: 13));
    const palette = [Color(0xFF10B981), Color(0xFF8B5CF6)];
    final maxValue = rows.fold<int>(0, (m, r) => intOf(r, 'value') > m ? intOf(r, 'value') : m);
    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          maxY: (maxValue < 4 ? 4 : maxValue * 1.2).toDouble(),
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= rows.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(str(rows[index], 'label'), style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < rows.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [BarChartRodData(toY: intOf(rows[i], 'value').toDouble(), color: palette[i % palette.length], width: 34, borderRadius: BorderRadius.circular(6))],
              ),
          ],
        ),
      ),
    );
  }
}
