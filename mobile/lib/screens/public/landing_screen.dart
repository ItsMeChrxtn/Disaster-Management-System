import 'dart:async';

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../core/api.dart';
import '../../core/ui.dart';
import 'public_map_screen.dart';

/// Mobile version of frontend/index.html: hero, alert strip, live stats,
/// coverage, about, preparedness, FAQs and the sign-in call to action.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  Map<String, dynamic>? _gis;
  List<Map<String, dynamic>> _alerts = [];
  bool _gisFailed = false;
  bool _alertsFailed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(AppConfig.alertPoll, (_) => _loadAlerts());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([_loadGis(), _loadAlerts()]);
  }

  Future<void> _loadGis() async {
    try {
      final data = mapOf(await Api.instance.get('/gis/layers'));
      if (mounted) setState(() => _gis = data);
    } catch (_) {
      if (mounted) setState(() => _gisFailed = true);
    }
  }

  Future<void> _loadAlerts() async {
    try {
      final rows = rowsOf(await Api.instance.get('/alerts'));
      if (mounted) setState(() => _alerts = rows);
    } catch (_) {
      if (mounted) setState(() => _alertsFailed = true);
    }
  }

  int _count(String key) => (_gis?[key] as List?)?.length ?? 0;
  int get _hazardCount => _count('flood_layer') + _count('storm_surge_layer') + _count('earthquake_layer') + _count('landslide_layer') + _count('other_hazard_layer');

  void _showAlert(Map<String, dynamic> alert) {
    final critical = str(alert, 'alert_level') == 'critical';
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
                children: [
                  Pill(Ui.titleCase(str(alert, 'alert_level', 'alert')), color: critical ? Ui.red : Ui.amber),
                  if (str(alert, 'alert_type').isNotEmpty) Pill(Ui.titleCase(str(alert, 'alert_type')), color: Ui.indigo),
                  Pill(str(alert, 'municipality_name', 'Province-wide'), color: Ui.slate500),
                ],
              ),
              const SizedBox(height: 10),
              Text(str(alert, 'title'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(Ui.formatDateTime(alert['sent_at'] ?? alert['created_at']), style: const TextStyle(fontSize: 12, color: Ui.slate500)),
              const SizedBox(height: 12),
              Text(str(alert, 'message'), style: const TextStyle(fontSize: 14.5, height: 1.55)),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(this.context).push(MaterialPageRoute(builder: (_) => const PublicMapScreen()));
                },
                icon: const Icon(Icons.map_outlined),
                label: const Text('Check the live map'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hazards = _hazardCount;
    final facilities = _count('safe_zone_layer') + _count('evacuation_center_layer');
    final municipalities = rowsOf(_gis?['municipalities']);

    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              titleSpacing: 16,
              title: const BrandMark(),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                    onPressed: () => Navigator.of(context).pushNamed('/login'),
                    child: const Text('Sign in'),
                  ),
                ),
              ],
            ),
            SliverList(
              delegate: SliverChildListDelegate([
                Container(
                  color: const Color(0xFF7F1D1D),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(color: Color(0xFFFECACA), fontSize: 12.5, fontFamily: 'Inter'),
                      children: [
                        TextSpan(
                          text: 'Emergency Hotline: 911',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ' — for life-threatening emergencies, call immediately'),
                      ],
                    ),
                  ),
                ),
                _hero(context),
                ..._alerts.take(3).map(_alertStrip),
                if (_alerts.length > 3)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Text(
                      '+${_alerts.length - 3} more active alert${_alerts.length - 3 == 1 ? '' : 's'} — sign in to see the alert center.',
                      style: const TextStyle(fontSize: 12, color: Ui.slate500),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: .9,
                    children: [
                      _stat(
                        Icons.warning_amber_rounded,
                        _gisFailed
                            ? 'Data unavailable'
                            : _gis == null
                            ? 'Loading...'
                            : '$hazards hazard zone${hazards == 1 ? '' : 's'}',
                        'Flood, storm surge, landslide and earthquake areas with risk levels.',
                        kGradOrange,
                      ),
                      _stat(
                        Icons.shield_outlined,
                        _gisFailed
                            ? 'Data unavailable'
                            : _gis == null
                            ? 'Loading...'
                            : '$facilities safe facilit${facilities == 1 ? 'y' : 'ies'}',
                        'Safe zones and evacuation centers kept visible for public planning.',
                        kGradGreen,
                      ),
                      _stat(
                        Icons.notifications_active_outlined,
                        _alertsFailed
                            ? 'Alerts unavailable'
                            : _alerts.isEmpty
                            ? 'No active alerts'
                            : '${_alerts.length} active alert${_alerts.length == 1 ? '' : 's'}',
                        'Active advisories shown beside local context and map filters.',
                        kGradRed,
                      ),
                      _stat(
                        Icons.location_on_outlined,
                        _gisFailed
                            ? 'Data unavailable'
                            : _gis == null
                            ? 'Loading...'
                            : '${municipalities.length} municipalities & cities',
                        'Municipalities and cities covered across the province.',
                        kGradBlue,
                      ),
                    ],
                  ),
                ),
                _section(
                  kicker: 'Interactive public map',
                  title: 'Everything important stays visible while you explore.',
                  body: 'Use municipality and hazard filters to focus the map on the areas that matter before, during, and after an incident.',
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PublicMapScreen())),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open live map'),
                  ),
                ),
                _section(
                  kicker: 'Provincial coverage',
                  title: 'Live data spans every municipality and city in Cavite.',
                  body: _gis == null ? 'Loading coverage details...' : '${municipalities.length} municipalities and cities with mapped hazard, safe zone, and evacuation center data.',
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: municipalities
                        .map(
                          (m) => Chip(
                            label: Text(str(m, 'municipality_name'), style: const TextStyle(fontSize: 12)),
                            backgroundColor: Ui.slate100,
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                ),
                _section(
                  kicker: 'About the platform',
                  title: 'Built for residents, responders, and local decision makers.',
                  body: 'Disaster Map organizes critical location data into a clean public interface so people can identify risk, nearby facilities, and evacuation options quickly.',
                  child: Column(
                    children: [
                      _feature(Icons.layers_outlined, 'Hazard visibility', 'Flood, storm surge, and earthquake layers are shown with risk levels for easier assessment.'),
                      _feature(Icons.route_outlined, 'Evacuation planning', 'Safe zones and evacuation centers help residents prepare practical safety plans.', colors: kGradGreen),
                      _feature(Icons.campaign_outlined, 'Public alerts', 'Important active advisories surface on the landing page without forcing users into the dashboard.', colors: kGradRed),
                    ],
                  ),
                ),
                _section(
                  kicker: 'Preparedness',
                  title: 'Simple actions before leaving home.',
                  body: 'Use the map together with official barangay and municipal instructions. Keep plans practical, familiar, and easy to repeat.',
                  child: Column(
                    children: [
                      _step(1, 'Check your barangay and the nearest visible hazard layer.'),
                      _step(2, 'Identify at least two nearby safe zones or evacuation centers.'),
                      _step(3, 'Prepare medicine, IDs, phone power, water, and essential supplies.'),
                      _step(4, 'Follow official advisories before floodwater, wind, or road conditions worsen.'),
                    ],
                  ),
                ),
                _section(
                  kicker: 'FAQs',
                  title: 'Common questions',
                  child: Column(
                    children: const [
                      _Faq('What can I see on the public map?', 'You can inspect mapped hazards, safe zones, and evacuation centers for Cavite.', open: true),
                      _Faq('Does the map show my exact location?', 'The map detects your approximate location if you allow location access, and uses it to show your position.'),
                      _Faq('Can I search for a barangay or address?', 'Yes. The search box supports Cavite locations and uses OpenStreetMap Nominatim results.'),
                      _Faq(
                        'Should this replace official emergency instructions?',
                        'No. Treat this as a public awareness tool and still follow instructions from local authorities and emergency responders.',
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Ui.slate100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Ui.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('For authorized teams', rule: true),
                      const SizedBox(height: 6),
                      const Text(
                        'Manage reports, alerts, GIS records, and response data in the dashboard.',
                        style: TextStyle(color: Ui.slate900, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.4),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(onPressed: () => Navigator.of(context).pushNamed('/login'), child: const Text('Go to dashboard')),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 28),
                  child: Text(
                    '© 2026 Disaster Map — Cavite Readiness Hub. Public awareness tool; not a substitute for official emergency instructions. Map data by OpenStreetMap contributors. National Emergency Hotline: 911.',
                    style: TextStyle(fontSize: 11.5, color: Ui.slate500),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final hazards = _hazardCount;
    final facilities = _count('safe_zone_layer') + _count('evacuation_center_layer');
    String metric(int value) => _gisFailed
        ? '–'
        : _gis == null
        ? '…'
        : '$value';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x660F172A), blurRadius: 40, offset: Offset(0, 24), spreadRadius: -18)],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/img/hero.jpg', fit: BoxFit.cover, alignment: const Alignment(0, -.3), cacheWidth: 1080, filterQuality: FilterQuality.low),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF080F1E).withValues(alpha: .96), const Color(0xFF080F1E).withValues(alpha: .82), const Color(0xFF080F1E).withValues(alpha: .45)],
                  stops: const [0, .55, 1],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Public situational awareness', color: Color(0xFF93C5FD)),
                const SizedBox(height: 10),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -.8, fontFamily: 'Inter'),
                    children: [
                      TextSpan(text: 'Prepared communities start with a '),
                      TextSpan(
                        text: 'clear map.',
                        style: TextStyle(color: Color(0xFF7DD3FC)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Check Cavite hazards, evacuation facilities, safe zones, and active alerts in one place.', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14.5, height: 1.5)),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    PrimaryButton(
                      label: 'Open live map',
                      icon: Icons.map_outlined,
                      expand: false,
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PublicMapScreen())),
                    ),
                    GlassButton(label: 'Register as resident', onPressed: () => Navigator.of(context).pushNamed('/register')),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: .16)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: const Color(0xFF34D399),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: const Color(0xFF34D399).withValues(alpha: .45), blurRadius: 0, spreadRadius: 4)],
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Live public readiness',
                              style: TextStyle(color: Color(0xFF93C5FD), fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: .18),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: .35)),
                            ),
                            child: const Text(
                              'OPERATIONAL',
                              style: TextStyle(color: Color(0xFFBBF7D0), fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: .6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _heroMetric('Hazards', metric(hazards)),
                          const SizedBox(width: 8),
                          _heroMetric('Facilities', metric(facilities)),
                          const SizedBox(width: 8),
                          _heroMetric('Alerts', _alertsFailed ? '–' : '${_alerts.length}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroMetric(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertStrip(Map<String, dynamic> alert) {
    final critical = str(alert, 'alert_level') == 'critical';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: critical ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showAlert(alert),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: critical ? Ui.red : Ui.amber, width: 4)),
            ),
            child: Row(
              children: [
                Icon(critical ? Icons.error_outline : Icons.campaign_outlined, color: critical ? Ui.red : Ui.amber),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(str(alert, 'title'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(str(alert, 'message'), style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
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
  }

  Widget _stat(IconData icon, String value, String note, List<Color> colors) {
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GradientTile(icon: icon, colors: colors, size: 38),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Ui.slate900),
          ),
          const SizedBox(height: 3),
          Text(
            note,
            style: const TextStyle(fontSize: 11.5, color: Ui.slate500, height: 1.35),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _section({required String kicker, required String title, String? body, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(kicker, rule: true),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Ui.slate900, height: 1.2, letterSpacing: -.5),
          ),
          if (body != null) ...[const SizedBox(height: 8), Text(body, style: const TextStyle(color: Ui.slate500, fontSize: 13.5))],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _feature(IconData icon, String title, String body, {List<Color> colors = kGradBlue}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GradientTile(icon: icon, colors: colors, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(body, style: const TextStyle(fontSize: 13, color: Ui.slate500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: kGradBlue),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Color(0x802563EB), blurRadius: 14, offset: Offset(0, 6), spreadRadius: -8)],
            ),
            child: Text(
              '$number',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Ui.line),
              ),
              child: Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq(this.question, this.answer, {this.open = false});

  final String question;
  final String answer;
  final bool open;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: open,
          title: Text(question, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(answer, style: const TextStyle(color: Ui.slate500, fontSize: 13))],
        ),
      ),
    );
  }
}
