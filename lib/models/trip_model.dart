/// GTFS Trip (Sefer) modeli
class Trip {
  final String tripId;
  final String routeId;
  final String serviceId;
  final String? tripHeadsign;
  final String? tripShortName;
  final int? directionId; // 0: gidiş, 1: dönüş
  final String? blockId;
  final String? shapeId;
  final int? wheelchairAccessible; // 0: bilgi yok, 1: erişilebilir, 2: erişilemez
  final int? bikesAllowed; // 0: bilgi yok, 1: izin var, 2: izin yok
  
  Trip({
    required this.tripId,
    required this.routeId,
    required this.serviceId,
    this.tripHeadsign,
    this.tripShortName,
    this.directionId,
    this.blockId,
    this.shapeId,
    this.wheelchairAccessible,
    this.bikesAllowed,
  });
  
  /// CSV satırından Trip oluştur
  factory Trip.fromCsvRow(List<dynamic> row, Map<String, int> headers) {
    return Trip(
      tripId: row[headers['trip_id']!].toString(),
      routeId: row[headers['route_id']!].toString(),
      serviceId: row[headers['service_id']!].toString(),
      tripHeadsign: _getStringValue(row, headers, 'trip_headsign'),
      tripShortName: _getStringValue(row, headers, 'trip_short_name'),
      directionId: _getIntValue(row, headers, 'direction_id'),
      blockId: _getStringValue(row, headers, 'block_id'),
      shapeId: _getStringValue(row, headers, 'shape_id'),
      wheelchairAccessible: _getIntValue(row, headers, 'wheelchair_accessible'),
      bikesAllowed: _getIntValue(row, headers, 'bikes_allowed'),
    );
  }
  
  /// Veritabanından Trip oluştur
  factory Trip.fromMap(Map<String, dynamic> map) {
    return Trip(
      tripId: map['trip_id'],
      routeId: map['route_id'],
      serviceId: map['service_id'],
      tripHeadsign: map['trip_headsign'],
      tripShortName: map['trip_short_name'],
      directionId: map['direction_id'],
      blockId: map['block_id'],
      shapeId: map['shape_id'],
      wheelchairAccessible: map['wheelchair_accessible'],
      bikesAllowed: map['bikes_allowed'],
    );
  }
  
  /// Veritabanına kaydetmek için Map'e dönüştür
  Map<String, dynamic> toMap() {
    return {
      'trip_id': tripId,
      'route_id': routeId,
      'service_id': serviceId,
      'trip_headsign': tripHeadsign,
      'trip_short_name': tripShortName,
      'direction_id': directionId,
      'block_id': blockId,
      'shape_id': shapeId,
      'wheelchair_accessible': wheelchairAccessible,
      'bikes_allowed': bikesAllowed,
    };
  }
  
  /// Yön adı
  String get directionName {
    switch (directionId) {
      case 0: return 'Gidiş';
      case 1: return 'Dönüş';
      default: return '';
    }
  }
  
  /// Tekerlekli sandalye erişilebilirliği
  bool get isWheelchairAccessible => wheelchairAccessible == 1;
  
  /// Bisiklet izni
  bool get areBikesAllowed => bikesAllowed == 1;
  
  // Yardımcı fonksiyonlar
  static String? _getStringValue(List<dynamic> row, Map<String, int> headers, String key) {
    final index = headers[key];
    if (index == null || index >= row.length) return null;
    final value = row[index].toString().trim();
    return value.isEmpty ? null : value;
  }
  
  static int? _getIntValue(List<dynamic> row, Map<String, int> headers, String key) {
    final strValue = _getStringValue(row, headers, key);
    if (strValue == null) return null;
    return int.tryParse(strValue);
  }
  
  @override
  String toString() => 'Trip(id: $tripId, route: $routeId)';
}

/// GTFS StopTime (Durak Zamanı) modeli
class StopTime {
  final String tripId;
  final String arrivalTime;
  final String departureTime;
  final String stopId;
  final int stopSequence;
  final String? stopHeadsign;
  final int? pickupType;
  final int? dropOffType;
  final int? continuousPickup;
  final int? continuousDropOff;
  final double? shapeDistTraveled;
  final int? timepoint;
  
  StopTime({
    required this.tripId,
    required this.arrivalTime,
    required this.departureTime,
    required this.stopId,
    required this.stopSequence,
    this.stopHeadsign,
    this.pickupType,
    this.dropOffType,
    this.continuousPickup,
    this.continuousDropOff,
    this.shapeDistTraveled,
    this.timepoint,
  });
  
  /// CSV satırından StopTime oluştur
  factory StopTime.fromCsvRow(List<dynamic> row, Map<String, int> headers) {
    return StopTime(
      tripId: row[headers['trip_id']!].toString(),
      arrivalTime: row[headers['arrival_time']!].toString(),
      departureTime: row[headers['departure_time']!].toString(),
      stopId: row[headers['stop_id']!].toString(),
      stopSequence: int.parse(row[headers['stop_sequence']!].toString()),
      stopHeadsign: _getStringValue(row, headers, 'stop_headsign'),
      pickupType: _getIntValue(row, headers, 'pickup_type'),
      dropOffType: _getIntValue(row, headers, 'drop_off_type'),
      continuousPickup: _getIntValue(row, headers, 'continuous_pickup'),
      continuousDropOff: _getIntValue(row, headers, 'continuous_drop_off'),
      shapeDistTraveled: _getDoubleValue(row, headers, 'shape_dist_traveled'),
      timepoint: _getIntValue(row, headers, 'timepoint'),
    );
  }
  
  /// Veritabanından StopTime oluştur
  factory StopTime.fromMap(Map<String, dynamic> map) {
    return StopTime(
      tripId: map['trip_id'],
      arrivalTime: map['arrival_time'],
      departureTime: map['departure_time'],
      stopId: map['stop_id'],
      stopSequence: map['stop_sequence'],
      stopHeadsign: map['stop_headsign'],
      pickupType: map['pickup_type'],
      dropOffType: map['drop_off_type'],
      continuousPickup: map['continuous_pickup'],
      continuousDropOff: map['continuous_drop_off'],
      shapeDistTraveled: map['shape_dist_traveled'],
      timepoint: map['timepoint'],
    );
  }
  
  /// Veritabanına kaydetmek için Map'e dönüştür
  Map<String, dynamic> toMap() {
    return {
      'trip_id': tripId,
      'arrival_time': arrivalTime,
      'departure_time': departureTime,
      'stop_id': stopId,
      'stop_sequence': stopSequence,
      'stop_headsign': stopHeadsign,
      'pickup_type': pickupType,
      'drop_off_type': dropOffType,
      'continuous_pickup': continuousPickup,
      'continuous_drop_off': continuousDropOff,
      'shape_dist_traveled': shapeDistTraveled,
      'timepoint': timepoint,
    };
  }
  
  /// Varış saatini DateTime olarak al
  DateTime? get arrivalDateTime {
    return _parseTime(arrivalTime);
  }
  
  /// Kalkış saatini DateTime olarak al
  DateTime? get departureDateTime {
    return _parseTime(departureTime);
  }
  
  /// Formatlanmış varış saati (HH:mm)
  String get formattedArrivalTime {
    return _formatTime(arrivalTime);
  }
  
  /// Formatlanmış kalkış saati (HH:mm)
  String get formattedDepartureTime {
    return _formatTime(departureTime);
  }
  
  /// GTFS zamanını parse et (24:00:00 üstü değerler olabilir)
  DateTime? _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        int hours = int.parse(parts[0]);
        int minutes = int.parse(parts[1]);
        
        // Gece yarısını geçen saatler
        final now = DateTime.now();
        var date = DateTime(now.year, now.month, now.day);
        
        if (hours >= 24) {
          date = date.add(const Duration(days: 1));
          hours -= 24;
        }
        
        return date.add(Duration(hours: hours, minutes: minutes));
      }
    } catch (_) {}
    return null;
  }
  
  /// Zamanı HH:mm formatında döndür
  String _formatTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        int hours = int.parse(parts[0]) % 24;
        int minutes = int.parse(parts[1]);
        return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
      }
    } catch (_) {}
    return timeStr;
  }
  
  // Yardımcı fonksiyonlar
  static String? _getStringValue(List<dynamic> row, Map<String, int> headers, String key) {
    final index = headers[key];
    if (index == null || index >= row.length) return null;
    final value = row[index].toString().trim();
    return value.isEmpty ? null : value;
  }
  
  static int? _getIntValue(List<dynamic> row, Map<String, int> headers, String key) {
    final strValue = _getStringValue(row, headers, key);
    if (strValue == null) return null;
    return int.tryParse(strValue);
  }
  
  static double? _getDoubleValue(List<dynamic> row, Map<String, int> headers, String key) {
    final strValue = _getStringValue(row, headers, key);
    if (strValue == null) return null;
    return double.tryParse(strValue);
  }
  
  @override
  String toString() => 'StopTime(trip: $tripId, stop: $stopId, seq: $stopSequence)';
}
