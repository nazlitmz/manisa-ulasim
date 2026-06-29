/// Durak modeli (GTFS stops.txt)
class Stop {
  final String stopId;
  final String? stopCode;
  final String stopName;
  final String? stopDesc;
  final double latitude;
  final double longitude;
  final String? zoneId;
  final String? stopUrl;
  final int? locationType;
  final String? parentStation;
  final String? stopTimezone;
  final int? wheelchairBoarding;
  final String? levelId;
  final String? platformCode;
  final String? direction;
  final String? position;

  // Hesaplanan alan - kullanıcıya mesafe (metre)
  final double? distanceFromUser;

  // ✅ EKLENEN ALAN - Hat üzerindeki sıra numarası
  final int? stopSequence;

  Stop({
    required this.stopId,
    this.stopCode,
    required this.stopName,
    this.stopDesc,
    required this.latitude,
    required this.longitude,
    this.zoneId,
    this.stopUrl,
    this.locationType,
    this.parentStation,
    this.stopTimezone,
    this.wheelchairBoarding,
    this.levelId,
    this.platformCode,
    this.direction,
    this.position,
    this.distanceFromUser,
    this.stopSequence, // ✅ EKLENDI
  });

  /// Map'ten oluştur (veritabanından)
  factory Stop.fromMap(Map<String, dynamic> map) {
    return Stop(
      stopId: map['stop_id']?.toString() ?? '',
      stopCode: map['stop_code']?.toString(),
      stopName: map['stop_name']?.toString() ?? '',
      stopDesc: map['stop_desc']?.toString(),
      latitude: (map['stop_lat'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['stop_lon'] as num?)?.toDouble() ?? 0.0,
      zoneId: map['zone_id']?.toString(),
      stopUrl: map['stop_url']?.toString(),
      locationType: map['location_type'] as int?,
      parentStation: map['parent_station']?.toString(),
      stopTimezone: map['stop_timezone']?.toString(),
      wheelchairBoarding: map['wheelchair_boarding'] as int?,
      levelId: map['level_id']?.toString(),
      platformCode: map['platform_code']?.toString(),
      direction: map['direction']?.toString(),
      position: map['position']?.toString(),
      // ✅ EKLENDI - SQL sorgusundan gelen stop_sequence alanını oku
      stopSequence: (map['stop_sequence'] as num?)?.toInt(),
    );
  }

  /// Map'e dönüştür (veritabanına)
  Map<String, dynamic> toMap() {
    return {
      'stop_id': stopId,
      'stop_code': stopCode,
      'stop_name': stopName,
      'stop_desc': stopDesc,
      'stop_lat': latitude,
      'stop_lon': longitude,
      'zone_id': zoneId,
      'stop_url': stopUrl,
      'location_type': locationType,
      'parent_station': parentStation,
      'stop_timezone': stopTimezone,
      'wheelchair_boarding': wheelchairBoarding,
      'level_id': levelId,
      'platform_code': platformCode,
      'direction': direction,
      'position': position,
    };
  }

  /// Kopyala ve değiştir
  Stop copyWith({
    String? stopId,
    String? stopCode,
    String? stopName,
    String? stopDesc,
    double? latitude,
    double? longitude,
    String? zoneId,
    String? stopUrl,
    int? locationType,
    String? parentStation,
    String? stopTimezone,
    int? wheelchairBoarding,
    String? levelId,
    String? platformCode,
    String? direction,
    String? position,
    double? distanceFromUser,
    int? stopSequence, // ✅ EKLENDI
  }) {
    return Stop(
      stopId: stopId ?? this.stopId,
      stopCode: stopCode ?? this.stopCode,
      stopName: stopName ?? this.stopName,
      stopDesc: stopDesc ?? this.stopDesc,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      zoneId: zoneId ?? this.zoneId,
      stopUrl: stopUrl ?? this.stopUrl,
      locationType: locationType ?? this.locationType,
      parentStation: parentStation ?? this.parentStation,
      stopTimezone: stopTimezone ?? this.stopTimezone,
      wheelchairBoarding: wheelchairBoarding ?? this.wheelchairBoarding,
      levelId: levelId ?? this.levelId,
      platformCode: platformCode ?? this.platformCode,
      direction: direction ?? this.direction,
      position: position ?? this.position,
      distanceFromUser: distanceFromUser ?? this.distanceFromUser,
      stopSequence: stopSequence ?? this.stopSequence, // ✅ EKLENDI
    );
  }

  /// Tekerlekli sandalye erişimi var mı?
  bool get isWheelchairAccessible => wheelchairBoarding == 1;

  /// Tekerlekli sandalye bilgisi mevcut mu?
  bool get hasWheelchairInfo =>
      wheelchairBoarding != null && wheelchairBoarding != 0;

  /// Erişilebilirlik durumu metni
  String get accessibilityStatus {
    switch (wheelchairBoarding) {
      case 1:
        return 'Tekerlekli sandalye erişimine uygun';
      case 2:
        return 'Tekerlekli sandalye erişimi yok';
      default:
        return 'Erişilebilirlik bilgisi yok';
    }
  }

  /// Formatlanmış mesafe
  String get formattedDistance {
    if (distanceFromUser == null) return '';
    if (distanceFromUser! < 1000) {
      return '${distanceFromUser!.round()} m';
    }
    return '${(distanceFromUser! / 1000).toStringAsFixed(1)} km';
  }

  @override
  String toString() => 'Stop($stopId: $stopName, seq: $stopSequence)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Stop &&
          runtimeType == other.runtimeType &&
          stopId == other.stopId;

  @override
  int get hashCode => stopId.hashCode;
}

/// Sefer zamanı modeli (GTFS stop_times.txt)
class StopTime {
  final String tripId;
  final String stopId;
  final String arrivalTime;
  final String departureTime;
  final int stopSequence;

  StopTime({
    required this.tripId,
    required this.stopId,
    required this.arrivalTime,
    required this.departureTime,
    required this.stopSequence,
  });

  factory StopTime.fromMap(Map<String, dynamic> map) {
    return StopTime(
      tripId: map['trip_id']?.toString() ?? '',
      stopId: map['stop_id']?.toString() ?? '',
      arrivalTime: map['arrival_time']?.toString() ?? '',
      departureTime: map['departure_time']?.toString() ?? '',
      stopSequence: (map['stop_sequence'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'trip_id': tripId,
      'stop_id': stopId,
      'arrival_time': arrivalTime,
      'departure_time': departureTime,
      'stop_sequence': stopSequence,
    };
  }

  /// Kalkış saati formatı (HH:mm)
  String get formattedDeparture {
    if (departureTime.length >= 5) {
      return departureTime.substring(0, 5);
    }
    return departureTime;
  }
}

/// Sefer modeli (GTFS trips.txt)
class Trip {
  final String tripId;
  final String routeId;
  final String serviceId;
  final String? tripHeadsign;
  final int? directionId;
  final String? shapeId;

  Trip({
    required this.tripId,
    required this.routeId,
    required this.serviceId,
    this.tripHeadsign,
    this.directionId,
    this.shapeId,
  });

  factory Trip.fromMap(Map<String, dynamic> map) {
    return Trip(
      tripId: map['trip_id']?.toString() ?? '',
      routeId: map['route_id']?.toString() ?? '',
      serviceId: map['service_id']?.toString() ?? '',
      tripHeadsign: map['trip_headsign']?.toString(),
      directionId: map['direction_id'] as int?,
      shapeId: map['shape_id']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'trip_id': tripId,
      'route_id': routeId,
      'service_id': serviceId,
      'trip_headsign': tripHeadsign,
      'direction_id': directionId,
      'shape_id': shapeId,
    };
  }
}
