import 'city_database_manager.dart';
import 'gtfs_importer.dart';
import 'gtfs_query_service.dart';

/// Tek giriş noktası — tüm uygulama bu sınıfı kullanır.
///
/// ─────────────────────────────────────────────────────
/// pubspec.yaml'a eklenecekler:
/// ─────────────────────────────────────────────────────
///   dependencies:
///     sqflite: ^2.3.2
///     path: ^1.9.0
///     csv: ^6.0.0
///
///   flutter:
///     assets:
///       - assets/gtfs/manisa/
///       - assets/gtfs/cyprus/
///       - assets/gtfs/izmir/
/// ─────────────────────────────────────────────────────
///
/// Klasör yapısı:
///   assets/
///   └── gtfs/
///       ├── manisa/
///       │   ├── stops.txt
///       │   ├── routes.txt
///       │   ├── trips.txt
///       │   ├── stop_times.txt
///       │   ├── shapes.txt
///       │   ├── calendar.txt
///       │   ├── frequencies.txt
///       │   └── ...
///       └── cyprus/
///           ├── agency.txt
///           ├── stops.txt
///           ├── routes.txt
///           ├── trips.txt
///           ├── stop_times.txt
///           ├── shapes.txt
///           ├── calendar.txt
///           ├── calendar_dates.txt
///           ├── networks.txt
///           ├── areas.txt
///           ├── stop_areas.txt
///           ├── route_networks.txt
///           ├── fare_media.txt
///           ├── fare_products.txt
///           ├── fare_leg_rules.txt
///           ├── rider_categories.txt
///           └── feed_info.txt
/// ─────────────────────────────────────────────────────
class GtfsService {
  static final GtfsService instance = GtfsService._internal();
  GtfsService._internal();

  final _manager = CityDatabaseManager.instance;
  final _query = GtfsQueryService.instance;

  SupportedCity? get currentCity => _manager.currentCity;

  // ==================== ŞEHİR SEÇME ====================

  /// Şehri değiştir ve GTFS verisini yükle.
  ///
  /// Örnek:
  ///   await GtfsService.instance.selectCity(SupportedCity.cyprus);
  Future<void> selectCity(SupportedCity city,
      {bool forceReload = false}) async {
    await _manager.switchCity(city);
    final importer = GtfsImporter(city);
    await importer.importAll(forceReload: forceReload);
  }

  // ==================== KULLANIM ÖRNEKLERİ ====================

  /// Örnek 1: Yakındaki durakları getir
  ///
  ///   final stops = await GtfsService.instance.nearbyStops(
  ///     lat: 35.1856, lon: 33.3823,
  ///   );
  Future<List<Map<String, dynamic>>> nearbyStops({
    required double lat,
    required double lon,
    double radiusMeters = 500,
  }) {
    return _query.getNearbyStops(lat, lon, radiusMeters: radiusMeters);
  }

  /// Tüm durakları döner
  Future<List<Map<String, dynamic>>> allStops() {
    return _query.getAllStops();
  }

  /// Örnek 2: Belirli bir durağa yaklaşan seferler
  ///
  ///   final times = await GtfsService.instance.upcomingArrivals('99044');
  ///   // ['08:30', '09:00', '09:30', ...]
  Future<List<String>> upcomingArrivals(String stopId, {String? routeId}) {
    return _query.getUpcomingArrivals(stopId, routeId: routeId);
  }

  /// Örnek 3: İki nokta arasında rota planla
  ///
  ///   final routes = await GtfsService.instance.planRoutes(
  ///     fromLat: 35.185, fromLon: 33.382,
  ///     toLat:   35.195, toLon:   33.362,
  ///   );
  ///   for (final r in routes) {
  ///     print('${r['route']['route_short_name']} → '
  ///           'Biniş: ${r['boarding_stop']['stop_name']} '
  ///           'İniş: ${r['alighting_stop']['stop_name']} '
  ///           'Sonraki: ${r['next_departures']}');
  ///   }
  Future<List<Map<String, dynamic>>> planRoutes({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    double walkRadius = 800,
  }) {
    return _query.planRoutes(
      fromLat: fromLat,
      fromLon: fromLon,
      toLat: toLat,
      toLon: toLon,
      walkRadius: walkRadius,
    );
  }

  /// Örnek 4: Bir hattın tüm durakları
  ///
  ///   final stops = await GtfsService.instance.stopsForRoute(
  ///     routeId: '01006', direction: 0,
  ///   );
  Future<List<Map<String, dynamic>>> stopsForRoute({
    required String routeId,
    int direction = 0,
  }) {
    return _query.getStopsForRoute(routeId, direction: direction);
  }

  /// Bir hattın shape (harita çizgisi) koordinatları.
  /// routeId ve direction verilir; trips tablosundan shapeId bulunur.
  ///
  ///   final shape = await GtfsService.instance.shapeForRoute(
  ///     routeId: '01006', direction: 0,
  ///   );
  ///   // [{'shape_pt_lat': 35.22..., 'shape_pt_lon': 33.32...}, ...]
  Future<List<Map<String, dynamic>>> shapeForRoute({
    required String routeId,
    int direction = 0,
  }) {
    return _query.getShapeForRoute(routeId, direction: direction);
  }

  /// Örnek 6: Bir hat için varsayılan ücret
  ///
  ///   final fare = await GtfsService.instance.fareForRoute('01006');
  ///   // 50.0 (TRY)
  Future<double?> fareForRoute(String routeId) {
    return _query.getDefaultFareForRoute(routeId);
  }

  /// Tüm aktif hatlar
  Future<List<Map<String, dynamic>>> allRoutes() {
    return _query.getAllActiveRoutes();
  }

  /// Bir durağa uğrayan hatlar
  Future<List<Map<String, dynamic>>> routesForStop(String stopId) {
    return _query.getRoutesForStop(stopId);
  }

  /// Örnek 7: Tüm aktif hatlar
  Future<List<Map<String, dynamic>>> allRoutesList() {
    return _query.getAllActiveRoutes();
  }

  /// Örnek 8: Bir durağa uğrayan hatlar
  Future<List<Map<String, dynamic>>> routesAtStop(String stopId) {
    return _query.getRoutesForStop(stopId);
  }

  /// Uygulama kapanınca çağır
  Future<void> dispose() async {
    await _manager.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// main.dart'ta kullanım örneği:
// ─────────────────────────────────────────────────────────────────────────────
//
// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//
//   // Uygulama açılışında şehri seç (kullanıcının tercihine göre)
//   await GtfsService.instance.selectCity(SupportedCity.cyprus);
//
//   runApp(const MyApp());
// }
//
// // Şehir değiştirme (örn. settings ekranında):
// await GtfsService.instance.selectCity(SupportedCity.manisa);
//
// ─────────────────────────────────────────────────────────────────────────────
// Durak ekranında yaklaşan seferler:
// ─────────────────────────────────────────────────────────────────────────────
//
// class StopDetailScreen extends StatefulWidget { ... }
//
// Future<void> _loadArrivals() async {
//   final times = await GtfsService.instance.upcomingArrivals(widget.stopId);
//   setState(() => _arrivals = times);
// }
//
// // Widget:
// ListView.builder(
//   itemCount: _arrivals.length,
//   itemBuilder: (ctx, i) => ListTile(
//     leading: const Icon(Icons.directions_bus),
//     title: Text(_arrivals[i]),
//   ),
// )
// ─────────────────────────────────────────────────────────────────────────────
