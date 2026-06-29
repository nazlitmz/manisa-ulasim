// lib/models/vehicle_location_model.dart
class VehicleLocation {
  final String id;
  final String name;
  final String? driverName;
  final GpsData gps;
  final String? routeId;
  final String? direction;
  final DateTime? lastUpdate;

  VehicleLocation({
    required this.id,
    required this.name,
    this.driverName,
    required this.gps,
    this.routeId,
    this.direction,
    this.lastUpdate,
  });

  factory VehicleLocation.fromJson(Map<String, dynamic> json) {
    return VehicleLocation(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      driverName: json['driver_name'] as String?,
      gps: GpsData.fromJson(json['gps'] as Map<String, dynamic>? ?? {}),
      routeId: json['route_id'] as String?,
      direction: json['direction'] as String?,
      lastUpdate: json['last_update'] != null
          ? DateTime.parse(json['last_update'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'driver_name': driverName,
      'gps': gps.toJson(),
      'route_id': routeId,
      'direction': direction,
      'last_update': lastUpdate?.toIso8601String(),
    };
  }

  VehicleLocation copyWith({
    String? id,
    String? name,
    String? driverName,
    GpsData? gps,
    String? routeId,
    String? direction,
    DateTime? lastUpdate,
  }) {
    return VehicleLocation(
      id: id ?? this.id,
      name: name ?? this.name,
      driverName: driverName ?? this.driverName,
      gps: gps ?? this.gps,
      routeId: routeId ?? this.routeId,
      direction: direction ?? this.direction,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }

  @override
  String toString() {
    return 'VehicleLocation(id: $id, name: $name, driver: $driverName, '
        'lat: ${gps.latitude}, lon: ${gps.longitude})';
  }
}

class GpsData {
  final double latitude;
  final double longitude;
  final double? speed;
  final double? heading;
  final double? accuracy;

  GpsData({
    required this.latitude,
    required this.longitude,
    this.speed,
    this.heading,
    this.accuracy,
  });

  factory GpsData.fromJson(Map<String, dynamic> json) {
    return GpsData(
      latitude: (json['lat'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['lon'] as num?)?.toDouble() ?? 0.0,
      speed: (json['speed'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': latitude,
      'lon': longitude,
      'speed': speed,
      'heading': heading,
      'accuracy': accuracy,
    };
  }

  GpsData copyWith({
    double? latitude,
    double? longitude,
    double? speed,
    double? heading,
    double? accuracy,
  }) {
    return GpsData(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      accuracy: accuracy ?? this.accuracy,
    );
  }

  @override
  String toString() {
    return 'GpsData(lat: $latitude, lon: $longitude, speed: $speed)';
  }
}
