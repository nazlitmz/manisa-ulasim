import 'package:flutter/foundation.dart';

import '../models/route_model.dart';
import '../models/stop_model.dart';
import '../services/database_service.dart';
import '../services/city_detection_service.dart';
import '../services/gtfs_service_facade.dart';
import '../services/city_database_manager.dart';

/// Rota seçeneği modeli
class RouteOption {
  final TransitRoute route;
  final Stop fromStop;
  final Stop toStop;
  final List<String> upcomingDepartures;
  final int estimatedDurationMinutes;

  RouteOption({
    required this.route,
    required this.fromStop,
    required this.toStop,
    required this.upcomingDepartures,
    required this.estimatedDurationMinutes,
  });

  String get formattedDuration {
    if (estimatedDurationMinutes < 60) return '$estimatedDurationMinutes dk';
    final hours = estimatedDurationMinutes ~/ 60;
    final minutes = estimatedDurationMinutes % 60;
    return '$hours sa $minutes dk';
  }

  String? get nextDeparture =>
      upcomingDepartures.isEmpty ? null : upcomingDepartures.first;

  bool get isDeparturePassed => upcomingDepartures.isEmpty;

  String get timeUntilDeparture {
    if (upcomingDepartures.isEmpty) return 'Sefer yok';
    try {
      final parts = upcomingDepartures.first.split(':');
      if (parts.length < 2) return upcomingDepartures.first;
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      final now = DateTime.now();
      final diff =
          DateTime(now.year, now.month, now.day, hour, minute).difference(now);
      if (diff.inMinutes < 1) return 'Şimdi';
      if (diff.inMinutes < 60) return '${diff.inMinutes} dk sonra';
      return '${diff.inHours} sa ${diff.inMinutes % 60} dk';
    } catch (e) {
      return upcomingDepartures.first;
    }
  }
}

/// Hat ve güzergah yönetimi.
/// GPS'e göre aktif şehir Manisa ise DatabaseService,
/// Kıbrıs/diğer ise GtfsService kullanılır.
class RoutesProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<TransitRoute> _allRoutes = [];
  List<TransitRoute> _filteredRoutes = [];
  List<RouteOption> _routeOptions = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';

  // Getters
  List<TransitRoute> get allRoutes => _allRoutes;
  List<TransitRoute> get filteredRoutes => _filteredRoutes;
  List<RouteOption> get routeOptions => _routeOptions;
  List<RouteOption> get validRouteOptions =>
      _routeOptions.where((o) => !o.isDeparturePassed).toList();
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;

  /// Aktif şehir Manisa mı?
  bool get _isManisa =>
      CityDetectionService.instance.currentCity == null ||
      CityDetectionService.instance.currentCity == SupportedCity.manisa;

  /// Tüm hatları yükle
  Future<void> loadAllRoutes() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (_isManisa) {
        _allRoutes = await _databaseService.getAllRoutes();
      } else {
        // Kıbrıs / diğer şehirler
        final raw = await GtfsService.instance.allRoutes();
        _allRoutes = raw
            .map((r) => TransitRoute(
                  routeId: r['route_id']?.toString() ?? '',
                  routeShortName: r['route_short_name']?.toString() ?? '',
                  routeLongName: r['route_long_name']?.toString() ?? '',
                  routeType: (r['route_type'] as num?)?.toInt() ?? 3,
                  routeColor: r['route_color']?.toString() ?? '',
                  routeTextColor: r['route_text_color']?.toString() ?? '',
                  isActive: (r['is_active'] as num?)?.toInt() == 1,
                ))
            .toList();
      }

      _allRoutes
          .sort((a, b) => _naturalCompare(a.routeShortName, b.routeShortName));
      _filteredRoutes = List.from(_allRoutes);
      debugPrint('📊 ${_allRoutes.length} hat yüklendi (sıralı)');
    } catch (e) {
      _error = 'Hatlar yüklenirken hata oluştu: $e';
      debugPrint('❌ $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Bir durağa gelen hatları getir
  Future<List<TransitRoute>> getRoutesForStop(String stopId) async {
    try {
      List<TransitRoute> routes;
      if (_isManisa) {
        routes = await _databaseService.getRoutesForStop(stopId);
      } else {
        final raw = await GtfsService.instance.routesForStop(stopId);
        routes = raw
            .map((r) => TransitRoute(
                  routeId: r['route_id']?.toString() ?? '',
                  routeShortName: r['route_short_name']?.toString() ?? '',
                  routeLongName: r['route_long_name']?.toString() ?? '',
                  routeType: (r['route_type'] as num?)?.toInt() ?? 3,
                  routeColor: r['route_color']?.toString() ?? '',
                  routeTextColor: r['route_text_color']?.toString() ?? '',
                  isActive: (r['is_active'] as num?)?.toInt() == 1,
                ))
            .toList();
      }
      routes
          .sort((a, b) => _naturalCompare(a.routeShortName, b.routeShortName));
      return routes;
    } catch (e) {
      debugPrint('❌ Durak hatları yüklenemedi: $e');
      return [];
    }
  }

  /// Hat ara
  void searchRoutes(String query) {
    _searchQuery = query;
    if (query.isEmpty) {
      _filteredRoutes = List.from(_allRoutes);
    } else {
      final q = _normalizeText(query);
      _filteredRoutes = _allRoutes.where((r) {
        return _normalizeText(r.routeShortName).contains(q) ||
            _normalizeText(r.routeLongName).contains(q);
      }).toList();
    }
    notifyListeners();
  }

  /// Şehir değişince önbelleği temizle
  Future<void> onCityChanged() async {
    _allRoutes = [];
    _filteredRoutes = [];
    _routeOptions = [];
    notifyListeners();
  }

  /// İki durak arasındaki güzergahları bul (sadece Manisa)
  Future<List<RouteOption>> findRoutesToDestination({
    required Stop fromStop,
    required Stop toStop,
  }) async {
    _isLoading = true;
    _error = null;
    _routeOptions = [];
    notifyListeners();

    try {
      List<TransitRoute> routes;
      if (_isManisa) {
        routes = await _databaseService.findRoutesBetweenStops(
          fromStop.stopId,
          toStop.stopId,
        );
      } else {
        final raw = await GtfsService.instance.planRoutes(
          fromLat: fromStop.latitude,
          fromLon: fromStop.longitude,
          toLat: toStop.latitude,
          toLon: toStop.longitude,
        );
        routes = raw.map((r) {
          final routeData = r['route'] as Map<String, dynamic>;
          return TransitRoute(
            routeId: routeData['route_id']?.toString() ?? '',
            routeShortName: routeData['route_short_name']?.toString() ?? '',
            routeLongName: routeData['route_long_name']?.toString() ?? '',
            routeType: (routeData['route_type'] as num?)?.toInt() ?? 3,
            routeColor: routeData['route_color']?.toString() ?? '',
            routeTextColor: routeData['route_text_color']?.toString() ?? '',
            isActive: true,
          );
        }).toList();
      }

      final now = DateTime.now();
      final List<RouteOption> activeOptions = [];
      final List<RouteOption> expiredOptions = [];

      for (final route in routes) {
        try {
          List<String> departures;
          if (_isManisa) {
            departures = await _databaseService.getUpcomingDeparturesForStop(
              route.routeId,
              fromStop.stopId,
            );
          } else {
            departures = await GtfsService.instance.upcomingArrivals(
              fromStop.stopId,
              routeId: route.routeId,
            );
          }

          final futureDepartures = <String>[];
          for (final time in departures) {
            if (futureDepartures.length >= 3) break;
            final formatted = _formatTimeString(time);
            if (formatted.isEmpty) continue;
            final parts = formatted.split(':');
            if (parts.length < 2) continue;
            final hour = int.tryParse(parts[0]);
            final minute = int.tryParse(parts[1]);
            if (hour == null || minute == null) continue;
            final dep = DateTime(now.year, now.month, now.day, hour, minute);
            if (dep.isAfter(now)) futureDepartures.add(formatted);
          }

          int duration = 15;
          if (_isManisa) {
            duration = await _databaseService.getEstimatedDuration(
              route.routeId,
              fromStop.stopId,
              toStop.stopId,
            );
          }

          final option = RouteOption(
            route: route,
            fromStop: fromStop,
            toStop: toStop,
            upcomingDepartures: futureDepartures,
            estimatedDurationMinutes: duration > 0 ? duration : 15,
          );

          if (futureDepartures.isNotEmpty) {
            activeOptions.add(option);
          } else {
            expiredOptions.add(option);
          }
        } catch (e) {
          debugPrint('❌ Hat ${route.routeShortName} işlenirken hata: $e');
        }
      }

      activeOptions.sort((a, b) =>
          a.estimatedDurationMinutes.compareTo(b.estimatedDurationMinutes));

      _routeOptions = [...activeOptions, ...expiredOptions];
    } catch (e) {
      _error = 'Güzergah bulunamadı: $e';
      debugPrint('❌ $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    return _routeOptions;
  }

  // ── Yardımcılar ──────────────────────────────────────────────────────────

  String _formatTimeString(String timeStr) {
    try {
      if (timeStr.isEmpty) return '';
      final parts = timeStr.trim().split(':');
      if (parts.length < 2) return '';
      var hours = int.tryParse(parts[0]) ?? 0;
      final minutes = int.tryParse(parts[1]) ?? 0;
      if (hours >= 24) hours = hours % 24;
      if (minutes < 0 || minutes > 59) return '';
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  int _naturalCompare(String a, String b) {
    final aNum = _extractNumber(a);
    final bNum = _extractNumber(b);
    final aPrefix = _extractPrefix(a);
    final bPrefix = _extractPrefix(b);
    if (aPrefix != bPrefix) {
      if (aPrefix.isEmpty && bPrefix.isNotEmpty) return -1;
      if (aPrefix.isNotEmpty && bPrefix.isEmpty) return 1;
      return aPrefix.compareTo(bPrefix);
    }
    if (aNum != null && bNum != null && aNum != bNum)
      return aNum.compareTo(bNum);
    if (aNum != null) return -1;
    if (bNum != null) return 1;
    return a.compareTo(b);
  }

  int? _extractNumber(String s) {
    final m = RegExp(r'(\d+)').firstMatch(s);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  String _extractPrefix(String s) {
    final m = RegExp(r'^([A-Za-zÇçĞğİıÖöŞşÜü]*)').firstMatch(s);
    return m != null ? m.group(1)!.toUpperCase() : '';
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

  void clearFilters() {
    _searchQuery = '';
    _filteredRoutes = List.from(_allRoutes);
    notifyListeners();
  }

  void clearRouteOptions() {
    _routeOptions = [];
    notifyListeners();
  }
}
