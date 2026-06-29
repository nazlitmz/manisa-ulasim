import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/user_location_model.dart';
import '../config/constants.dart';
import '../services/city_detection_service.dart';

/// Konum servisi provider'ı
/// Kullanıcının konumunu yönetir ve GPS'e göre şehri otomatik seçer
class LocationProvider extends ChangeNotifier {
  UserLocation? _currentLocation;
  LocationStatus _status = LocationStatus.initial;
  LocationPermissionStatus _permissionStatus = LocationPermissionStatus.unknown;
  String? _errorMessage;

  StreamSubscription<Position>? _positionStream;

  // Getters
  UserLocation? get currentLocation => _currentLocation;
  LocationStatus get status => _status;
  LocationPermissionStatus get permissionStatus => _permissionStatus;
  String? get errorMessage => _errorMessage;
  bool get hasLocation => _currentLocation != null && _currentLocation!.isValid;
  bool get isLoading => _status == LocationStatus.loading;

  /// Position getter - uyumluluk için
  Position? get currentPosition => _currentLocation != null
      ? Position(
          latitude: _currentLocation!.latitude,
          longitude: _currentLocation!.longitude,
          timestamp: _currentLocation!.timestamp,
          accuracy: _currentLocation!.accuracy ?? 0,
          altitude: _currentLocation!.altitude ?? 0,
          altitudeAccuracy: 0,
          heading: _currentLocation!.heading ?? 0,
          headingAccuracy: 0,
          speed: _currentLocation!.speed ?? 0,
          speedAccuracy: 0,
        )
      : null;

  /// Varsayılan konum (Manisa merkez)
  UserLocation get defaultLocation => UserLocation(
        latitude: AppConstants.defaultLatitude,
        longitude: AppConstants.defaultLongitude,
      );

  /// Aktif konum veya varsayılan
  UserLocation get effectiveLocation => _currentLocation ?? defaultLocation;

  /// Konum servisini başlat
  Future<void> initialize() async {
    await checkPermission();

    if (_permissionStatus == LocationPermissionStatus.granted ||
        _permissionStatus == LocationPermissionStatus.grantedLimited) {
      await getCurrentLocation();
    }
  }

  /// Konum iznini kontrol et
  Future<void> checkPermission() async {
    _status = LocationStatus.requestingPermission;
    notifyListeners();

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _status = LocationStatus.serviceDisabled;
        _errorMessage = 'Konum servisi kapalı. Lütfen ayarlardan açın.';
        notifyListeners();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      _permissionStatus = _mapPermission(permission);

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        _permissionStatus = _mapPermission(permission);
      }

      if (permission == LocationPermission.deniedForever) {
        _status = LocationStatus.permissionDenied;
        _errorMessage =
            'Konum izni kalıcı olarak reddedildi. Lütfen ayarlardan izin verin.';
        notifyListeners();
        return;
      }

      if (permission == LocationPermission.denied) {
        _status = LocationStatus.permissionDenied;
        _errorMessage = 'Konum izni reddedildi.';
        notifyListeners();
        return;
      }

      _status = LocationStatus.initial;
      notifyListeners();
    } catch (e) {
      _status = LocationStatus.error;
      _errorMessage = 'Konum izni kontrol edilemedi: $e';
      notifyListeners();
    }
  }

  /// Mevcut konumu al
  Future<void> getCurrentLocation() async {
    if (_permissionStatus != LocationPermissionStatus.granted &&
        _permissionStatus != LocationPermissionStatus.grantedLimited) {
      await checkPermission();
      if (_status == LocationStatus.permissionDenied ||
          _status == LocationStatus.serviceDisabled) {
        return;
      }
    }

    _status = LocationStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: AppConstants.locationTimeoutSeconds),
      );

      _currentLocation = UserLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        speed: position.speed,
        heading: position.heading,
        timestamp: position.timestamp,
      );

      _status = LocationStatus.success;
      _errorMessage = null;
      debugPrint('📍 Konum alındı: ${_currentLocation!.formattedCoordinates}');
      notifyListeners();

      // ✅ GPS'e göre şehri otomatik seç
      await _detectCity();
    } catch (e) {
      _status = LocationStatus.error;
      _errorMessage = 'Konum alınamadı: $e';
      debugPrint('❌ Konum hatası: $e');
      notifyListeners();
    }
  }

  /// Konum güncellemelerini dinlemeye başla
  void startLocationUpdates() {
    _positionStream?.cancel();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        _currentLocation = UserLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          altitude: position.altitude,
          accuracy: position.accuracy,
          speed: position.speed,
          heading: position.heading,
          timestamp: position.timestamp,
        );

        _status = LocationStatus.success;
        debugPrint(
            '📍 Konum güncellendi: ${_currentLocation!.formattedCoordinates}');
        notifyListeners();

        // ✅ Konum her güncellenince şehri kontrol et
        _detectCity();
      },
      onError: (error) {
        _errorMessage = 'Konum güncellenemedi: $error';
        debugPrint('❌ Konum güncelleme hatası: $error');
        notifyListeners();
      },
    );
  }

  /// GPS koordinatına göre şehri algıla ve GTFS verisini değiştir
  Future<void> _detectCity() async {
    if (_currentLocation == null) return;
    await CityDetectionService.instance.detectAndSwitch(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
    );
    // Şehir değişince provider'ı yenile (ekranlar yeniden build edilsin)
    notifyListeners();
  }

  /// Konum güncellemelerini durdur
  void stopLocationUpdates() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  /// Ayarlar sayfasını aç (izin için)
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  /// Uygulama ayarlarını aç (izin için)
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  /// Geolocator izin tipini kendi tipimize dönüştür
  LocationPermissionStatus _mapPermission(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.denied:
        return LocationPermissionStatus.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.deniedForever;
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.grantedLimited;
      case LocationPermission.always:
        return LocationPermissionStatus.granted;
      default:
        return LocationPermissionStatus.unknown;
    }
  }

  /// İki konum arasındaki mesafeyi hesapla (metre)
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Kullanıcının konumundan bir noktaya mesafe
  double? distanceFromUser(double lat, double lon) {
    if (!hasLocation) return null;
    return calculateDistance(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      lat,
      lon,
    );
  }

  @override
  void dispose() {
    stopLocationUpdates();
    super.dispose();
  }
}
