import 'dart:ui';

import 'package:disaster_map/core/geo.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('CaviteLock is idempotent', () {
    const lock = CaviteLock();
    for (final size in const [Size(411, 400), Size(411, 700), Size(900, 300), Size(300, 900)]) {
      for (final zoom in [6.0, 9.0, 10.0, 10.37, 12.0, 15.0]) {
        for (final center in const [LatLng(14.25, 120.86), LatLng(15, 121.5), LatLng(13, 120), LatLng(14.5, 120.42)]) {
          final camera = MapCamera(crs: const Epsg3857(), center: center, zoom: zoom, rotation: 0, nonRotatedSize: size, minZoom: 9, maxZoom: 19);
          final once = lock.constrain(camera)!;
          final twice = lock.constrain(once)!;
          expect(identical(twice, once) || twice == once, isTrue, reason: '$size z$zoom $center -> ${once.center} z${once.zoom} -> ${twice.center} z${twice.zoom}');
        }
      }
    }
  });
}
