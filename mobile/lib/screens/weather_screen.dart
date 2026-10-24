import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/location.dart';
import '../core/ui.dart';

/// Weather monitoring module (loadWeatherModule in dashboard.js).
class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _usedDeviceLocation = false;
  String? _error;

  static const Map<String, (Color, Color)> _levelStyles = {
    'normal': (Color(0xFFECFDF5), Color(0xFF065F46)),
    'advisory': (Color(0xFFF0F9FF), Color(0xFF0C4A6E)),
    'warning': (Color(0xFFFFFBEB), Color(0xFF78350F)),
    'critical': (Color(0xFFFEF2F2), Color(0xFF7F1D1D)),
  };

  @override
  void initState() {
    super.initState();
    _load(true);
  }

  Future<void> _load(bool useDeviceLocation) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      LatLng? position;
      if (useDeviceLocation) position = await Location.tryCurrent();
      final query = position != null ? '?latitude=${position.latitude}&longitude=${position.longitude}' : '';
      final data = mapOf(await Api.instance.get('/weather/current$query'));
      if (!mounted) return;
      setState(() {
        _data = data;
        _usedDeviceLocation = position != null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Color _levelColor(String level) => switch (level) {
    'critical' => Ui.red,
    'warning' => const Color(0xFFD97706),
    'advisory' => Ui.sky,
    _ => Ui.emerald,
  };

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final current = mapOf(data?['current']);
    final location = mapOf(data?['location']);
    final advisories = mapOf(data?['advisories']).values.map(mapOf).toList();
    final level = str(data, 'warning_level', '-');
    final address = str(location, 'address', str(location, 'name'));

    return RefreshIndicator(
      onRefresh: () => _load(true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ModuleHeader(
            eyebrow: 'Weather command',
            title: 'Weather monitoring',
            subtitle: _loading
                ? 'Detecting your location...'
                : data == null
                ? 'Weather service unavailable.'
                : '$address · ${(dbl(location, 'latitude') ?? 0).toStringAsFixed(4)}, ${(dbl(location, 'longitude') ?? 0).toStringAsFixed(4)}',
            icon: Icons.cloud_outlined,
            actions: [BannerButton(label: _loading ? 'Updating...' : 'Refresh using my location', icon: Icons.my_location, onPressed: _loading ? null : () => _load(true))],
          ),
          const SizedBox(height: 16),
          if (_error != null) ErrorBanner(_error),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.15,
            children: [
              _tile(
                'Current weather',
                _loading ? 'Loading...' : str(current, 'condition', 'Unavailable'),
                data == null ? '' : '${(dbl(current, 'temperature_c') ?? 0).round()} C - Feels like ${(dbl(current, 'apparent_temperature_c') ?? 0).round()} C',
              ),
              _tile('Warning level', level.toUpperCase(), 'Highest derived advisory', valueColor: _levelColor(level)),
              _tile(
                'Humidity and clouds',
                data == null ? '-' : '${str(current, 'humidity_percent', '0')}%',
                data == null ? '' : 'Cloud cover ${str(current, 'cloud_cover_percent', '0')}% - Pressure ${(dbl(current, 'pressure_hpa') ?? 0).round()} hPa',
              ),
              _tile('Wind', data == null ? '-' : '${(dbl(current, 'wind_speed_kmh') ?? 0).round()} km/h', data == null ? '' : 'Gusts up to ${(dbl(current, 'wind_gust_kmh') ?? 0).round()} km/h'),
            ],
          ),
          const SizedBox(height: 14),
          for (final a in advisories) ...[
            Builder(
              builder: (context) {
                final style = _levelStyles[str(a, 'level')] ?? _levelStyles['normal']!;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: style.$1,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: style.$2.withValues(alpha: .15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              str(a, 'title'),
                              style: TextStyle(fontWeight: FontWeight.w800, color: style.$2),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .7), borderRadius: BorderRadius.circular(999)),
                            child: Text(
                              str(a, 'level').toUpperCase(),
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: style.$2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(str(a, 'message'), style: TextStyle(fontSize: 13, color: style.$2)),
                      if (a.containsKey('forecast_6h_mm')) ...[
                        const SizedBox(height: 8),
                        Text('6-hour rainfall: ${a['forecast_6h_mm']} mm - Maximum probability: ${a['max_probability_percent']}%', style: TextStyle(fontSize: 11.5, color: style.$2)),
                      ],
                      if (a.containsKey('maximum_gust_6h_kmh')) ...[
                        const SizedBox(height: 8),
                        Text('Maximum 6-hour gust: ${a['maximum_gust_6h_kmh']} km/h', style: TextStyle(fontSize: 11.5, color: style.$2)),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
          if (data != null)
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _usedDeviceLocation ? str(data, 'official_notice') : '${str(data, 'official_notice')} Device location was unavailable, so the default monitoring location was used.',
                    style: const TextStyle(fontSize: 12.5, color: Ui.slate500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Last updated: ${str(data, 'last_updated').replaceFirst('T', ' ')} ${str(location, 'timezone')} - Source: ${str(data, 'source')}',
                    style: const TextStyle(fontSize: 11.5, color: Ui.slate500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(String label, String value, String note, {Color? valueColor}) {
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Ui.slate500, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: valueColor ?? Ui.slate900),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            note,
            style: const TextStyle(fontSize: 11, color: Ui.slate500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
