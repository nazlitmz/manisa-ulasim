import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/stop_model.dart';
import '../models/route_model.dart';

/// Favori yer modeli
class FavoritePlace {
  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final DateTime addedAt;

  FavoritePlace({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'latitude': latitude,
        'longitude': longitude,
        'addedAt': addedAt.toIso8601String(),
      };

  factory FavoritePlace.fromJson(Map<String, dynamic> json) => FavoritePlace(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        latitude: json['latitude'] as double,
        longitude: json['longitude'] as double,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );
}

/// Favori durak modeli
class FavoriteStop {
  final String stopId;
  final String stopName;
  final double latitude;
  final double longitude;
  final DateTime addedAt;

  FavoriteStop({
    required this.stopId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'stopId': stopId,
        'stopName': stopName,
        'latitude': latitude,
        'longitude': longitude,
        'addedAt': addedAt.toIso8601String(),
      };

  factory FavoriteStop.fromJson(Map<String, dynamic> json) => FavoriteStop(
        stopId: json['stopId'] as String,
        stopName: json['stopName'] as String,
        latitude: json['latitude'] as double,
        longitude: json['longitude'] as double,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );

  factory FavoriteStop.fromStop(Stop stop) => FavoriteStop(
        stopId: stop.stopId,
        stopName: stop.stopName,
        latitude: stop.latitude,
        longitude: stop.longitude,
      );
}

/// Favori hat modeli
class FavoriteRoute {
  final String routeId;
  final String routeShortName;
  final String routeLongName;
  final String? routeColor;
  final DateTime addedAt;

  FavoriteRoute({
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    this.routeColor,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'routeId': routeId,
        'routeShortName': routeShortName,
        'routeLongName': routeLongName,
        'routeColor': routeColor,
        'addedAt': addedAt.toIso8601String(),
      };

  factory FavoriteRoute.fromJson(Map<String, dynamic> json) => FavoriteRoute(
        routeId: json['routeId'] as String,
        routeShortName: json['routeShortName'] as String,
        routeLongName: json['routeLongName'] as String,
        routeColor: json['routeColor'] as String?,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );

  factory FavoriteRoute.fromRoute(TransitRoute route) => FavoriteRoute(
        routeId: route.routeId,
        routeShortName: route.routeShortName,
        routeLongName: route.routeLongName,
        routeColor: route.routeColor,
      );
}

/// Favoriler Provider
class FavoritesProvider extends ChangeNotifier {
  static const String _stopsKey = 'favorite_stops';
  static const String _routesKey = 'favorite_routes';
  static const String _placesKey = 'favorite_places';

  List<FavoriteStop> _favoriteStops = [];
  List<FavoriteRoute> _favoriteRoutes = [];
  List<FavoritePlace> _favoritePlaces = [];
  bool _isLoaded = false;

  List<FavoriteStop> get favoriteStops => List.unmodifiable(_favoriteStops);
  List<FavoriteRoute> get favoriteRoutes => List.unmodifiable(_favoriteRoutes);
  List<FavoritePlace> get favoritePlaces => List.unmodifiable(_favoritePlaces);
  bool get isLoaded => _isLoaded;

  bool get hasFavorites =>
      _favoriteStops.isNotEmpty ||
      _favoriteRoutes.isNotEmpty ||
      _favoritePlaces.isNotEmpty;

  int get totalFavoritesCount =>
      _favoriteStops.length + _favoriteRoutes.length + _favoritePlaces.length;

  Future<void> loadFavorites() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      final stopsJson = prefs.getString(_stopsKey);
      if (stopsJson != null) {
        final List<dynamic> decoded = jsonDecode(stopsJson);
        _favoriteStops = decoded.map((e) => FavoriteStop.fromJson(e)).toList();
      }

      final routesJson = prefs.getString(_routesKey);
      if (routesJson != null) {
        final List<dynamic> decoded = jsonDecode(routesJson);
        _favoriteRoutes =
            decoded.map((e) => FavoriteRoute.fromJson(e)).toList();
      }

      final placesJson = prefs.getString(_placesKey);
      if (placesJson != null) {
        final List<dynamic> decoded = jsonDecode(placesJson);
        _favoritePlaces =
            decoded.map((e) => FavoritePlace.fromJson(e)).toList();
      }

      _isLoaded = true;
      debugPrint(
          '✅ Favoriler yüklendi: ${_favoriteStops.length} durak, ${_favoriteRoutes.length} hat, ${_favoritePlaces.length} yer');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Favoriler yüklenirken hata: $e');
    }
  }

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stopsKey,
          jsonEncode(_favoriteStops.map((e) => e.toJson()).toList()));
      await prefs.setString(_routesKey,
          jsonEncode(_favoriteRoutes.map((e) => e.toJson()).toList()));
      await prefs.setString(_placesKey,
          jsonEncode(_favoritePlaces.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('❌ Favoriler kaydedilirken hata: $e');
    }
  }

  // DURAK FAVORİLERİ
  bool isStopFavorite(String stopId) =>
      _favoriteStops.any((s) => s.stopId == stopId);

  Future<void> addStopToFavorites(Stop stop) async {
    if (isStopFavorite(stop.stopId)) return;
    _favoriteStops.insert(0, FavoriteStop.fromStop(stop));
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> removeStopFromFavorites(String stopId) async {
    _favoriteStops.removeWhere((s) => s.stopId == stopId);
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> toggleStopFavorite(Stop stop) async {
    if (isStopFavorite(stop.stopId)) {
      await removeStopFromFavorites(stop.stopId);
    } else {
      await addStopToFavorites(stop);
    }
  }

  // HAT FAVORİLERİ
  bool isRouteFavorite(String routeId) =>
      _favoriteRoutes.any((r) => r.routeId == routeId);

  Future<void> addRouteToFavorites(TransitRoute route) async {
    if (isRouteFavorite(route.routeId)) return;
    _favoriteRoutes.insert(0, FavoriteRoute.fromRoute(route));
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> removeRouteFromFavorites(String routeId) async {
    _favoriteRoutes.removeWhere((r) => r.routeId == routeId);
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> toggleRouteFavorite(TransitRoute route) async {
    if (isRouteFavorite(route.routeId)) {
      await removeRouteFromFavorites(route.routeId);
    } else {
      await addRouteToFavorites(route);
    }
  }

  // YER FAVORİLERİ
  bool isPlaceFavorite(String placeId) =>
      _favoritePlaces.any((p) => p.id == placeId);

  Future<void> addPlaceToFavorites({
    required String id,
    required String name,
    required String category,
    required double latitude,
    required double longitude,
  }) async {
    if (isPlaceFavorite(id)) return;
    _favoritePlaces.insert(
        0,
        FavoritePlace(
          id: id,
          name: name,
          category: category,
          latitude: latitude,
          longitude: longitude,
        ));
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> removePlaceFromFavorites(String placeId) async {
    _favoritePlaces.removeWhere((p) => p.id == placeId);
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> togglePlaceFavorite({
    required String id,
    required String name,
    required String category,
    required double latitude,
    required double longitude,
  }) async {
    if (isPlaceFavorite(id)) {
      await removePlaceFromFavorites(id);
    } else {
      await addPlaceToFavorites(
          id: id,
          name: name,
          category: category,
          latitude: latitude,
          longitude: longitude);
    }
  }

  Future<void> clearAllFavorites() async {
    _favoriteStops.clear();
    _favoriteRoutes.clear();
    _favoritePlaces.clear();
    notifyListeners();
    await _saveFavorites();
  }
}
