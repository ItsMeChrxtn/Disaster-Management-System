import 'package:flutter/material.dart';

import 'ui.dart';

/// Labels, colours and option lists copied from dashboard.js / the admin views
/// so the app and the website describe records the same way.
class Domain {
  Domain._();

  // Same scale as the website: low = green, moderate = amber, high = orange, critical = red.
  static const Map<String, Color> riskColors = {'low': Color(0xFF059669), 'moderate': Color(0xFFD97706), 'high': Color(0xFFEA580C), 'critical': Color(0xFFDC2626)};

  /// Public map palette (map.js).
  static const Map<String, Color> publicRiskColors = riskColors;
  static const Map<String, Color> layerColors = {'flood': Color(0xFF2563EB), 'storm': Color(0xFF7C3AED), 'earthquake': Color(0xFFF97316)};

  /// One icon per map layer, used on the pins and in the layer list so residents match them by shape, not only colour.
  static const Map<String, IconData> layerIcons = {'flood': Icons.water_drop, 'storm': Icons.waves, 'earthquake': Icons.vibration, 'safeZones': Icons.shield, 'centers': Icons.home};

  static Color riskColor(String risk) => riskColors[risk] ?? Ui.orange;

  static String riskLabel(String risk) => const {'critical': 'High Risk', 'high': 'High Risk', 'moderate': 'Medium', 'low': 'Low'}[risk] ?? risk;

  static const List<String> standardHazardTypes = ['flood_zone', 'storm_surge_area', 'landslide', 'earthquake_area', 'fire'];
  static const Map<String, String> hazardTypeLabels = {
    'flood_zone': 'Flood',
    'storm_surge_area': 'Storm Surge',
    'landslide': 'Landslide',
    'earthquake_area': 'Earthquake',
    'fire': 'Fire',
    'high_risk_area': 'High Risk Area',
  };

  static String hazardTypeLabel(dynamic value) {
    final raw = (value ?? '').toString().trim();
    return hazardTypeLabels[raw.toLowerCase()] ?? (raw.isEmpty ? '-' : raw.replaceAll('_', ' '));
  }

  static const Map<String, String> riskOptions = {'low': 'Low risk', 'moderate': 'Moderate risk', 'high': 'High risk', 'critical': 'Critical risk'};

  static const Map<String, String> alertTypes = {
    'weather_alert': 'Weather Alert',
    'flood_alert': 'Flood Alert',
    'earthquake_alert': 'Earthquake Alert',
    'storm_surge_alert': 'Storm Surge Alert',
    'emergency_alert': 'Emergency Alert',
  };

  static const Map<String, String> alertLevels = {'info': 'Information', 'advisory': 'Advisory', 'warning': 'Warning', 'critical': 'Critical'};

  static Color alertLevelColor(String level) => switch (level) {
    'critical' => Ui.red,
    'warning' => Ui.amber,
    'advisory' => Ui.sky,
    _ => Ui.slate500,
  };

  static const Map<String, String> centerStatuses = {'available': 'Available', 'full': 'Full', 'closed': 'Closed', 'under_maintenance': 'Under maintenance'};

  /// [label, color, note] – centerStatusMeta in dashboard.js.
  static (String, Color, String) centerStatusMeta(String status) => switch (status) {
    'available' => ('Available', const Color(0xFF16A34A), 'Ready to receive evacuees'),
    'full' => ('Full', const Color(0xFFF97316), 'Capacity currently full'),
    'under_maintenance' => ('Maintenance', const Color(0xFF7C3AED), 'Facility under maintenance'),
    'closed' => ('Closed', const Color(0xFF64748B), 'Not currently operating'),
    _ => (status.isEmpty ? 'Unknown' : status, const Color(0xFF64748B), 'Status not specified'),
  };

  static const Map<String, String> reportTypes = {
    'hazard': 'Hazard Report',
    'alert': 'Alert Report',
    'historical_disaster': 'Historical Disaster Report',
    'evacuation_center': 'Evacuation Center Report',
  };

  static const List<String> disasterTypes = [
    'Flood',
    'Flash Flood',
    'Typhoon',
    'Tropical Cyclone',
    'Storm',
    'Severe Thunderstorm',
    'Storm Surge',
    'Tornado',
    'Earthquake',
    'Tsunami',
    'Volcanic Eruption',
    'Lahar',
    'Landslide',
    'Mudslide',
    'Sinkhole',
    'Fire',
    'Forest Fire',
    'Drought',
    'Extreme Heat',
    'El Nino',
    'La Nina',
    'Disease Outbreak',
    'Epidemic',
    'Pandemic',
    'Chemical Spill',
    'Oil Spill',
    'Industrial Accident',
    'Transport Accident',
    'Structural Collapse',
    'Power Outage',
    'Coastal Erosion',
    'Other',
  ];

  static const Map<String, String> routeModeLabels = {'driving': 'Car route', 'motorcycle': 'Motorcycle route', 'walking': 'Walking route', 'cycling': 'Bicycle route'};
  static const Map<String, List<String>> routeMetricLabels = {
    'driving': ['Car distance', 'Car time'],
    'motorcycle': ['Motorcycle distance', 'Motorcycle time'],
    'walking': ['Walking distance', 'Walking time'],
    'cycling': ['Bicycle distance', 'Bicycle time'],
  };

  static const Color safeZoneColor = Color(0xFF059669);
  static const Color centerColor = Color(0xFF2563EB);
  static const Color nearestColor = Color(0xFFD97706);
  static const Color draftColor = Color(0xFF6D28D9);
}

/// Bottom sheet used instead of Leaflet popups.
Future<void> showDetailSheet(
  BuildContext context, {
  required String title,
  String? kicker,
  Color color = Ui.indigo,
  IconData icon = Icons.info_outline,
  List<(String, String)> rows = const [],
  String? body,
  List<Widget> actions = const [],
}) {
  return showModalBottomSheet<void>(
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (kicker != null)
                        Text(
                          kicker.toUpperCase(),
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color, letterSpacing: .6),
                        ),
                      Text(
                        title,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Ui.slate900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (body != null) ...[const SizedBox(height: 12), Text(body, style: const TextStyle(fontSize: 13.5, color: Ui.slate900))],
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: rows
                        .map(
                          (row) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 110,
                                  child: Text(
                                    row.$1,
                                    style: const TextStyle(fontSize: 12.5, color: Ui.slate500, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Expanded(
                                  child: Text(row.$2, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[const SizedBox(height: 14), Wrap(spacing: 8, runSpacing: 8, children: actions)],
          ],
        ),
      ),
    ),
  );
}
