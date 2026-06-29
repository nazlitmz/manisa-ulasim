import 'package:flutter/foundation.dart';

import 'city_database_manager.dart';
import 'gtfs_service_facade.dart';

/// GPS koordinatına göre otomatik şehir algılar ve GTFS verisini yükler.
///
/// Kullanım:
///   await CityDetectionService.instance.detectAndSwitch(lat, lon);
class CityDetectionService {
  static final CityDetectionService instance = CityDetectionService._();
  CityDetectionService._();

  SupportedCity? _lastDetectedCity;
  SupportedCity? get currentCity => _lastDetectedCity;

  // ── Şehir sınır kutuları ──────────────────────────────────────────────────

  static const _bounds = {
    SupportedCity.manisa: _BBox(
      minLat: 38.0,
      maxLat: 39.5,
      minLon: 26.5,
      maxLon: 28.5,
    ),
    SupportedCity.cyprus: _BBox(
      minLat: 34.5,
      maxLat: 35.8,
      minLon: 32.0,
      maxLon: 34.7,
    ),
    SupportedCity.izmir: _BBox(
      minLat: 37.5,
      maxLat: 38.8,
      minLon: 26.3,
      maxLon: 27.8,
    ),
  };

  /// Koordinata göre hangi şehirde olduğunu döner.
  /// Hiçbir şehir sınırında değilse null döner.
  SupportedCity? detectCity(double lat, double lon) {
    for (final entry in _bounds.entries) {
      if (entry.value.contains(lat, lon)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Şehri algıla ve gerekirse GTFS verisini değiştir.
  ///
  /// Aynı şehrdeyse tekrar yükleme yapmaz.
  /// Tanımlanmamış bir bölgedeyse mevcut şehri korur.
  Future<void> detectAndSwitch(double lat, double lon) async {
    final detected = detectCity(lat, lon);

    if (detected == null) {
      debugPrint('📍 ($lat, $lon) tanımlı bir şehir sınırında değil');
      return;
    }

    if (detected == _lastDetectedCity) {
      debugPrint('✅ Zaten ${detected.displayName} modunda');
      return;
    }

    debugPrint(
        '🌍 Şehir değişiyor: ${_lastDetectedCity?.displayName ?? '?'} → ${detected.displayName}');
    _lastDetectedCity = detected;

    await GtfsService.instance.selectCity(detected);
    debugPrint('✅ ${detected.displayName} GTFS aktif');
  }
}

/// Basit koordinat sınır kutusu
class _BBox {
  final double minLat, maxLat, minLon, maxLon;
  const _BBox({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  bool contains(double lat, double lon) =>
      lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
}
