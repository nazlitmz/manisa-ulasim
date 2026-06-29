import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_model.dart';
import '../models/stop_model.dart';
import '../models/vehicle_location_model.dart';
import '../services/database_service.dart';
import '../services/vehicle_service.dart';
import '../services/city_detection_service.dart';
import '../services/city_database_manager.dart';
import '../services/gtfs_service_facade.dart';

class RouteMapController extends ChangeNotifier {
  final TransitRoute route;
  final DatabaseService _db = DatabaseService();
  final VehicleService _vehicleService = VehicleService();

  RouteMapController({required this.route});

  bool isLoading = true;
  String? error;

  List<LatLng> outboundPoints = [];
  List<LatLng> inboundPoints = [];
  List<Stop> outboundStops = [];
  List<Stop> inboundStops = [];
  List<VehicleLocation> vehicles = [];

  int selectedDirection = 1;
  bool showStops = true;
  bool showVehicles = true;
  Stop? selectedStop;
  VehicleLocation? selectedVehicle;

  Map<String, String> vehicleStopMapping = {};
  Map<String, LatLng> vehicleSnappedPositions = {};
  Map<String, double> vehicleBearings = {};
  Map<String, int> vehicleDirectionMapping = {};

  Timer? _vehicleTimer;

  bool get _isManisa =>
      CityDetectionService.instance.currentCity == null ||
      CityDetectionService.instance.currentCity == SupportedCity.manisa;

  List<LatLng> get currentPoints =>
      selectedDirection == 1 ? outboundPoints : inboundPoints;

  List<Stop> get currentStops =>
      selectedDirection == 1 ? outboundStops : inboundStops;

  List<VehicleLocation> get currentVehicles => vehicles
      .where((v) => vehicleDirectionMapping[v.id] == selectedDirection)
      .toList();

  Future<void> init() async {
    await loadRouteData();
    _startVehicleUpdates();
  }

  @override
  void dispose() {
    _vehicleTimer?.cancel();
    super.dispose();
  }

  Future<void> loadRouteData() async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      if (_isManisa) {
        await _loadManisaData();
      } else {
        await _loadCyprusData();
      }
    } catch (e) {
      error = 'Güzergah yüklenirken hata oluştu: $e';
      isLoading = false;
      notifyListeners();
    }
  }

  // ── Manisa (mevcut sistem) ─────────────────────────────────────
  Future<void> _loadManisaData() async {
    final ob = await _db.getShapeForRoute(route.routeId, direction: 1);
    outboundPoints = ob.map((p) => LatLng(p['lat']!, p['lon']!)).toList();

    final ib = await _db.getShapeForRoute(route.routeId, direction: 2);
    inboundPoints = ib.map((p) => LatLng(p['lat']!, p['lon']!)).toList();

    outboundStops = _dedup(
        await _db.getStopsForRouteDirection(route.routeId, direction: 1));
    inboundStops = _dedup(
        await _db.getStopsForRouteDirection(route.routeId, direction: 2));

    if (outboundPoints.isEmpty && inboundPoints.isEmpty) {
      error = 'Bu hat için güzergah verisi bulunamadı.';
      isLoading = false;
      notifyListeners();
      return;
    }

    if (outboundPoints.isEmpty && inboundPoints.isNotEmpty) {
      selectedDirection = 2;
    }

    isLoading = false;
    _snapAll();
    notifyListeners();
  }

  // ── Kıbrıs (GtfsService) ───────────────────────────────────────
  Future<void> _loadCyprusData() async {
    // Direction 0 = gidiş, direction 1 = dönüş (GTFS standardı)
    final obRaw =
        await GtfsService.instance.shapeForRoute(routeId: route.routeId);
    outboundPoints = obRaw
        .map((p) => LatLng(
              (p['shape_pt_lat'] as num).toDouble(),
              (p['shape_pt_lon'] as num).toDouble(),
            ))
        .toList();

    // Dönüş yönü için direction=1 ile dene
    // Kıbrıs'ta çoğu hat tek yönlü olabilir, boş gelirse sorun yok
    inboundPoints = [];

    // Duraklar
    final obStopsRaw = await GtfsService.instance
        .stopsForRoute(routeId: route.routeId, direction: 0);
    outboundStops = _dedup(obStopsRaw
        .map((s) => Stop(
              stopId: s['stop_id']?.toString() ?? '',
              stopName: s['stop_name']?.toString() ?? '',
              latitude: (s['stop_lat'] as num).toDouble(),
              longitude: (s['stop_lon'] as num).toDouble(),
            ))
        .toList());

    final ibStopsRaw = await GtfsService.instance
        .stopsForRoute(routeId: route.routeId, direction: 1);
    inboundStops = _dedup(ibStopsRaw
        .map((s) => Stop(
              stopId: s['stop_id']?.toString() ?? '',
              stopName: s['stop_name']?.toString() ?? '',
              latitude: (s['stop_lat'] as num).toDouble(),
              longitude: (s['stop_lon'] as num).toDouble(),
            ))
        .toList());

    // Shape yoksa durak koordinatlarından oluştur
    if (outboundPoints.isEmpty && outboundStops.isNotEmpty) {
      outboundPoints =
          outboundStops.map((s) => LatLng(s.latitude, s.longitude)).toList();
      debugPrint(
          '⚠️ ${route.routeId}: Shape yok, durak koordinatlarından çizgi oluşturuldu');
    }
    if (inboundPoints.isEmpty && inboundStops.isNotEmpty) {
      inboundPoints =
          inboundStops.map((s) => LatLng(s.latitude, s.longitude)).toList();
    }

    if (outboundPoints.isEmpty && inboundPoints.isEmpty) {
      error = 'Bu hat için güzergah verisi bulunamadı.';
      isLoading = false;
      notifyListeners();
      return;
    }

    if (outboundPoints.isEmpty && inboundPoints.isNotEmpty) {
      selectedDirection = 2;
    }

    isLoading = false;
    _snapAll();
    notifyListeners();
  }

  void _startVehicleUpdates() {
    // Kıbrıs'ta araç takibi yok
    if (!_isManisa) return;
    _loadVehicles();
    _vehicleTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadVehicles(),
    );
  }

  Future<void> _loadVehicles() async {
    try {
      final fresh = await _vehicleService.getVehiclesForRoute(route.routeId);
      vehicles = fresh;
      _snapAll();
      notifyListeners();
    } catch (e) {
      debugPrint('Araç verileri yüklenemedi: $e');
    }
  }

  void _snapAll() {
    _snapVehiclesToRoute();
    _assignVehiclesToNearestStops();
  }

  void _snapVehiclesToRoute() {
    vehicleSnappedPositions.clear();
    vehicleBearings.clear();
    vehicleDirectionMapping.clear();

    for (final v in vehicles) {
      final vPos = LatLng(v.gps.latitude, v.gps.longitude);
      LatLng? bestSnapped;
      double? bestBearing;
      double bestDist = double.infinity;
      int bestDirection = 1;

      final directions = <int, List<LatLng>>{
        1: outboundPoints,
        2: inboundPoints,
      };

      for (final entry in directions.entries) {
        final dir = entry.key;
        final routePoints = entry.value;
        if (routePoints.isEmpty) continue;

        for (int i = 0; i < routePoints.length - 1; i++) {
          final proj =
              _projectOntoSegment(vPos, routePoints[i], routePoints[i + 1]);
          final d = _haversineMeters(
              vPos.latitude, vPos.longitude, proj.latitude, proj.longitude);
          if (d < bestDist) {
            bestDist = d;
            bestSnapped = proj;
            bestBearing = _bearing(routePoints[i], routePoints[i + 1]);
            bestDirection = dir;
          }
        }
      }

      if (bestSnapped != null && bestDist < 200.0) {
        vehicleSnappedPositions[v.id] = bestSnapped;
        vehicleBearings[v.id] = bestBearing ?? 0;
      } else {
        vehicleSnappedPositions[v.id] = vPos;
        for (final entry in directions.entries) {
          final dir = entry.key;
          final routePoints = entry.value;
          if (routePoints.isEmpty) continue;
          int closest = 0;
          double md = double.infinity;
          for (int i = 0; i < routePoints.length; i++) {
            final d = _haversineMeters(vPos.latitude, vPos.longitude,
                routePoints[i].latitude, routePoints[i].longitude);
            if (d < md) {
              md = d;
              closest = i;
            }
          }
          if (md < bestDist) {
            bestDist = md;
            bestDirection = dir;
            if (closest < routePoints.length - 1) {
              vehicleBearings[v.id] =
                  _bearing(routePoints[closest], routePoints[closest + 1]);
            } else if (closest > 0) {
              vehicleBearings[v.id] =
                  _bearing(routePoints[closest - 1], routePoints[closest]);
            }
          }
        }
      }

      vehicleDirectionMapping[v.id] = bestDirection;
    }
  }

  void _assignVehiclesToNearestStops() {
    vehicleStopMapping.clear();

    for (final v in vehicles) {
      final dir = vehicleDirectionMapping[v.id] ?? 1;
      final stopsForDir = dir == 1 ? outboundStops : inboundStops;
      final stopsToSearch = stopsForDir.isNotEmpty
          ? stopsForDir
          : [...outboundStops, ...inboundStops];

      Stop? nearest;
      double minDist = double.infinity;

      for (final s in stopsToSearch) {
        final d = _haversineMeters(
            v.gps.latitude, v.gps.longitude, s.latitude, s.longitude);
        if (d < minDist) {
          minDist = d;
          nearest = s;
        }
      }

      if (nearest != null && minDist < 200.0) {
        vehicleStopMapping[v.id] = nearest.stopId;
      }
    }
  }

  void setDirection(int dir) {
    selectedDirection = dir;
    selectedStop = null;
    selectedVehicle = null;
    notifyListeners();
  }

  void selectStop(Stop stop) {
    selectedStop = stop;
    selectedVehicle = null;
    notifyListeners();
  }

  void selectVehicle(VehicleLocation vehicle) {
    selectedVehicle = vehicle;
    selectedStop = null;
    notifyListeners();
  }

  void clearSelection() {
    selectedStop = null;
    selectedVehicle = null;
    notifyListeners();
  }

  void toggleStops() {
    showStops = !showStops;
    notifyListeners();
  }

  void toggleVehicles() {
    showVehicles = !showVehicles;
    notifyListeners();
  }

  void fitBounds(MapController mapController) {
    final points = currentPoints;
    if (points.isEmpty) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLon = points.first.longitude;
    double maxLon = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    const padding = 0.012;
    final bounds = LatLngBounds(
      LatLng(minLat - padding, minLon - padding),
      LatLng(maxLat + padding, maxLon + padding),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(52)));
    });
  }

  List<Stop> _dedup(List<Stop> stops) {
    final seen = <String>{};
    return stops.where((s) => seen.add(s.stopId)).toList();
  }

  LatLng _projectOntoSegment(LatLng p, LatLng a, LatLng b) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    if (dx == 0 && dy == 0) return a;
    final t = (((p.longitude - a.longitude) * dx) +
            ((p.latitude - a.latitude) * dy)) /
        (dx * dx + dy * dy);
    final ct = t.clamp(0.0, 1.0);
    return LatLng(a.latitude + ct * dy, a.longitude + ct * dx);
  }

  double _bearing(LatLng start, LatLng end) {
    final la1 = _rad(start.latitude);
    final la2 = _rad(end.latitude);
    final dLon = _rad(end.longitude - start.longitude);
    final y = sin(dLon) * cos(la2);
    final x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double d) => d * pi / 180;
}
