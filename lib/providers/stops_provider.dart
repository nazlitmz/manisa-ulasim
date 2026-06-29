import 'package:flutter/foundation.dart';
import 'package:haversine_distance/haversine_distance.dart';

import '../models/stop_model.dart';
import '../services/database_service.dart';
import '../services/city_detection_service.dart';
import '../services/gtfs_service_facade.dart';
import '../services/city_database_manager.dart';

/// Durak verilerini yöneten provider.
/// GPS'e göre aktif şehir Manisa ise DatabaseService,
/// Kıbrıs/diğer ise GtfsService kullanılır.
class StopsProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  final HaversineDistance _haversine = HaversineDistance();

  List<Stop> _allStops = [];
  List<Stop> _nearbyStops = [];
  List<Stop> _searchResults = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';

  // Getters
  List<Stop> get allStops => _allStops;
  List<Stop> get nearbyStops => _nearbyStops;
  List<Stop> get searchResults => _searchResults;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;

  /// Aktif şehir Manisa mı?
  bool get _isManisa =>
      CityDetectionService.instance.currentCity == null ||
      CityDetectionService.instance.currentCity == SupportedCity.manisa;

  /// Tüm durakları yükle
  Future<void> loadAllStops() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (_isManisa) {
        _allStops = await _databaseService.getAllStops();
      } else {
        // Kıbrıs veya diğer şehirler — GtfsService üzerinden
        final raw = await GtfsService.instance.allStops();
        _allStops = raw
            .map((s) => Stop(
                  stopId: s['stop_id']?.toString() ?? '',
                  stopCode: s['stop_code']?.toString() ?? '',
                  stopName: s['stop_name']?.toString() ?? '',
                  latitude: (s['stop_lat'] as num).toDouble(),
                  longitude: (s['stop_lon'] as num).toDouble(),
                ))
            .toList();
      }
      debugPrint('📊 ${_allStops.length} durak yüklendi');
    } catch (e) {
      _error = 'Duraklar yüklenirken hata oluştu: $e';
      debugPrint('❌ $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Yakındaki durakları bul
  Future<void> findNearbyStops({
    required double latitude,
    required double longitude,
    double radiusMeters = 500,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (_isManisa) {
        // ── Manisa: mevcut sistem ───────────────────────────────────────
        if (_allStops.isEmpty) await loadAllStops();

        final userLocation = Location(latitude, longitude);
        final stopsInRadius = <Stop>[];

        for (final stop in _allStops) {
          final stopLocation = Location(stop.latitude, stop.longitude);
          final distance = _haversine.haversine(
            userLocation,
            stopLocation,
            Unit.METER,
          );
          if (distance <= radiusMeters) {
            stopsInRadius.add(stop.copyWith(distanceFromUser: distance));
          }
        }

        stopsInRadius.sort((a, b) => (a.distanceFromUser ?? double.infinity)
            .compareTo(b.distanceFromUser ?? double.infinity));

        final stopsWithRoutes = <Stop>[];
        for (final stop in stopsInRadius) {
          final routes = await _databaseService.getRoutesForStop(stop.stopId);
          if (routes.isNotEmpty) stopsWithRoutes.add(stop);
        }

        _nearbyStops = stopsWithRoutes;
      } else {
        // ── Kıbrıs / diğer şehirler: GtfsService ──────────────────────
        final raw = await GtfsService.instance.nearbyStops(
          lat: latitude,
          lon: longitude,
          radiusMeters: radiusMeters,
        );

        _nearbyStops = raw.map((s) {
          final dist = (s['distance_m'] as num?)?.toDouble();
          return Stop(
            stopId: s['stop_id']?.toString() ?? '',
            stopCode: s['stop_code']?.toString() ?? '',
            stopName: s['stop_name']?.toString() ?? '',
            latitude: (s['stop_lat'] as num).toDouble(),
            longitude: (s['stop_lon'] as num).toDouble(),
            distanceFromUser: dist,
          );
        }).toList();
      }

      debugPrint(
          '📍 $radiusMeters m içinde ${_nearbyStops.length} durak bulundu');
    } catch (e) {
      _error = 'Yakın duraklar bulunamadı: $e';
      debugPrint('❌ $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Durak ara
  void searchStops(String query) {
    _searchQuery = query;

    if (query.isEmpty || query.length < 2) {
      _searchResults = [];
    } else {
      final normalizedQuery = _normalizeText(query);
      _searchResults = _allStops
          .where(
              (stop) => _normalizeText(stop.stopName).contains(normalizedQuery))
          .take(20)
          .toList();
    }

    notifyListeners();
  }

  /// Şehir değişince önbelleği temizle ve yeniden yükle
  Future<void> onCityChanged() async {
    _allStops = [];
    _nearbyStops = [];
    _searchResults = [];
    notifyListeners();
  }

  String _normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll('İ', 'i')
        .replaceAll('Ğ', 'g')
        .replaceAll('Ü', 'u')
        .replaceAll('Ş', 's')
        .replaceAll('Ö', 'o')
        .replaceAll('Ç', 'c');
  }

  Stop? getStopById(String stopId) {
    try {
      return _allStops.firstWhere((stop) => stop.stopId == stopId);
    } catch (e) {
      return null;
    }
  }

  void clearSearch() {
    _searchQuery = '';
    _searchResults = [];
    notifyListeners();
  }

  void clearSearchResults() => clearSearch();
}
